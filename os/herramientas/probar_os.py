#!/usr/bin/env python3
"""probar_os.py --bios BIOS.bin --rbf 255.RBF --trabajo DIR — Prueba el OS (etapa 5) con la BIOS real en el modelo
de tools/bios: arranque y resets, mando, lectura de la SD (FAT16/FAT32, SDHC/SDSC, con y sin MBR, raíz con cadena
de clústeres, reset a mitad de lectura, tarjeta muda) y lanzamiento de juegos (carga del RBF, PRG, CHR, registros,
salto, vuelta al menú y errores), carpetas (entrar, volver, páginas, vuelta de un juego dentro de una carpeta) y
nombres largos (acentos, cortados, ocultos, borrados) y partidas con pila (crear, cargar, guardar al volver y al
encender, nombres largos, carpeta ampliada, FAT16, SDSC, tarjeta que no deja escribir). Comprueba que solo escribe
en la tarjeta las partidas (y lo que la FAT necesita para crearlas, validado con fsck.fat) y nunca en la flash."""
import argparse, os, pathlib, shutil, subprocess, sys

RAIZ = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / 'tools/bios'))
from maquina import Maquina, SD   # noqa: E402

p = argparse.ArgumentParser()
p.add_argument('--bios', required=True)
p.add_argument('--rbf', required=True)
p.add_argument('--trabajo', required=True)
p.add_argument('--os', default=str(RAIZ / 'os/build/OS.BIN'))
a = p.parse_args()
t = pathlib.Path(a.trabajo)
t.mkdir(parents=True, exist_ok=True)
(t / 'edfc').mkdir(exist_ok=True)
shutil.copy(a.os, t / 'edfc/OS.BIN')
shutil.copy(a.rbf, t / 'edfc/255.RBF')
os.environ.setdefault('MTOOLS_SKIP_CHECK', '1')
os.environ['LC_ALL'] = 'C.UTF-8'          # mtools: nombres largos con acentos
bios = pathlib.Path(a.bios).read_bytes()

def imagen(nombre, fat, mbr, archivos):
    """Imagen con EDFC, una carpeta y `archivos` (nombre -> tamaño) en la raíz, en ese orden."""
    img = t / nombre
    subprocess.run(['sh', str(RAIZ / 'tools/bios/hacer_sd.sh'), str(img), str(fat), 'si' if mbr else 'no',
                    str(t / 'edfc')], check=True, stdout=subprocess.DEVNULL)
    dest = f'{img}@@{8192 * 512}' if mbr else str(img)
    subprocess.run(['mmd', '-i', dest, '::PRUEBAS'], check=True)
    for n, tam in archivos:
        f = t / 'tmp.bin'
        f.write_bytes(bytes((i * 31 + len(n)) & 0xFF for i in range(tam)))
        subprocess.run(['mcopy', '-i', dest, str(f), f'::{n}'], check=True)
    return img

fallos = []
def comprobar(cond, texto):
    print(('ok    ' if cond else 'FALLO ') + texto)
    if not cond:
        fallos.append(texto)

def particion(m, desp=8192 * 512):
    f = t / 'part.img'
    f.write_bytes(bytes(m.sd.img[desp:]) if isinstance(m, Maquina) else m[desp:])
    return f

def fsck(m, desp=8192 * 512):
    """Avisos de fsck.fat -n (sin el de la FSInfo «sin calcular», que es lo que deja el OS a propósito)."""
    r = subprocess.run(['fsck.fat', '-n', str(particion(m, desp))], capture_output=True, text=True)
    avisos = [l for l in r.stdout.split('\n') if l and not l.startswith('fsck.fat ') and 'files,' not in l
              and 'Free cluster summary uninitialized' not in l]
    return avisos + ([f'salida {r.returncode}'] if r.returncode else [])

def leer_archivo(m, ruta, desp=8192 * 512):
    f = t / 'sacado.bin'
    f.unlink(missing_ok=True)
    r = subprocess.run(['mcopy', '-n', '-i', str(particion(m, desp)), f'::{ruta}', str(f)], capture_output=True)
    return f.read_bytes() if r.returncode == 0 else None

def nombres_save(m, desp=8192 * 512):
    r = subprocess.run(['mdir', '-b', '-i', str(particion(m, desp)), '::EDFC/SAVE'], capture_output=True, text=True)
    return sorted(l.rsplit('/', 1)[-1] for l in r.stdout.split('\n') if l.strip())

etiquetas = {}
for linea in (pathlib.Path(a.os).parent / 'os.lbl').read_text().split('\n'):
    if linea.startswith('al '):
        _, dire, nombre = linea.split()
        etiquetas[nombre.lstrip('.')] = int(dire, 16)

def lista(pan):
    """Las entradas de la lista (filas 9-24), sin el cursor."""
    return [l[3:].lstrip(' ▶') for l in pan.split('\n') if 9 <= int(l[:2]) <= 24]

def cursor_en(pan, texto):
    return any(l[3:] == ' ▶' + texto for l in pan.split('\n') if 9 <= int(l[:2]) <= 24)

def sin_cursor(pan):
    return not any('▶' in l for l in pan.split('\n') if 9 <= int(l[:2]) <= 24)

def cabecera(pan):
    return ' '.join(next((l[3:] for l in pan.split('\n') if l[:2] == ' 7'), '').split())

def lista_raiz(pan):
    filas = [l[3:] for l in pan.split('\n')]
    return (any(l.strip().startswith('Raíz') and l.rstrip().endswith('1/1') for l in filas)
            and [l.strip(' ▶') for l in filas if l.startswith(' ') and l.strip(' ▶') in
                 ('EDFC/', 'PRUEBAS/', 'IRQ65', 'Super Mario Bros. (World)', 'ZELDA', 'NOTAS.TXT')]
            == ['EDFC/', 'PRUEBAS/', 'IRQ65', 'Super Mario Bros. (World)', 'ZELDA', 'NOTAS.TXT'])

def arrancar(img, sdhc=True, sd=None):
    m = Maquina(bios, sd or SD(pathlib.Path(img).read_bytes(), sdhc=sdhc))
    ok = m.arrancar_bios() == 'parada' and m.cpu.pc == 0x8000
    m.n_log = len(m.log)
    m.partidas = bytes(m.prgram[:0x12000])
    m.prg_antes = dict(m.escrituras_prgram)
    return m, ok

def estado(m, nombre):
    return m.prgram[0x18000 | (etiquetas[nombre] & 0x7FFF)]
def contadores(m):
    return estado(m, 'arranques'), estado(m, 'resets'), estado(m, 'vueltas')
def solo_lectura(m):
    ordenes = {e[0] for e in m.log[m.n_log:] if e[0].startswith('SD_')}
    return not m.sd.escrituras and ordenes <= {'SD_CMD0', 'SD_CMD8', 'SD_CMD55', 'SD_ACMD41', 'SD_CMD58', 'SD_CMD16',
                                               'SD_CMD17', 'SD_CMD18', 'SD_CMD12'}
PASOS = 2_500_000

def toca(m, mascara):
    m.pad = mascara; m.correr(30_000, nmi_cada=9000); m.pad = 0; m.correr(30_000, nmi_cada=9000)

def pulsa(m, mascara, despues=150_000):
    """Pulsa y espera a que la página nueva termine de subir a la PPU (2 filas por fotograma)."""
    toca(m, mascara)
    m.correr(despues, nmi_cada=9000)

ARCHIVOS = [('IRQ65.NES', 24592), ('Super Mario Bros. (World).nes', 40976), ('ZELDA.NES', 131088), ('NOTAS.TXT', 300)]

# ------------------------------------------------------------------ FAT32 con MBR, SDHC: el caso de la SD real
img32 = imagen('f32.img', 32, True, ARCHIVOS)
m, ok = arrancar(img32)
comprobar(ok, 'la BIOS salta a $8000')
r = m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(r == 'limite', 'el OS sigue corriendo (sin opcodes ilegales)')
comprobar('OS propio N8 - etapa 5' in pan and 'Arranque: frío (BIOS)' in pan and contadores(m) == (1, 0, 0),
          'encendido: FRIO, contadores 1/0/0')
comprobar(m.ppu_mask & 0x08 and m.ppu_ctrl & 0x80, 'fondo visible y NMI activa')
comprobar('SD: SDHC FAT32 clúster 01' in pan, 'tarjeta SDHC, FAT32')
comprobar(lista_raiz(pan), 'la raíz: cabecera «Raíz 1/1» y las 6 entradas, en orden')
comprobar(lista(pan) == ['EDFC/', 'PRUEBAS/', 'IRQ65', 'Super Mario Bros. (World)', 'ZELDA', 'NOTAS.TXT'],
          f'en la lista: {lista(pan)}')
comprobar('▶EDFC/' in pan and '.NES' not in pan and '.nes' not in pan,
          'cursor en la primera entrada; sin la extensión .nes (nombre largo y 8.3)')
comprobar(m.cpld[2] == 0x0B, f'reg 2 al terminar = $0B: rápido, tarjeta libre, SDHC (${m.cpld[2]:02X})')
comprobar(solo_lectura(m), 'solo órdenes de lectura; ninguna escritura en la tarjeta')
m.pad = 0x80 | 0x20
m.correr(60_000, nmi_cada=9000)
comprobar('Mando: A - S - - - - -' in m.pantalla(), 'el mando se ve en vivo (Select+A)')
m.pad = 0

# resets: en el OS, en ráfaga (alguno a mitad de la lectura de la SD) y vuelta de un juego
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
comprobar('Arranque: reset' in m.pantalla() and contadores(m) == (2, 1, 0) and lista_raiz(m.pantalla()),
          'reset en el OS: RESET 2/1/0 y la SD se vuelve a leer bien')
for pasos in (500, 3000, 20_000, 60_000, 150_000, 400_000):      # los últimos caen dentro de la lectura de la SD
    m.correr(pasos, nmi_cada=9000)
    m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Arranque: reset' in pan and contadores(m) == (8, 7, 0) and lista_raiz(pan) and 'error' not in pan,
          f'ráfaga de 6 resets, algunos a mitad de lectura: contadores {contadores(m)} y la SD bien')
m.prgram[0x18000 | (etiquetas['en_juego'] & 0x7FFF)] = 1
m.cpld[9] = 0x15
m.cpld[2] = 0x0D                          # tarjeta seleccionada y en ráfaga, como si se hubiera cortado una lectura
for i in range(0x800):
    m.ram[i] = 0xA5
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Arranque: vuelta de juego' in pan and contadores(m) == (9, 7, 1) and lista_raiz(pan),
          'vuelta de un juego: VUELTA DE JUEGO 9/7/1 y la SD bien')
comprobar(estado(m, 'en_juego') == 0 and m.cpld[9] == 1, 'marca en_juego borrada y reg 9 = 01')
cpld = [e for e in m.log[m.n_log:] if e[0] == 'CPLD']
comprobar(all(e[1] in (2, 9) for e in cpld) and all(e[3] == 1 for e in cpld if e[1] == 9),
          'del CPLD solo escribe el reg 2 (SD) y reg 9 = 01')
otros = [e for e in m.log[m.n_log:] if e[0] in ('4402', 'ESCRITURA_EN_FLASH', 'USB_TX') or (e[0] == 'FPGA' and e[1] not in (129, 130))]
comprobar(not otros, f'no toca la flash, $4402 ni otros registros del FPGA que el 129 (marca de partida) y el 130 ({otros[:3]})')
comprobar(dict(m.escrituras_prgram) == m.prg_antes and bytes(m.prgram[:0x12000]) == m.partidas,
          'no toca la PRG-RAM fuera de su imagen')
comprobar(solo_lectura(m) and bytes(m.sd.img) == pathlib.Path(img32).read_bytes(), 'la imagen de la SD queda idéntica')

# ------------------------------------------------------------------ otras tarjetas
m, ok = arrancar(img32, sdhc=False)
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('SD: SDSC FAT32' in pan and lista_raiz(pan) and m.cpld[2] == 0x03,
          'SDSC (direcciones en bytes): misma lista; reg 2 = $03')

m, ok = arrancar(imagen('f16.img', 16, True, ARCHIVOS))
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('SD: SDHC FAT16 clúster' in pan and lista_raiz(pan), 'FAT16 con MBR')

m, ok = arrancar(imagen('f32nombr.img', 32, False, ARCHIVOS))
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('FAT32' in pan and lista_raiz(pan), 'FAT32 sin MBR (sin particiones)')

muchos = [(f'J{i:03d}.NES', 16 + i) for i in range(60)]
for fat in (32, 16):
    m, ok = arrancar(imagen(f'muchos{fat}.img', fat, True, muchos))
    m.correr(PASOS + 1_500_000, nmi_cada=9000)
    pan = m.pantalla()
    comprobar(cabecera(pan) == 'Raíz 1/4' and lista(pan)[-1] == 'J013' and len(lista(pan)) == 16 and 'error' not in pan,
              f'FAT{fat}: raíz de 62 entradas (varios sectores{" y cadena de clústeres" if fat == 32 else ""}): 4 páginas de 16')
    for _ in range(3):
        pulsa(m, 0x02)                    # izquierda: de la 1 a la 4, 3 y 2
    pan = m.pantalla()
    comprobar(cabecera(pan) == 'Raíz 2/4' and lista(pan) == [f'J{i:03d}' for i in range(14, 30)] and cursor_en(pan, 'J014'),
              f'FAT{fat}: izquierda da la vuelta (1 -> 4 -> 3 -> 2) y la página 2 son J014-J029')
    pulsa(m, 0x01)
    pulsa(m, 0x01)
    pan = m.pantalla()
    comprobar(cabecera(pan) == 'Raíz 4/4' and lista(pan) == [f'J{i:03d}' for i in range(46, 60)],
              f'FAT{fat}: derecha dos veces: la última página, con 14')
    comprobar(solo_lectura(m), f'FAT{fat}: solo lectura')

class SDmuda(SD):
    def byte(self, v, cs):
        return 0xFF
m, ok = arrancar(img32)
m.sd.__class__ = SDmuda                   # la tarjeta deja de contestar después de que la BIOS cargue el OS
r = m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(r == 'limite' and 'SD: error 01 R1=FF' in pan and 'Mando:' in pan and m.ppu_mask & 0x08,
          'tarjeta muda: ERROR 01 en pantalla y el OS sigue vivo')

# ------------------------------------------------------------------ etapa 3: lanzar juegos
def rom(prg16, chr8, mapper, byte6=0, trainer=False, semilla=1, cola=None):
    """ROM iNES de prueba: datos reconocibles y, en el vector de reset ($C000 del último banco), un programa que
    deja una marca en $0700 (A5, el primer byte de la PRG y S) y se queda en un bucle."""
    prg = bytearray((i * 13 + semilla) & 0xFF for i in range(prg16 * 16384))
    cod = bytes([0xA9, 0xA5, 0x8D, 0x00, 0x07, 0xAD, 0x00, 0x80, 0x8D, 0x01, 0x07, 0xBA, 0x8E, 0x02, 0x07, 0x4C, 0x0F, 0xC0])
    prg[-0x4000:-0x4000 + len(cod)] = cod
    prg[-6:] = bytes([0x0F, 0xC0, 0x00, 0xC0, 0x0F, 0xC0])
    chr_ = bytes((i * 3 + semilla) & 0xFF for i in range(chr8 * 8192))
    cab = bytes([0x4E, 0x45, 0x53, 0x1A, prg16, chr8, (mapper & 15) << 4 | byte6 | (4 if trainer else 0), mapper & 0xF0]) + bytes(8)
    if cola is not None:                  # bytes 7-15 tal cual (NES 2.0, basura de cabeceras antiguas)
        cab = cab[:7] + bytes(cola)
    return cab + (bytes(range(256)) * 2 if trainer else b'') + bytes(prg) + chr_, bytes(prg), chr_

maprout = bytearray([0xFF]) * 512
for mp, r in ((0, 100), (4, 100), (1, 101), (219, 105)):
    maprout[mp] = r
(t / 'edfc/MAPROUT.BIN').write_bytes(maprout)
rbf100 = bytes((i * 7 + 1) & 0xFF for i in range(51200))
rbf105 = bytes((i * 5 + 3) & 0xFF for i in range(76288 - 300))        # tamaño que no es múltiplo de 512
ROMS = [('JUEGO.NES', rom(2, 1, 0, byte6=1)), ('CHRRAM.NES', rom(1, 0, 0, semilla=2)),
        ('MMC3.NES', rom(8, 8, 4, byte6=2, semilla=3)), ('TRAINER.NES', rom(2, 1, 0, trainer=True, semilla=4)),
        ('M219.NES', rom(4, 2, 219, semilla=5)), ('NOTAS.TXT', (b'no soy una ROM' * 40, b'', b'')),
        ('SINRBF.NES', rom(2, 1, 65, semilla=6)), ('FALTA.NES', rom(2, 1, 1, semilla=7)),
        # la cabecera de «219 Toy Story (Asia) (En) (Pirate).nes»: NES 2.0 con región y mando en los bytes 12 y 15
        ('NES20.NES', rom(4, 2, 219, semilla=8, cola=[0xD8, 0, 0, 0, 0, 2, 0, 0, 1])),
        # «DiskDude!» en los bytes 7-15: solo vale el nibble bajo (mapper 4)
        ('DUDE.NES', rom(8, 8, 0x44, semilla=9, cola=b'DiskDude!'))]

def imagen3(nombre, fragmentar=False, fragmentar_roms=(), fat=32):
    img = t / nombre
    subprocess.run(['sh', str(RAIZ / 'tools/bios/hacer_sd.sh'), str(img), str(fat), 'si', str(t / 'edfc')], check=True,
                   stdout=subprocess.DEVNULL)
    dest = f'{img}@@{8192 * 512}'
    subprocess.run(['mmd', '-i', dest, '::PRUEBAS'], check=True)
    for n, datos in (('EDFC/MAPS/100.RBF', rbf100), ('EDFC/MAPS/105.RBF', rbf105)) + tuple((n, r[0]) for n, r in ROMS):
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), f'::{n}'], check=True)
    if fragmentar:
        subprocess.run([sys.executable, '-I', str(RAIZ / 'tools/bios/fragmentar.py'), str(img), '8192',
                        'EDFC/MAPS/100.RBF'], check=True, stdout=subprocess.DEVNULL)
    if fragmentar_roms:
        subprocess.run([sys.executable, '-I', str(RAIZ / 'tools/bios/fragmentar.py'), str(img), '8192',
                        *fragmentar_roms], check=True, stdout=subprocess.DEVNULL)
    return img


def menu3(img, nombre):
    """Arranca, baja el cursor hasta `nombre` (2 carpetas delante) y devuelve la máquina."""
    m, ok = arrancar(img)
    m.correr(PASOS, nmi_cada=9000)
    m.pc_en_config.clear()
    m.n_cfg = len(m.fpga_cfgs)
    for _ in range(2 + [n for n, _ in ROMS].index(nombre)):
        toca(m, 0x04)
    return m

def lanzar(m, boton=0x80):
    m.pad = boton
    r = m.correr(6_000_000, lambda m: m.mapper != 0xFF, nmi_cada=9000)
    m.pad = 0
    return r == 'parada'

img3 = imagen3('e3.img')
for nombre, prg16, chr8, mapper, r132, r133, r134, rbf in (
        ('JUEGO.NES', 2, 1, 0, 1, 0, 1, rbf100), ('CHRRAM.NES', 1, 0, 0, 0, 0xFF, 0, rbf100),
        ('MMC3.NES', 8, 8, 4, 7, 7, 2, rbf100), ('TRAINER.NES', 2, 1, 0, 1, 0, 0, rbf100),
        ('M219.NES', 4, 2, 219, 3, 1, 0x10, rbf105), ('NES20.NES', 4, 2, 219, 3, 1, 0x10, rbf105),
        ('DUDE.NES', 8, 8, 4, 7, 7, 0, rbf100)):
    _, prg, chr_ = dict(ROMS)[nombre]
    m = menu3(img3, nombre)
    comprobar(('▶' + nombre.split('.')[0]) in m.pantalla(), f'{nombre}: el cursor llega a la entrada')
    ok = lanzar(m)
    comprobar(ok and m.mapper == mapper and m.cpu.pc < 0x0800,
              f'{nombre}: reg 131 = {mapper} (el de la cabecera), escrito desde la RAM')
    cfg = m.fpga_cfgs[m.n_cfg:]
    comprobar(len(cfg) == 1 and bytes(cfg[0][:len(rbf)]) == rbf and len(cfg[0]) >= len(rbf) + 256,
              f'{nombre}: el FPGA recibe el RBF entero y relojes de sobra ({len(cfg[0]) if cfg else 0} bytes)')
    comprobar(not m.pc_en_config, f'{nombre}: nada se ejecuta en $8000-$FFFF mientras se configura el FPGA')
    r9 = [(e[2], e[3]) for e in m.log[m.n_log:] if e[0] == 'CPLD' and e[1] == 9]
    comprobar((1, 0) in r9 and r9[-1] == (0, 1) and m.cpld[9] == 1, f'{nombre}: reg 9 a 0 durante la carga y de vuelta a 1')
    comprobar(bytes(m.prgrom[:len(prg)]) == prg, f'{nombre}: la PRG ({len(prg) // 1024} KiB) queda igual en la SRAM')
    comprobar(bytes(m.chr[:len(chr_)]) == chr_, f'{nombre}: la CHR ({len(chr_) // 1024} KiB) queda igual en la SRAM')
    comprobar((m.fpga.get(132), m.fpga.get(133), m.fpga.get(134), m.fpga.get(136)) == (r132, r133, r134, 0),
              f'{nombre}: regs 132/133/134/136 = {r132:02X}/{r133:02X}/{r134:02X}/00')
    pila = nombre == 'MMC3.NES'           # byte 6 = 2: con pila, crea EDFC/SAVE/MMC3.SRM
    comprobar(estado(m, 'en_juego') == 1 and (pila or solo_lectura(m)) and not [e for e in m.log[m.n_log:] if e[0] == 'ESCRITURA_EN_FLASH'],
              f'{nombre}: marca en_juego puesta; {"crea su partida" if pila else "la SD solo se lee"}; nada escrito en la flash')
    if mapper == 0:
        m.correr(3000)
        comprobar(bytes(m.ram[0x700:0x703]) == bytes([0xA5, prg[0], 0xFD]), f'{nombre}: el juego corre (marca en la RAM, S = $FD)')
        m.reset_consola()
        m.correr(PASOS, nmi_cada=9000)
        pan = m.pantalla()
        comprobar('Arranque: vuelta de juego' in pan and contadores(m) == (2, 0, 1) and ('▶' + nombre.split('.')[0]) in pan,
                  f'{nombre}: tras el reset, «vuelta de juego» 2/0/1 y el cursor sobre el juego')

for nombre, mensaje in (('NOTAS.TXT', 'No es una ROM iNES'), ('SINRBF.NES', 'Mapper sin RBF: 41'), ('FALTA.NES', 'No encuentro el RBF 101')):
    m = menu3(img3, nombre)
    ok = lanzar(m)
    m.correr(200_000, nmi_cada=9000)
    comprobar(not ok and mensaje in m.pantalla() and m.ppu_mask & 0x08 and not m.fpga_cfgs[m.n_cfg:],
              f'{nombre}: no se lanza, «{mensaje}», el FPGA no se toca y el menú sigue')
    toca(m, 0x08)
    comprobar('▶' in m.pantalla() and estado(m, 'en_juego') == 0, f'{nombre}: el cursor se sigue moviendo')
m, ok = arrancar(img3)
m.correr(PASOS, nmi_cada=9000)
lanzo = lanzar(m)
m.correr(1_000_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(not lanzo and cabecera(pan) == 'EDFC 1/1' and lista(pan) == ['MAPS/', 'SAVE/', 'OS.BIN', 'MAPROUT.BIN']
          and cursor_en(pan, 'MAPS/') and m.ppu_mask & 0x08, f'A sobre EDFC: entra en la carpeta ({lista(pan)})')
pulsa(m, 0x40, 1_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Raíz 1/1' and cursor_en(pan, 'EDFC/'), 'B: vuelve a la raíz con el cursor sobre EDFC')
pulsa(m, 0x40, 1_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Raíz 1/1' and cursor_en(pan, 'EDFC/') and solo_lectura(m), 'B en la raíz: no hace nada')
m = menu3(img3, 'JUEGO.NES')
comprobar(not lanzar(m, 0x80 | 0x20), 'Select+A (reset del kit Lava) no lanza el juego')
m = menu3(img3, 'JUEGO.NES')
comprobar(lanzar(m, 0x10) and m.mapper == 0, 'Start también lanza')
m = menu3(imagen3('e3frag.img', fragmentar=True), 'JUEGO.NES')
ok = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not ok and 'RBF fragmentado en la SD' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:],
          'RBF fragmentado: aviso y el FPGA no se toca')

# ROMs fragmentadas en la tarjeta: la copia va por tramos de clústeres seguidos (varias lecturas múltiples)
img3f = imagen3('e3romfrag.img', fragmentar_roms=('JUEGO.NES', 'MMC3.NES', 'TRAINER.NES'))
for nombre in ('JUEGO.NES', 'MMC3.NES', 'TRAINER.NES'):
    _, prg, chr_ = dict(ROMS)[nombre]
    m = menu3(img3f, nombre)
    n18 = sum(1 for e in m.log[m.n_log:] if e[0] == 'SD_CMD18')
    c0 = m.cpu.ciclos
    ok = lanzar(m)
    n18 = sum(1 for e in m.log[m.n_log:] if e[0] == 'SD_CMD18') - n18
    comprobar(ok and bytes(m.prgrom[:len(prg)]) == prg and bytes(m.chr[:len(chr_)]) == chr_ and n18 >= 4,
              f'{nombre} fragmentada: PRG y CHR iguales, {n18} lecturas múltiples (RBF + 3 tramos de la ROM)')

# ------------------------------------------------------------------ etapa 4: carpetas y nombres largos
def imagen4(nombre):
    img = imagen3(nombre)
    dest = f'{img}@@{8192 * 512}'
    def copia(datos, destino):
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), destino], check=True)
    subprocess.run(['mmd', '-i', dest, '::Juegos', '::Juegos/Mapper 4 (MMC3)', '::Juegos/Vacía'], check=True)
    for i in range(40):
        copia(bytes(100), f'::Juegos/Juego de prueba número {i:02d}.nes')
    copia(bytes(50), '::Juegos/borrado con nombre largo.nes')
    subprocess.run(['mdel', '-i', dest, '::Juegos/borrado con nombre largo.nes'], check=True)
    copia(dict(ROMS)['MMC3.NES'][0], '::Juegos/Mapper 4 (MMC3)/Súper Prueba ñ (España).nes')
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/._Súper Prueba ñ (España).nes')
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/OCULTO.NES')
    subprocess.run(['mattrib', '-i', dest, '+h', '::Juegos/Mapper 4 (MMC3)/OCULTO.NES'], check=True)
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/Un nombre larguísimo que no cabe en la pantalla.nes')
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/zelda.nes')
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/Ölçü àèìòù ÇÄÖ.nes')
    return img

img4 = imagen4('e4.img')
m, ok = arrancar(img4)
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(lista(pan)[-1] == 'Juegos/', 'la carpeta «Juegos» (nombre largo con minúsculas) al final de la raíz')
for _ in range(2 + len(ROMS)):            # EDFC, PRUEBAS y las ROMs: Juegos va detrás
    toca(m, 0x04)
comprobar(cursor_en(m.pantalla(), 'Juegos/'), 'el cursor llega a Juegos/')
pulsa(m, 0x80, 2_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Juegos 1/3' and cursor_en(pan, 'Mapper 4 (MMC3)/')
          and lista(pan) == ['Mapper 4 (MMC3)/', 'Vacía/'] + [f'Juego de prueba número {i:02d}' for i in range(14)],
          'dentro de Juegos: cabecera «Juegos 1/3», carpetas, acentos, 16 por página; el borrado no sale')
toca(m, 0x08)
m.correr(150_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Juegos 3/3' and cursor_en(pan, 'Juego de prueba número 39')
          and lista(pan) == [f'Juego de prueba número {i:02d}' for i in range(30, 40)],
          'arriba desde la primera fila: última página, cursor en la última entrada')
toca(m, 0x04)
m.correr(150_000, nmi_cada=9000)
comprobar(cabecera(m.pantalla()) == 'Juegos 1/3' and cursor_en(m.pantalla(), 'Mapper 4 (MMC3)/'),
          'abajo desde la última: vuelve a la primera página')
pulsa(m, 0x01)
comprobar(cabecera(m.pantalla()) == 'Juegos 2/3' and cursor_en(m.pantalla(), 'Juego de prueba número 14'), 'derecha: página 2')
pulsa(m, 0x02)
toca(m, 0x04)
pulsa(m, 0x80, 1_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Vacía' and lista(pan) == ['(carpeta vacía)'] and sin_cursor(pan), 'carpeta vacía: aviso y sin cursor')
pulsa(m, 0x40, 2_000_000)
comprobar(cursor_en(m.pantalla(), 'Vacía/') and cabecera(m.pantalla()) == 'Juegos 1/3', 'B: vuelve a Juegos con el cursor sobre Vacía/')
toca(m, 0x08)
pulsa(m, 0x80, 1_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Mapper 4 (MMC3) 1/1' and cursor_en(pan, 'Súper Prueba ñ (España)'), 'nombre largo con ú y ñ')
comprobar(lista(pan) == ['Súper Prueba ñ (España)', 'Un nombre larguísimo que no…', 'zelda', 'Olcü aeiou CAO'],
          f'sin «._» de macOS ni ocultos; cortado con «…»; «zelda» (8.3 en minúsculas); otros acentos sin acento: {lista(pan)}')
comprobar(solo_lectura(m), 'navegar por carpetas: solo lectura')
m.n_cfg = len(m.fpga_cfgs)
_, prg, chr_ = dict(ROMS)['MMC3.NES']
ok = lanzar(m)
comprobar(ok and m.mapper == 4 and bytes(m.prgrom[:len(prg)]) == prg and bytes(m.chr[:len(chr_)]) == chr_,
          'lanza un juego de una subcarpeta (2 niveles): MMC3, PRG y CHR iguales')
m.reset_consola()
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Arranque: vuelta de juego' in pan and cabecera(pan) == 'Mapper 4 (MMC3) 1/1' and cursor_en(pan, 'Súper Prueba ñ (España)'),
          'tras el reset: vuelve a la subcarpeta con el cursor sobre el juego')
pulsa(m, 0x40, 2_000_000)
comprobar(cursor_en(m.pantalla(), 'Mapper 4 (MMC3)/') and cabecera(m.pantalla()) == 'Juegos 1/3', 'B: a Juegos, cursor sobre la subcarpeta')
pulsa(m, 0x40, 1_000_000)
comprobar(cursor_en(m.pantalla(), 'Juegos/') and cabecera(m.pantalla()) == 'Raíz 1/1', 'B: a la raíz, cursor sobre Juegos')
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
comprobar('Arranque: reset' in m.pantalla() and 'Raíz' in m.pantalla(), 'reset en el menú: sigue en la carpeta (raíz)')
comprobar(fsck(m) == [] and leer_archivo(m, 'EDFC/SAVE/Súper Prueba ñ (España).srm') == bytes([0xFF]) * 8192,
          'la partida del juego de la subcarpeta: «Súper Prueba ñ (España).srm», y la FAT sin errores')


# ------------------------------------------------------------------ etapa 5: partidas con pila
PILA = [('Juego con pila (USA).nes', rom(2, 1, 0, byte6=2, semilla=11)),
        ('Otro juego (Japan).nes', rom(2, 1, 0, byte6=2, semilla=12)),
        # NES 2.0 con 32 KiB de PRG-NVRAM (byte 10 = $90: 64 << 9)
        ('Grande NES 2.0.nes', rom(2, 1, 0, byte6=2, semilla=13, cola=[0x08, 0, 0, 0x90, 0, 0, 0, 0, 0]))]
OTRA = bytes((i * 7 + 5) & 0xFF for i in range(8192))          # partida que ya estaba (copiada de un emulador)
FF8 = bytes([0xFF]) * 8192

def imagen5(nombre, fat=32, relleno=0, ocupar=False, sin_save=False):
    img = imagen3(nombre, fat=fat)
    dest = f'{img}@@{8192 * 512}'
    def copia(datos, destino):
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), destino], check=True)
    for n, r in PILA:
        copia(r[0], f'::{n}')
    if sin_save:
        subprocess.run(['mrd', '-i', dest, '::EDFC/SAVE'], check=True)
    else:
        copia(OTRA, '::EDFC/SAVE/OTRO JUEGO (Japan).SRM')           # mayúsculas distintas: tiene que valer
    for i in range(relleno):
        copia(b'x', f'::EDFC/SAVE/R{i:02d}.BIN')
    if ocupar:                                                      # casi llena: menos de 8 KiB libres
        out = subprocess.run(['mdir', '-i', dest, '::'], capture_output=True, text=True).stdout
        libres = int(out.strip().split('\n')[-1].split('bytes')[0].replace(' ', ''))
        f = t / 'grande.bin'
        with open(f, 'wb') as g:
            g.truncate(libres - 2048)
        subprocess.run(['mcopy', '-i', dest, str(f), '::RELLENO.BIN'], check=True)
    return img

def encender(img_bytes, prgram=None, sdhc=True, sd=None):
    m = Maquina(bios, sd or SD(img_bytes, sdhc=sdhc), prgram=prgram)
    ok = m.arrancar_bios() == 'parada' and m.cpu.pc == 0x8000
    m.n_log = len(m.log)
    m.correr(PASOS, nmi_cada=9000)
    m.n_cfg = len(m.fpga_cfgs)
    return m, ok

def ir_a(m, nombre):
    """Desde el arranque (cursor en EDFC), baja hasta la ROM `nombre` de PILA."""
    for _ in range(2 + len(ROMS) + [n for n, _ in PILA].index(nombre)):
        toca(m, 0x04)

def suma_marca(r):
    """La suma de partida.s: $A5 + bytes 17..0 con ADC (el acarreo se arrastra)."""
    a, c = 0xA5, 0
    for x in reversed(r[0x10000:0x10012]):
        v = a + x + c
        a, c = v & 0xFF, v >> 8
    return a

def marca(m):
    return bytes(m.prgram[0x10000:0x10004]) == b'N8SV'

def escrituras(m):
    return [e for e in m.log[m.n_log:] if e[0] == 'SD_CMD24']

def volver(m):
    m.correr(3000)
    m.reset_consola()
    m.correr(PASOS, nmi_cada=9000)
    return m.pantalla()

JP = 'Juego con pila (USA)'
img5 = imagen5('e5.img')
m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a(m, JP + '.nes')
comprobar(cursor_en(m.pantalla(), JP), 'partidas: el cursor llega al juego con pila')
m.prgram[:0x2000] = bytes(0x2000)
ok = lanzar(m)
comprobar(ok and m.mapper == 0 and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == FF8 and bytes(m.prgram[:0x2000]) == FF8,
          'juego con pila sin partida: crea «EDFC/SAVE/Juego con pila (USA).srm» (8 KiB a $FF) y la PRG-RAM queda a $FF')
comprobar(marca(m) and fsck(m) == [], 'marca de partida pendiente en el banco 8; fsck.fat sin errores')
comprobar(nombres_save(m) == sorted([f'{JP}.srm', 'OTRO JUEGO (Japan).SRM']), f'EDFC/SAVE: {nombres_save(m)}')
comprobar(not [e for e in m.log if e[0] == 'ESCRITURA_EN_FLASH'], 'nada escrito en la flash')
PAT = bytes((i * 11 + 3) & 0xFF for i in range(8192))
m.prgram[:0x2000] = PAT                    # lo que guarda el juego
pan = volver(m)
comprobar('Arranque: vuelta de juego' in pan and 'Partida guardada' in pan and cursor_en(pan, JP),
          'RESET en el juego: «Partida guardada», con el cursor sobre el juego')
comprobar(leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT and not marca(m) and fsck(m) == [],
          'el .srm tiene lo que dejó el juego, la marca se borra y la FAT sigue bien')
n_esc = len(escrituras(m))
m.prgram[:0x2000] = bytes(0x2000)
m.n_cfg = len(m.fpga_cfgs)
ok = lanzar(m)
comprobar(ok and bytes(m.prgram[:0x2000]) == PAT and len(escrituras(m)) == n_esc and len(nombres_save(m)) == 2,
          'al lanzarlo otra vez carga la partida guardada, sin escribir nada ni crear otra')
PAT2 = bytes((i * 5 + 9) & 0xFF for i in range(8192))
m.prgram[:0x2000] = PAT2
ram = bytearray(m.prgram)
ram[0x12000:] = bytes(len(ram) - 0x12000)  # al encender, la BIOS vuelve a cargar el OS
m2, ok = encender(bytes(m.sd.img), prgram=ram)
pan = m2.pantalla()
comprobar(ok and 'Arranque: frío (BIOS)' in pan and 'Partida guardada' in pan and leer_archivo(m2, f'EDFC/SAVE/{JP}.srm') == PAT2
          and not marca(m2) and fsck(m2) == [], 'apagado dentro del juego (RAM con pila): al encender se guarda la partida')
m3, ok = encender(bytes(m.sd.img))           # RAM sin pila: llega a cero, no hay marca
comprobar(ok and 'Partida' not in m3.pantalla() and solo_lectura(m3), 'encendido con la RAM a cero: no escribe nada')
mal = bytearray(ram)
mal[0x10012] ^= 1                            # marca con la suma mal
comprobar(suma_marca(ram) == ram[0x10012], 'la suma de la marca se calcula como en partida.s')
m3, ok = encender(bytes(m.sd.img), prgram=mal)
comprobar(ok and 'Partida' not in m3.pantalla() and solo_lectura(m3), 'marca con la suma de comprobación mal: no escribe nada')
mal = bytearray(ram)
mal[0x1000A] ^= 0x40                         # marca que apunta a otro clúster (con su suma bien)
mal[0x10012] = suma_marca(mal)
m3, ok = encender(bytes(m.sd.img), prgram=mal)
comprobar(ok and 'Partida no encontrada' in m3.pantalla() and solo_lectura(m3) and not marca(m3),
          'marca que no coincide con el archivo: «Partida no encontrada», no escribe y la borra')

m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a(m, 'Otro juego (Japan).nes')
ok = lanzar(m)
comprobar(ok and bytes(m.prgram[:0x2000]) == OTRA and len(nombres_save(m)) == 1 and not escrituras(m),
          'partida que ya estaba («OTRO JUEGO (Japan).SRM», otras mayúsculas): se carga, sin crear nada')
m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a(m, 'Grande NES 2.0.nes')
ok = lanzar(m)
comprobar(ok and leer_archivo(m, 'EDFC/SAVE/Grande NES 2.0.srm') == bytes([0xFF]) * 32768 and bytes(m.prgram[:0x8000]) == bytes([0xFF]) * 32768,
          'NES 2.0 con 32 KiB de PRG-NVRAM: partida de 32 KiB (4 bancos de la PRG-RAM)')
PAT32 = bytes((i * 3 + (i >> 9)) & 0xFF for i in range(32768))
m.prgram[:0x8000] = PAT32
pan = volver(m)
comprobar('Partida guardada' in pan and leer_archivo(m, 'EDFC/SAVE/Grande NES 2.0.srm') == PAT32 and fsck(m) == [],
          'los 32 KiB se guardan al volver')
m, ok = encender(pathlib.Path(img5).read_bytes())
for _ in range(2 + [n for n, _ in ROMS].index('MMC3.NES')):
    toca(m, 0x04)
ok = lanzar(m)
comprobar(ok and 'MMC3.SRM' in nombres_save(m) and leer_archivo(m, 'EDFC/SAVE/MMC3.SRM') == FF8 and fsck(m) == [],
          'ROM con nombre 8.3 (MMC3.NES): su partida es MMC3.SRM, sin nombre largo')

# carpeta SAVE casi llena (clúster de 512 bytes = 16 entradas): la partida nueva empieza en el clúster y sigue en otro
m, ok = encender(pathlib.Path(imagen5('e5dir.img', relleno=9)).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
comprobar(ok and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == FF8 and fsck(m) == [] and len(nombres_save(m)) == 11,
          'EDFC/SAVE sin sitio: se le añade un clúster y el nombre largo queda partido entre los dos; fsck.fat bien')
m.prgram[:0x2000] = PAT
pan = volver(m)
comprobar('Partida guardada' in pan and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT, 'y se guarda bien al volver')

# sin la carpeta EDFC/SAVE (la SD de la v0.4.0-beta no la trae): se crea
m, ok = encender(pathlib.Path(imagen5('e5sinsave.img', sin_save=True)).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
comprobar(ok and nombres_save(m) == [f'{JP}.srm'] and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == FF8 and fsck(m) == [],
          'sin EDFC/SAVE: crea la carpeta («.» y «..») y la partida; fsck.fat sin errores')

# FAT16 y SDSC
m, ok = encender(pathlib.Path(imagen5('e5f16.img', fat=16)).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
m.prgram[:0x2000] = PAT
pan = volver(m)
comprobar(ok and 'FAT16' in pan and 'Partida guardada' in pan and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT and fsck(m) == [],
          'FAT16: crea, guarda al volver y fsck.fat sin errores')
m, ok = encender(pathlib.Path(img5).read_bytes(), sdhc=False)
ir_a(m, JP + '.nes')
ok = lanzar(m)
m.prgram[:0x2000] = PAT
pan = volver(m)
comprobar(ok and 'SDSC' in pan and 'Partida guardada' in pan and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT and fsck(m) == [],
          'SDSC (direcciones en bytes): crea y guarda')

# tarjeta llena
m, ok = encender(pathlib.Path(imagen5('e5llena.img', fat=16, ocupar=True)).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not ok and 'SD llena: no cabe la partida' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:] and fsck(m) == [],
          'SD sin sitio: «SD llena», no lanza y la FAT queda bien')

# tarjeta que no deja escribir (protegida): la marca se queda y no se lanza nada hasta guardar
class SDprotegida(SD):
    def byte(self, v, cs):
        if cs and self.modo == 'escribir' and self.wbuf is not None and len(self.wbuf) == 514:
            self.wbuf = None
            self.modo = None
            self.salida.extend([0x0D, 0xFF])           # bloque rechazado (error de escritura)
            return 0xFF
        return super().byte(v, cs)
m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
m.prgram[:0x2000] = PAT
m.sd.__class__ = SDprotegida
pan = volver(m)
comprobar('Partida no guardada: 0B' in pan and marca(m), 'tarjeta que no deja escribir: «Partida no guardada: 0B» y la marca se queda')
toca(m, 0x08)                                # arriba: a NOTAS.TXT... el cursor está en el juego; subir y bajar
toca(m, 0x04)
m.n_cfg = len(m.fpga_cfgs)
lanzo = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not lanzo and 'Sin guardar la anterior: 0B' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:] and bytes(m.prgram[:0x2000]) == PAT,
          'con la partida sin guardar no se lanza nada (ni se toca la PRG-RAM)')
m.sd.__class__ = SD
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
comprobar('Partida guardada' in m.pantalla() and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT and not marca(m),
          'cuando la tarjeta vuelve a dejar escribir, el reset guarda la partida')
m, ok = encender(pathlib.Path(img5).read_bytes(), sd=SDprotegida(pathlib.Path(img5).read_bytes()))
ir_a(m, JP + '.nes')
lanzo = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not lanzo and 'Error al escribir la SD 0B' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:],
          'no se puede crear la partida: «Error al escribir la SD 0B» y no lanza')

print('pantalla del caso FAT32:')
m, ok = arrancar(img32)
m.correr(PASOS, nmi_cada=9000)
print(m.pantalla())
sys.exit(1 if fallos else 0)
