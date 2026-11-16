#!/usr/bin/env python3
"""probar_os.py --bios BIOS.bin --rbf 255.RBF --trabajo DIR — Prueba el OS (etapa 2) con la BIOS real en el modelo
de tools/bios: arranque y resets, mando, y lectura de la SD (FAT16/FAT32, SDHC/SDSC, con y sin MBR, raíz con cadena
de clústeres, reset a mitad de lectura, tarjeta muda). Comprueba que nunca escribe en la tarjeta."""
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
                                               'SD_CMD17', 'SD_CMD12'}
PASOS = 2_500_000

ARCHIVOS = [('IRQ65.NES', 24592), ('Super Mario Bros. (World).nes', 40976), ('ZELDA.NES', 131088), ('NOTAS.TXT', 300)]

# ------------------------------------------------------------------ FAT32 con MBR, SDHC: el caso de la SD real
img32 = imagen('f32.img', 32, True, ARCHIVOS)
m, ok = arrancar(img32)
comprobar(ok, 'la BIOS salta a $8000')
r = m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(r == 'limite', 'el OS sigue corriendo (sin opcodes ilegales)')
comprobar('OS propio N8 - etapa 2: SD' in pan and 'Arranque: frío (BIOS)' in pan and contadores(m) == (1, 0, 0),
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
    comprobar('En raíz: 3E' in pan and 'J010    .NES 0000001A' in pan and 'error' not in pan,
              f'FAT{fat}: raíz de 62 entradas (varios sectores{" y cadena de clústeres" if fat == 32 else ""}); se listan 13')
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

print('pantalla del caso FAT32:')
m, ok = arrancar(img32)
m.correr(PASOS, nmi_cada=9000)
print(m.pantalla())
sys.exit(1 if fallos else 0)
