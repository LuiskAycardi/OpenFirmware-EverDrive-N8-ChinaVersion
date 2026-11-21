#!/usr/bin/env python3
"""probar_parche.py — Banco del parche FDS (etapa F2): la BIOS del usuario, parcheada, arranca un .fds en una máquina
que imita el N8 con nuestro mapper_fds.v (GPL-3.0-or-later, código propio).

  python3 -I tools/fds/probar_parche.py --bios BIOS.bin [--parche os/build/fds_parche.bin] JUEGO.fds [...]

Para cada .fds: copia las caras a la SRAM PRG (cara k en k*64 KiB), el bloque del parche a 0x7D000 (con el número de
caras en 0x7DFFF) y la BIOS a 0x7E000, le aplica la tabla de enganches del bloque y arranca desde el vector de reset.
Da por buena la carga cuando la BIOS salta al juego (el PC pasa a $6000-$DFFF) y los archivos de arranque de la cara
1 están en la RAM ($6000-$DFFF) o en la VRAM tal y como vienen en el disco.

La máquina: 6502 de tools/bios (sin ciclos reales: una NMI cada ~29780/3 instrucciones), PPU mínima (registros,
VRAM de 16 KiB, vblank), mando sin pulsar, y el mapper como en hdl/rtl/mapper_fds.v: BIOS en $E000, RAM en
$6000-$DFFF, parche en $5000, ventana de 1 KiB en $4800 con la cabeza en $4213/$4214 ($4215 avanza), cara en $4212.
Ni la BIOS ni los juegos están en el repositorio: se pasan por la línea de órdenes.

Con --api, después del arranque llama a la BIOS desde la RAM de la CPU: LoadFiles ($E1F8) con el ID de la cara 2
(cambio de cara automático), archivo por archivo, y WriteFile ($E239) con el último archivo de la cara 1 cambiado en
su primer byte (escritura en el disco: solo debe cambiar ese byte de la imagen).
"""
import argparse
import os
import sys
import zlib

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
sys.path.insert(0, AQUI)
sys.path.insert(0, os.path.join(RAIZ, 'tools', 'bios'))
import fds  # noqa: E402
from cpu6502 import CPU  # noqa: E402

INSTR_FOTOGRAMA = 29780 // 3


class Maquina:
    def __init__(self, bios, parche, caras):
        self.sram = bytearray(512 * 1024)
        for k, c in enumerate(caras):
            self.sram[k * 0x10000:k * 0x10000 + len(c)] = c
        self.sram[0x7D000:0x7D000 + len(parche)] = parche
        self.sram[0x7DFFF] = len(caras)
        b = bytearray(bios)
        self.enganches = aplicar(b, parche)
        self.sram[0x7E000:0x80000] = b
        self.ram = bytearray(0x800)
        self.wram = bytearray(0x8000)               # $6000-$DFFF
        self.vram = bytearray(0x4000)
        self.ppuctrl = self.ppumask = 0
        self.ppuaddr = 0
        self.latch = 0
        self.vblank = 0
        self.leido = 0
        # mapper
        self.cara = self.cabeza = self.apoyo = 0
        self.ventana = 0
        self.mir_h = 0
        self.escrituras_disco = 0
        self.cpu = CPU(self.rd, self.wr)

    # ------------------------------------------------------------------ memoria de la CPU
    def rd(self, a):
        if a < 0x2000:
            return self.ram[a & 0x7FF]
        if a < 0x4000:
            r = a & 7
            if r == 2:
                v = (self.vblank << 7)
                self.vblank = 0
                self.latch = 0
                return v
            if r == 7:
                v = self.leido
                self.leido = self.vram[self.ppuaddr & 0x3FFF]
                self.ppuaddr = (self.ppuaddr + (32 if self.ppuctrl & 4 else 1)) & 0x3FFF
                return v
            return 0
        if a < 0x4020:
            return 0x40 if a == 0x4016 or a == 0x4017 else 0
        if 0x4000 <= a < 0x4200:
            return a >> 8                            # en el N8 de NES aquí no llega nada: bus abierto
        if a == 0x4212:
            return self.cara
        if a == 0x4213:
            return self.cabeza & 0xFF
        if a == 0x4214:
            return self.cabeza >> 8
        if a == 0x4216:
            return self.apoyo
        if 0x4800 <= a < 0x4C00 and self.ventana:
            return self.sram[self.dir_ventana(a)]
        if 0x5000 <= a < 0x6000:
            return self.sram[0x7D000 + (a & 0xFFF)]
        if 0x6000 <= a < 0xE000:
            return self.wram[a - 0x6000]
        if a >= 0xE000:
            return self.sram[0x7E000 + (a & 0x1FFF)]
        return a >> 8

    def dir_ventana(self, a):
        return (self.cara << 16) | (self.cabeza & 0xFC00) | (a & 0x3FF)

    def wr(self, a, v):
        if a < 0x2000:
            self.ram[a & 0x7FF] = v
        elif a < 0x4000:
            r = a & 7
            if r == 0:
                self.ppuctrl = v
            elif r == 1:
                self.ppumask = v
            elif r == 6:
                if self.latch == 0:
                    self.ppuaddr = (self.ppuaddr & 0xFF) | ((v & 0x3F) << 8)
                else:
                    self.ppuaddr = (self.ppuaddr & 0x3F00) | v
                self.latch ^= 1
            elif r == 7:
                self.vram[self.ppuaddr & 0x3FFF] = v
                self.ppuaddr = (self.ppuaddr + (32 if self.ppuctrl & 4 else 1)) & 0x3FFF
        elif a == 0x4025:
            self.mir_h = (v >> 3) & 1
        elif a == 0x4210:
            self.ventana = v & 1
        elif a == 0x4212:
            self.cara = v & 7
        elif a == 0x4213:
            self.cabeza = (self.cabeza & 0xFF00) | v
        elif a == 0x4214:
            self.cabeza = (self.cabeza & 0xFF) | (v << 8)
        elif a == 0x4215:
            self.cabeza = (self.cabeza + 1) & 0xFFFF
        elif a == 0x4216:
            self.apoyo = v
        elif 0x4800 <= a < 0x4C00 and self.ventana:
            self.sram[self.dir_ventana(a)] = v
            self.escrituras_disco += 1
        elif 0x6000 <= a < 0xE000:
            self.wram[a - 0x6000] = v

    # ------------------------------------------------------------------ ejecución
    def correr(self, max_fotogramas):
        """Arranca desde el reset. 'juego' cuando la BIOS salta al vector de reset del juego ($DFFC, en la RAM)."""
        cpu = self.cpu
        cpu.reset()
        prev = cpu.pc
        for f in range(max_fotogramas):
            for _ in range(INSTR_FOTOGRAMA):
                pc = cpu.pc
                if prev >= 0xE000 and pc < 0xE000:
                    vec = self.wram[0xDFFC - 0x6000] | self.wram[0xDFFD - 0x6000] << 8
                    if pc == vec:
                        return 'juego', f, pc
                prev = pc
                if not cpu.paso():
                    return 'ilegal', f, cpu.ilegal
            self.vblank = 1
            if self.ppuctrl & 0x80:
                prev = 0                                # la NMI entra por la BIOS: no es el salto al juego
                cpu.nmi()
        return 'tiempo', max_fotogramas, cpu.pc


ZONAS = (0x0400, 0x0200, 0x0600)                    # código y datos de prueba (0x180 bytes) en la RAM de la CPU


def zona_libre(dire, tam):
    """Una zona de la RAM de la CPU para el código de prueba que no pise [dire, dire + tam)."""
    for z in ZONAS:
        if dire + tam <= z or dire >= z + 0x180:
            return z
    return ZONAS[0]


def llamar(m, rutina, params, a=0, zona=ZONAS[0], max_instr=40_000_000):
    """JSR rutina con los parámetros en línea (palabras), A = a; devuelve (A al volver, Y) o None si no vuelve."""
    codigo = [0x20, rutina & 0xFF, rutina >> 8]
    for w in params:
        codigo += [w & 0xFF, w >> 8]
    fin = zona + len(codigo)
    res = zona + 0x170
    codigo += [0x8D, res & 0xFF, res >> 8, 0x8C, (res + 1) & 0xFF, (res + 1) >> 8,
               0x4C, (fin + 6) & 0xFF, (fin + 6) >> 8]
    for i, b in enumerate(codigo):
        m.ram[zona + i] = b
    m.ppuctrl = 0                                    # sin NMI del juego mientras tanto
    cpu = m.cpu
    cpu.pc, cpu.a, cpu.s, cpu.i = zona, a, 0xFF, 1
    for _ in range(max_instr):
        if cpu.pc == fin + 6:
            return m.ram[res], m.ram[res + 1]
        if not cpu.paso():
            return None
    return None


def poner(m, dire, datos):
    for i, b in enumerate(datos):
        m.ram[dire + i] = b


def prueba_api(m, caras):
    """Cara 2 (si la hay) y escritura en la cara 1. Devuelve una lista de (bien, texto)."""
    res = []
    if len(caras) > 1:
        c2 = fds.leer_cara(caras[1])
        vistos = set()
        for a in reversed(c2['archivos']):             # el último de cada ID es el que queda en memoria
            if a['id'] in vistos or a['oculto']:
                continue
            vistos.add(a['id'])
            z = zona_libre(a['dir'], len(a['datos'])) if a['tipo'] == 0 else ZONAS[0]
            datos = z + 0x80
            poner(m, datos, caras[1][15:25])         # ID de la cara 2
            poner(m, datos + 0x10, [a['id'], 0xFF])
            r = llamar(m, 0xE1F8, [datos, datos + 0x10], zona=z)
            d = a['datos']
            if a['tipo'] == 0:
                if a['dir'] + len(d) <= 0x0800:
                    ok = bytes(m.ram[a['dir']:a['dir'] + len(d)]) == d
                else:
                    ok = 0x6000 <= a['dir'] and a['dir'] + len(d) <= 0xE000 and \
                        bytes(m.wram[a['dir'] - 0x6000:a['dir'] - 0x6000 + len(d)]) == d
            else:
                ok = bytes(m.vram[a['dir']:a['dir'] + len(d)]) == d
            ok = ok and r is not None and r[0] == 0 and m.cara == 1
            res.append((ok, f'cara 2: LoadFiles {a["nombre"]!r} (id {a["id"]:02X}): '
                            f'{"bien" if ok else f"MAL (A, Y = {r}, cara {m.cara})"}'))
    # escritura: el último archivo de la cara 1, con el primer byte cambiado
    c1 = fds.leer_cara(caras[0])
    arch = [x for x in c1['archivos'] if not x['oculto']]
    a = arch[-1]
    n = len(arch) - 1
    d = bytearray(a['datos'])
    if 0 < len(d) <= 0xC0:
        d[0] ^= 0xFF
        z = zona_libre(a['dir'], len(d)) if a['tipo'] == 0 else ZONAS[0]
        datos = z + 0x80
        cab = bytes(a['cab'][2:16]) + bytes([(datos + 0x30) & 0xFF, (datos + 0x30) >> 8, 0])   # id, nombre, dir., tamaño, tipo
        poner(m, datos, caras[0][15:25])
        poner(m, datos + 0x10, cab)
        poner(m, datos + 0x30, d)
        antes = bytes(m.sram[0:len(caras[0])])
        r = llamar(m, 0xE239, [datos, datos + 0x10], a=n, zona=z)
        despues = bytes(m.sram[0:len(caras[0])])
        difs = [i for i in range(len(antes)) if antes[i] != despues[i]]
        ok = r is not None and r[0] == 0 and len(difs) == 1 and despues[difs[0]] == d[0]
        res.append((ok, f'cara 1: WriteFile {a["nombre"]!r} (archivo {n}, {len(d)} B): '
                        f'{"bien" if ok else "MAL"} (A, Y = {r}; bytes cambiados en la imagen: {len(difs)})'))
    else:
        res.append((True, f'cara 1: sin escritura (el último archivo mide {len(d)} B)'))
    return res


def aplicar(bios, parche):
    """Aplica a la BIOS (bytearray de 8 KiB) la tabla de enganches del bloque del parche. Devuelve la lista."""
    assert parche[:5] == b'N8FDS', 'el bloque del parche no empieza por N8FDS'
    p = (parche[6] | parche[7] << 8) - 0x5000
    hechos = []
    while True:
        dire = parche[p] | parche[p + 1] << 8
        if dire == 0:
            return hechos
        n = parche[p + 2]
        datos = parche[p + 3:p + 3 + n]
        bios[dire - 0xE000:dire - 0xE000 + n] = datos
        hechos.append((dire, bytes(datos)))
        p += 3 + n


def comprobar_carga(m, cara):
    """Archivos de arranque de la cara, en el orden del disco (uno posterior pisa a uno anterior en la misma
    dirección): monta la imagen esperada de la RAM de la CPU, la RAM del FDS y la VRAM y la compara byte a byte con
    la máquina. Devuelve (bien, mal, detalles)."""
    r = fds.leer_cara(cara)
    arranque = r.get('arranque', 0)
    cpu, ppu, det = {}, {}, []
    for a in r['archivos']:
        if a['id'] > arranque or a['oculto']:
            continue
        dest = cpu if a['tipo'] == 0 else ppu
        for i, b in enumerate(a['datos']):
            dest[(a['dir'] + i) & (0xFFFF if a['tipo'] == 0 else 0x3FFF)] = (b, a['nombre'])
        det.append(f'{a["nombre"]:8s} id {a["id"]:02X} {len(a["datos"]):5d} B '
                   f'{"RAM" if a["tipo"] == 0 else "VRAM"} ${a["dir"]:04X}')
    mal = {}
    for d, (b, n) in cpu.items():
        if d < 0x2000:
            v = m.ram[d & 0x7FF]
        elif 0x6000 <= d < 0xE000:
            v = m.wram[d - 0x6000]
        else:
            continue                                  # registros o la BIOS: no se puede cargar ahí
        if v != b:
            mal[n] = mal.get(n, 0) + 1
    for d, (b, n) in ppu.items():
        if d >= 0x3F00:
            continue                                  # paletas: la PPU mínima no las separa
        if m.vram[d] != b:
            mal[n] = mal.get(n, 0) + 1
    for n, k in mal.items():
        det.append(f'  {n}: {k} bytes distintos')
    return len(det) - len(mal), len(mal), det


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bios', required=True)
    ap.add_argument('--parche', default=os.path.join(RAIZ, 'os', 'build', 'fds_parche.bin'))
    ap.add_argument('--fotogramas', type=int, default=900)
    ap.add_argument('-v', '--detalle', action='store_true')
    ap.add_argument('--api', action='store_true', help='probar también LoadFiles en la cara 2 y WriteFile')
    ap.add_argument('fds', nargs='+')
    a = ap.parse_args()
    bios = open(a.bios, 'rb').read()
    crc, nombre, estado, texto = fds.bios_info(bios)
    print(f'BIOS {nombre or "?"} ({crc:08X}): {estado} — {texto}')
    if estado != 'si':
        sys.exit('esta BIOS no se puede parchear')
    parche = open(a.parche, 'rb').read()
    fallos = 0
    for ruta in a.fds:
        caras, _ = fds.caras(open(ruta, 'rb').read())
        m = Maquina(bios, parche, caras)
        como, f, pc = m.correr(a.fotogramas)
        nom = os.path.basename(ruta)
        if como != 'juego':
            fallos += 1
            print(f'FALLO {nom}: {como} (fotograma {f}, PC {pc if isinstance(pc, tuple) else f"${pc:04X}"})')
            continue
        bien, mal, det = comprobar_carga(m, caras[0])
        ok = mal == 0 and bien > 0
        fallos += not ok
        print(f'{"ok   " if ok else "FALLO"} {nom}: salta al juego en ${pc:04X} (fotograma {f}); '
              f'{bien} archivos de arranque bien, {mal} mal; cabeza {m.cabeza}, cara {m.cara}, '
              f'{m.escrituras_disco} escrituras en el disco')
        if a.detalle or not ok:
            for d in det:
                print('      ' + d)
        if a.api and ok:
            for bien_api, texto in prueba_api(m, caras):
                fallos += not bien_api
                print(f'      {"ok   " if bien_api else "FALLO"} {texto}')
    sys.exit(1 if fallos else 0)


if __name__ == '__main__':
    main()
