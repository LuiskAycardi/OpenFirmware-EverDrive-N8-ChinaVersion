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

m = Maquina(pathlib.Path(a.bios).read_bytes(), SD(img.read_bytes()))
comprobar(m.arrancar_bios() == 'parada' and m.cpu.pc == 0x8000, 'la BIOS salta a $8000')
n_log = len(m.log)
prg_antes = dict(m.escrituras_prgram)
partidas = bytes(m.prgram[:0x12000])
r = m.correr(300_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(r == 'limite', 'el OS sigue corriendo (sin opcodes ilegales)')
comprobar('OS PROPIO N8 - HOLA MUNDO' in pan, 'título en pantalla')
comprobar('ARRANQUES: 01' in pan, 'primer arranque: ARRANQUES 01')
comprobar('01 FF 00 FB' in pan, 'registros de la CPU al entrar (A X Y S de la BIOS)')
comprobar(m.ppu_mask & 0x08, 'fondo visible')
glifo = bytes(m.chr[0x7F000 + 0x41 * 16:0x7F000 + 0x41 * 16 + 8])
comprobar(glifo[0] == 0x70 and glifo[3] == 0xF8, 'la «A» de la fuente está en la CHR (banco 127, tile $41)')
m.pad = 0x80 | 0x08          # A y arriba (orden de lectura: A B Select Start Arriba Abajo Izq Der)
m.correr(60_000, nmi_cada=9000)
comprobar('MANDO: A - - - U - - -' in m.pantalla(), 'el mando se ve en vivo (A y arriba)')
m.pad = 0
m.correr(30_000, nmi_cada=9000)
for modo in (1, 2, 3):           # A sola cambia la forma de leer el mando
    m.pad = 0x80; m.correr(30_000, nmi_cada=9000); m.pad = 0; m.correr(30_000, nmi_cada=9000)
    comprobar(f'MODO MANDO: 0{modo}' in m.pantalla(), f'A cambia al modo de lectura {modo}')
m.pad = 0x40 | 0x20              # B+Select con el modo 3 (lectura en la NMI)
m.correr(60_000, nmi_cada=9000)
comprobar('MANDO: - B S - - - - -' in m.pantalla(), 'el modo 3 (lectura en la NMI) ve B+Select')
m.pad = 0
# reset de la consola: el CPLD mantiene el reg 9 (supuesto a medir) y la CPU lee el vector de la RAM
m.cpu.reset()
comprobar(m.cpu.pc == 0x8000, 'el vector RESET instalado en la RAM apunta a $8000')
m.correr(300_000, nmi_cada=9000)
comprobar('ARRANQUES: 02' in m.pantalla(), 'tras un reset sin BIOS: ARRANQUES 02')
comprobar('MODO MANDO: 03' in m.pantalla(), 'el modo de lectura sobrevive al reset')
otros = [e for e in m.log[n_log:] if e[0] in ('CPLD', '4402', 'ESCRITURA_EN_FLASH', 'USB_TX') or
         (e[0] == 'FPGA' and e[1] != 130) or e[0].startswith('SD_')]
comprobar(not otros, f'no escribe registros del CPLD, la flash, la SD ni otros del FPGA ({otros[:3]})')
comprobar(dict(m.escrituras_prgram) == prg_antes and bytes(m.prgram[:0x12000]) == partidas,
          'no toca la PRG-RAM fuera de su imagen (partidas y estado del v13 intactos)')
print('pantalla final:\n' + m.pantalla())
sys.exit(1 if fallos else 0)
