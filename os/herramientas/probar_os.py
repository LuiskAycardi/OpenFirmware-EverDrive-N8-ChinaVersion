#!/usr/bin/env python3
"""probar_os.py --bios BIOS.bin --rbf 255.RBF --trabajo DIR — Prueba el OS (etapa 3) con la BIOS real en el modelo
de tools/bios: arranque y resets, mando, lectura de la SD (FAT16/FAT32, SDHC/SDSC, con y sin MBR, raíz con cadena
de clústeres, reset a mitad de lectura, tarjeta muda) y lanzamiento de juegos (carga del RBF, PRG, CHR, registros,
salto, vuelta al menú y errores). Comprueba que nunca escribe en la tarjeta ni en la flash."""
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

etiquetas = {}
for linea in (pathlib.Path(a.os).parent / 'os.lbl').read_text().split('\n'):
    if linea.startswith('al '):
        _, dire, nombre = linea.split()
        etiquetas[nombre.lstrip('.')] = int(dire, 16)

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

ARCHIVOS = [('IRQ65.NES', 24592), ('Super Mario Bros. (World).nes', 40976), ('ZELDA.NES', 131088), ('NOTAS.TXT', 300)]

# ------------------------------------------------------------------ FAT32 con MBR, SDHC: el caso de la SD real
img32 = imagen('f32.img', 32, True, ARCHIVOS)
m, ok = arrancar(img32)
comprobar(ok, 'la BIOS salta a $8000')
r = m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(r == 'limite', 'el OS sigue corriendo (sin opcodes ilegales)')
comprobar('OS propio N8 - etapa 3' in pan and 'Arranque: frío (BIOS)' in pan and contadores(m) == (1, 0, 0),
          'encendido: FRIO, contadores 1/0/0')
comprobar(m.ppu_mask & 0x08 and m.ppu_ctrl & 0x80, 'fondo visible y NMI activa')
comprobar('SD: SDHC FAT32 clúster 01' in pan and 'Part 00002000' in pan, 'tarjeta SDHC, FAT32, partición en 0x2000')
comprobar('En raíz: 06' in pan, '6 entradas en la raíz (2 carpetas y 4 archivos; nombres largos y etiqueta fuera)')
for linea in ('EDFC    .    <DIR>', 'PRUEBAS .    <DIR>', 'IRQ65   .NES 00006010', 'ZELDA   .NES 00020010',
              'NOTAS   .TXT 0000012C', '.NES 0000A010'):
    comprobar(linea in pan, f'en la lista: «{linea}»')
comprobar('32K en f: 00' in pan and 'fallo' not in pan, 'prueba de lectura de 32 KiB sin fallos')
comprobar(m.cpld[2] == 0x0B, f'reg 2 al terminar = $0B: rápido, tarjeta libre, SDHC (${m.cpld[2]:02X})')
comprobar(solo_lectura(m), 'solo órdenes de lectura; ninguna escritura en la tarjeta')
m.pad = 0x80 | 0x20
m.correr(60_000, nmi_cada=9000)
comprobar('Mando: A - S - - - - -' in m.pantalla(), 'el mando se ve en vivo (Select+A)')
m.pad = 0

# resets: en el OS, en ráfaga (alguno a mitad de la lectura de la SD) y vuelta de un juego
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
comprobar('Arranque: reset' in m.pantalla() and contadores(m) == (2, 1, 0) and 'En raíz: 06' in m.pantalla(),
          'reset en el OS: RESET 2/1/0 y la SD se vuelve a leer bien')
for pasos in (500, 3000, 20_000, 60_000, 150_000, 400_000):      # los últimos caen dentro de la lectura de la SD
    m.correr(pasos, nmi_cada=9000)
    m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Arranque: reset' in pan and contadores(m) == (8, 7, 0) and 'En raíz: 06' in pan and 'error' not in pan,
          f'ráfaga de 6 resets, algunos a mitad de lectura: contadores {contadores(m)} y la SD bien')
m.prgram[0x18000 | (etiquetas['en_juego'] & 0x7FFF)] = 1
m.cpld[9] = 0x15
m.cpld[2] = 0x0D                          # tarjeta seleccionada y en ráfaga, como si se hubiera cortado una lectura
for i in range(0x800):
    m.ram[i] = 0xA5
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Arranque: vuelta de juego' in pan and contadores(m) == (9, 7, 1) and 'En raíz: 06' in pan,
          'vuelta de un juego: VUELTA DE JUEGO 9/7/1 y la SD bien')
comprobar(estado(m, 'en_juego') == 0 and m.cpld[9] == 1, 'marca en_juego borrada y reg 9 = 01')
cpld = [e for e in m.log[m.n_log:] if e[0] == 'CPLD']
comprobar(all(e[1] in (2, 9) for e in cpld) and all(e[3] == 1 for e in cpld if e[1] == 9),
          'del CPLD solo escribe el reg 2 (SD) y reg 9 = 01')
otros = [e for e in m.log[m.n_log:] if e[0] in ('4402', 'ESCRITURA_EN_FLASH', 'USB_TX') or (e[0] == 'FPGA' and e[1] != 130)]
comprobar(not otros, f'no toca la flash, $4402 ni otros registros del FPGA ({otros[:3]})')
comprobar(dict(m.escrituras_prgram) == m.prg_antes and bytes(m.prgram[:0x12000]) == m.partidas,
          'no toca la PRG-RAM fuera de su imagen')
comprobar(solo_lectura(m) and bytes(m.sd.img) == pathlib.Path(img32).read_bytes(), 'la imagen de la SD queda idéntica')

# ------------------------------------------------------------------ otras tarjetas
m, ok = arrancar(img32, sdhc=False)
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('SD: SDSC FAT32' in pan and 'En raíz: 06' in pan and 'ZELDA   .NES 00020010' in pan and m.cpld[2] == 0x03,
          'SDSC (direcciones en bytes): misma lista; reg 2 = $03')

m, ok = arrancar(imagen('f16.img', 16, True, ARCHIVOS))
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('SD: SDHC FAT16 clúster' in pan and 'En raíz: 06' in pan and 'NOTAS   .TXT 0000012C' in pan, 'FAT16 con MBR')

m, ok = arrancar(imagen('f32nombr.img', 32, False, ARCHIVOS))
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('FAT32' in pan and 'Part 00000000' in pan and 'En raíz: 06' in pan, 'FAT32 sin MBR (sin particiones)')

muchos = [(f'J{i:03d}.NES', 16 + i) for i in range(60)]
for fat in (32, 16):
    m, ok = arrancar(imagen(f'muchos{fat}.img', fat, True, muchos))
    m.correr(PASOS + 1_500_000, nmi_cada=9000)
    pan = m.pantalla()
    comprobar('En raíz: 3E' in pan and 'J009    .NES 00000019' in pan and 'error' not in pan,
              f'FAT{fat}: raíz de 62 entradas (varios sectores{" y cadena de clústeres" if fat == 32 else ""}); se listan 12')
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
def rom(prg16, chr8, mapper, byte6=0, trainer=False, semilla=1):
    """ROM iNES de prueba: datos reconocibles y, en el vector de reset ($C000 del último banco), un programa que
    deja una marca en $0700 (A5, el primer byte de la PRG y S) y se queda en un bucle."""
    prg = bytearray((i * 13 + semilla) & 0xFF for i in range(prg16 * 16384))
    cod = bytes([0xA9, 0xA5, 0x8D, 0x00, 0x07, 0xAD, 0x00, 0x80, 0x8D, 0x01, 0x07, 0xBA, 0x8E, 0x02, 0x07, 0x4C, 0x0F, 0xC0])
    prg[-0x4000:-0x4000 + len(cod)] = cod
    prg[-6:] = bytes([0x0F, 0xC0, 0x00, 0xC0, 0x0F, 0xC0])
    chr_ = bytes((i * 3 + semilla) & 0xFF for i in range(chr8 * 8192))
    cab = bytes([0x4E, 0x45, 0x53, 0x1A, prg16, chr8, (mapper & 15) << 4 | byte6 | (4 if trainer else 0), mapper & 0xF0]) + bytes(8)
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
        ('SINRBF.NES', rom(2, 1, 65, semilla=6)), ('FALTA.NES', rom(2, 1, 1, semilla=7))]

def imagen3(nombre, fragmentar=False):
    img = t / nombre
    subprocess.run(['sh', str(RAIZ / 'tools/bios/hacer_sd.sh'), str(img), '32', 'si', str(t / 'edfc')], check=True,
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
    return img

def toca(m, mascara):
    m.pad = mascara; m.correr(30_000, nmi_cada=9000); m.pad = 0; m.correr(30_000, nmi_cada=9000)

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
        ('M219.NES', 4, 2, 219, 3, 1, 0x10, rbf105)):
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
    comprobar(estado(m, 'en_juego') == 1 and solo_lectura(m) and not [e for e in m.log[m.n_log:] if e[0] == 'ESCRITURA_EN_FLASH'],
              f'{nombre}: marca en_juego puesta; la SD solo se lee; nada escrito en la flash')
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
m.correr(200_000, nmi_cada=9000)
comprobar(not lanzo and 'Carpetas: en otra etapa' in m.pantalla(), 'A sobre una carpeta: aviso, sin lanzar')
m = menu3(img3, 'JUEGO.NES')
comprobar(not lanzar(m, 0x80 | 0x20), 'Select+A (reset del kit Lava) no lanza el juego')
m = menu3(img3, 'JUEGO.NES')
comprobar(lanzar(m, 0x10) and m.mapper == 0, 'Start también lanza')
m = menu3(imagen3('e3frag.img', fragmentar=True), 'JUEGO.NES')
ok = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not ok and 'RBF fragmentado en la SD' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:],
          'RBF fragmentado: aviso y el FPGA no se toca')

print('pantalla del caso FAT32:')
m, ok = arrancar(img32)
m.correr(PASOS, nmi_cada=9000)
print(m.pantalla())
sys.exit(1 if fallos else 0)
