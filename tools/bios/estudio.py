#!/usr/bin/env python3
"""estudio.py — Ejecuta la BIOS del N8 clon en el modelo (maquina.py) y comprueba lo documentado en
docs/bios-n8-clon.md.

  python3 -I tools/bios/estudio.py arranque --bios BIOS.bin --img sd.img [--sdsc] [--seguir N]
  python3 -I tools/bios/estudio.py pruebas  --bios BIOS.bin --os OS.BIN --rbf 255.RBF --trabajo DIR

- BIOS.bin: volcado de 16 KiB de la ventana $C000-$FFFF de la flash (no está en el repositorio, es de Krikzz).
- `arranque` resume lo que hace la BIOS con una imagen de SD: órdenes de la SD, registros del CPLD y del FPGA,
  dónde deja el OS.BIN, qué recibe el FPGA y el estado al saltar a $8000. Con --seguir N ejecuta N instrucciones
  más del OS (con NMI) y enseña la pantalla.
- `pruebas` crea imágenes (FAT16/FAT32, con y sin MBR, SDHC/SDSC, tamaños de OS.BIN, archivos fragmentados y
  que faltan) en DIR y comprueba cada resultado. Necesita mtools, mkfs.fat y sfdisk.
"""
import argparse
import collections
import pathlib
import shutil
import subprocess
import sys

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
from maquina import Maquina, SD   # noqa: E402


def maquina(bios, img, sdhc=True):
    return Maquina(pathlib.Path(bios).read_bytes(), SD(pathlib.Path(img).read_bytes(), sdhc=sdhc))


def donde_esta(m, datos):
    i = bytes(m.prgram).find(datos[:64])
    return i


def arranque(a):
    m = maquina(a.bios, a.img, not a.sdsc)
    r = m.arrancar_bios()
    c = m.cpu
    print(f'resultado: {r}  PC=${c.pc:04X}  A={c.a:02X} X={c.x:02X} Y={c.y:02X} S={c.s:02X} P={c.p():02X}')
    print('órdenes de la SD:', dict(collections.Counter(e[0][3:] for e in m.log if e[0].startswith('SD_'))))
    print('registros (sin los cambios de /CS y de ráfaga del reg 2):')
    for e in m.log:
        if e[0] == 'CPLD' and e[1] == 2 and (e[2] ^ e[3]) in (2, 4):
            continue
        if e[0] in ('CPLD', 'FPGA', '4402'):
            print('  ', e[0], *[f'{x}' if i < len(e) - 1 else f'(PC ${x:04X})' for i, x in enumerate(e[1:])])
    print('bancos de PRG-RAM escritos:', sorted(m.escrituras_prgram.items()))
    print('configuraciones del FPGA (bytes):', [len(x) for x in m.fpga_cfgs])
    print(f'CPLD final: {dict(m.cpld)}  $4402={m.m4402}  FPGA: {m.fpga}  PPU $2000={m.ppu_ctrl:02X} $2001={m.ppu_mask:02X}')
    print('página $FC00 de la PRG-RAM = página $FC00 de la BIOS:', m.prgram[0x1FC00:] == m.bios[0x3C00:])
    if m.pantalla():
        print('pantalla:\n' + m.pantalla())
    if a.seguir and r == 'parada':
        r2 = m.correr(a.seguir, None, nmi_cada=9000)
        print(f'tras {a.seguir} instrucciones del OS: {r2}, PC=${m.cpu.pc:04X}')
        print('pantalla:\n' + m.pantalla())


# ------------------------------------------------------------------------------------------------ pruebas
def sh(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)


def imagen(trabajo, nombre, fat, mbr, carpeta):
    img = trabajo / nombre
    sh('sh', str(AQUI / 'hacer_sd.sh'), str(img), str(fat), 'si' if mbr else 'no', str(carpeta))
    return img


def pruebas(a):
    trabajo = pathlib.Path(a.trabajo)
    if trabajo.exists() and any(trabajo.iterdir()):
        sys.exit(f'{trabajo} no está vacío')
    trabajo.mkdir(parents=True, exist_ok=True)
    osb = pathlib.Path(a.os).read_bytes()
    rbf = pathlib.Path(a.rbf).read_bytes()
    base = trabajo / 'base'
    base.mkdir()
    shutil.copy(a.os, base / 'OS.BIN')
    shutil.copy(a.rbf, base / '255.RBF')
    fallos = 0

    def caso(nombre, img, sdhc=True, os_esperado=osb, inicio=None, ok_rbf=True, error=None):
        nonlocal fallos
        m = maquina(a.bios, img, sdhc)
        r = m.arrancar_bios()
        notas = []
        bien = True
        if error:
            m.correr(200000)
            bien = r != 'parada' and f'ERROR:{error}' in m.pantalla()
            notas.append('pantalla: ' + ' / '.join(x[3:].strip() for x in m.pantalla().splitlines()[1:3]))
        else:
            fin = 0x1FC00
            n = len(os_esperado)
            ini = inicio if inicio is not None else 0x20000 - (n // 0x2000) * 0x2000
            esperado = os_esperado[:fin - ini]
            igual = bytes(m.prgram[ini:fin]) == esperado[:fin - ini]
            rbf_ok = bytes(m.fpga_cfgs[0][:len(rbf)]) == rbf if m.fpga_cfgs else False
            bien = r == 'parada' and igual and (rbf_ok == ok_rbf)
            notas.append(f'OS.BIN en 0x{ini:05X}: {"igual" if igual else "DISTINTO"}; '
                         f'255.RBF {"igual" if rbf_ok else "distinto"} ({len(m.fpga_cfgs[0]) if m.fpga_cfgs else 0} B enviados)')
        fallos += not bien
        print(f'{"ok   " if bien else "FALLO"} {nombre:34s} {"; ".join(notas)}')

    caso('FAT32 con MBR, SDHC', imagen(trabajo, 'f32.img', 32, True, base))
    caso('FAT32 con MBR, SDSC', trabajo / 'f32.img', sdhc=False)
    caso('FAT32 sin MBR', imagen(trabajo, 'f32nombr.img', 32, False, base))
    caso('FAT16 con MBR, SDHC', imagen(trabajo, 'f16.img', 16, True, base))
    caso('FAT16 con MBR, SDSC', trabajo / 'f16.img', sdhc=False)
    for tam in (16384, 20000, 65536):
        d = trabajo / f'os{tam}'
        d.mkdir()
        datos = bytes((i * 7 + 3) & 0xFF for i in range(tam))
        (d / 'OS.BIN').write_bytes(datos)
        shutil.copy(a.rbf, d / '255.RBF')
        n = (tam // 0x2000) * 0x2000                        # la BIOS trunca a múltiplos de 8 KiB
        caso(f'OS.BIN de {tam} bytes', imagen(trabajo, f'os{tam}.img', 32, True, d),
             os_esperado=datos[:n], inicio=0x20000 - n)
    img = imagen(trabajo, 'frag.img', 32, True, base)
    sh(sys.executable, '-I', str(AQUI / 'fragmentar.py'), str(img), '8192', 'EDFC/OS.BIN', 'EDFC/MAPS/255.RBF')
    m = maquina(a.bios, img)
    m.arrancar_bios()
    igual = bytes(m.prgram[0x12000:0x1FC00]) == osb[:0xDC00]
    print(f'{"ok   " if not igual else "FALLO"} {"OS.BIN y 255.RBF fragmentados":34s} '
          f'se cargan {"bien (no esperado)" if igual else "mal: la BIOS lee de forma contigua"}')
    fallos += igual
    for nombre, borrar, cod in (('sin OS.BIN', '::EDFC/OS.BIN', '12'), ('sin 255.RBF', '::EDFC/MAPS/255.RBF', '13')):
        img = trabajo / (nombre.replace(' ', '_') + '.img')
        shutil.copy(trabajo / 'f32.img', img)
        sh('mdel', '-i', f'{img}@@{8192 * 512}', borrar)
        caso(nombre, img, error=cod)
    print('fallos:', fallos)
    return fallos


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    s = p.add_subparsers(dest='orden', required=True)
    q = s.add_parser('arranque')
    q.add_argument('--bios', required=True)
    q.add_argument('--img', required=True)
    q.add_argument('--sdsc', action='store_true')
    q.add_argument('--seguir', type=int, default=0)
    q = s.add_parser('pruebas')
    q.add_argument('--bios', required=True)
    q.add_argument('--os', required=True)
    q.add_argument('--rbf', required=True)
    q.add_argument('--trabajo', required=True)
    a = p.parse_args()
    import os
    os.environ.setdefault('MTOOLS_SKIP_CHECK', '1')
    if a.orden == 'arranque':
        arranque(a)
    else:
        sys.exit(1 if pruebas(a) else 0)


if __name__ == '__main__':
    main()
