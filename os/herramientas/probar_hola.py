#!/usr/bin/env python3
"""probar_hola.py --bios BIOS.bin --rbf 255.RBF --trabajo DIR — Prueba el OS de la etapa 1 con la BIOS real en el
modelo de tools/bios: pantalla, mando, reset en caliente y que no toque nada que no debe."""
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
img = t / 'sd.img'
os.environ.setdefault('MTOOLS_SKIP_CHECK', '1')
subprocess.run(['sh', str(RAIZ / 'tools/bios/hacer_sd.sh'), str(img), '32', 'si', str(t / 'edfc')], check=True,
               stdout=subprocess.DEVNULL)

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
def estado(nombre):                      # variable de la zona de estado, en la PRG-RAM
    return m.prgram[0x18000 | (etiquetas[nombre] & 0x7FFF)]
def contadores():
    return estado('arranques'), estado('resets'), estado('vueltas')

m = Maquina(pathlib.Path(a.bios).read_bytes(), SD(img.read_bytes()))
comprobar(m.arrancar_bios() == 'parada' and m.cpu.pc == 0x8000, 'la BIOS salta a $8000')
n_log = len(m.log)
prg_antes = dict(m.escrituras_prgram)
partidas = bytes(m.prgram[:0x12000])
r = m.correr(300_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(r == 'limite', 'el OS sigue corriendo (sin opcodes ilegales)')
comprobar('OS PROPIO N8 - ARRANQUE' in pan, 'título en pantalla')
comprobar('ARRANQUE: FRIO (BIOS)' in pan and contadores() == (1, 0, 0), 'encendido: FRIO, contadores 1/0/0')
comprobar('01 FF 00 FB' in pan, 'registros de la CPU al entrar (A X Y S de la BIOS)')
comprobar(m.ppu_mask & 0x08 and m.ppu_ctrl & 0x80, 'fondo visible y NMI activa')
glifo = bytes(m.chr[0x7F000 + 0x41 * 16:0x7F000 + 0x41 * 16 + 8])
comprobar(glifo[0] == 0x70 and glifo[3] == 0xF8, 'la «A» de la fuente está en la CHR (banco 127, tile $41)')
m.pad = 0x80 | 0x08          # A y arriba (orden de lectura: A B Select Start Arriba Abajo Izq Der)
m.correr(60_000, nmi_cada=9000)
comprobar('MANDO: A - - - U - - -' in m.pantalla(), 'el mando se ve en vivo (A y arriba)')
m.pad = 0x20 | 0x80          # Select+A, la combinación del Lava
m.correr(60_000, nmi_cada=9000)
comprobar('MANDO: A - S - - - - -' in m.pantalla(), 'Select+A se lee bien')
m.pad = 0

# reset en el OS (botón RESET o kit Lava): el CPLD mantiene el reg 9 y la CPU usa el vector de la RAM
m.cpu.reset()
comprobar(m.cpu.pc == 0x8000, 'el vector RESET instalado en la RAM apunta a $8000')
m.correr(300_000, nmi_cada=9000)
comprobar('ARRANQUE: RESET' in m.pantalla() and contadores() == (2, 1, 0), 'reset en el OS: RESET, contadores 2/1/0')

# ráfaga del Lava: varios resets seguidos, alguno antes de que el OS termine de arrancar
for pasos in (500, 3000, 20_000, 60_000):
    m.correr(pasos, nmi_cada=9000)
    m.cpu.reset()
m.correr(300_000, nmi_cada=9000)
comprobar('ARRANQUE: RESET' in m.pantalla() and contadores() == (6, 5, 0),
          f'ráfaga de 4 resets (kit Lava): contadores {contadores()}, esperado (6, 5, 0)')

# vuelta de un juego: marca del lanzador, y la consola como la deja un juego
m.prgram[0x18000 | (etiquetas['en_juego'] & 0x7FFF)] = 1
m.cpld[9] = 0x15                          # el lanzador del v13 puede dejar los bits 2-4
for i in range(0x800):
    m.ram[i] = 0xA5
m.ppu_ctrl, m.ppu_mask = 0x90, 0x1E
m.cpu.reset()
m.correr(300_000, nmi_cada=9000)
comprobar('ARRANQUE: VUELTA DE JUEGO' in m.pantalla() and contadores() == (7, 5, 1),
          f'vuelta de un juego: VUELTA DE JUEGO, contadores {contadores()}')
comprobar(estado('en_juego') == 0, 'la marca en_juego queda borrada')
comprobar(m.cpld[9] == 1, f'el reg 9 vuelve a 01 (era $15; ahora ${m.cpld[9]:02X})')
m.cpu.reset()
m.correr(300_000, nmi_cada=9000)
comprobar('ARRANQUE: RESET' in m.pantalla() and contadores() == (8, 6, 1), 'el reset siguiente vuelve a ser RESET')

cpld = [e for e in m.log[n_log:] if e[0] == 'CPLD']
comprobar(cpld and all(e[1] == 9 and e[3] == 1 for e in cpld), 'del CPLD solo escribe reg 9 = 01')
otros = [e for e in m.log[n_log:] if e[0] in ('4402', 'ESCRITURA_EN_FLASH', 'USB_TX') or
         (e[0] == 'FPGA' and e[1] != 130) or e[0].startswith('SD_')]
comprobar(not otros, f'no toca la flash, la SD, $4402 ni otros registros del FPGA ({otros[:3]})')
comprobar(dict(m.escrituras_prgram) == prg_antes and bytes(m.prgram[:0x12000]) == partidas,
          'no toca la PRG-RAM fuera de su imagen (partidas y estado del v13 intactos)')
print('pantalla final:\n' + m.pantalla())
sys.exit(1 if fallos else 0)
