#!/usr/bin/env python3
"""hacer.py — ROMs y disco de calibración del volumen del sonido de expansión (GPL-3.0-or-later, código propio).

  python3 -I tools/calibracion/hacer.py [--kyodaku-de DISCO.fds] [--salida DIR]

Ensambla cal.s una vez por chip (necesita cc65) y deja en DIR (por defecto tools/calibracion/out):
  CAL VRC6.nes (24), CAL 5B.nes (69), CAL N163.nes (19), CAL VRC7.nes (85), CAL MMC5.nes (5)
y, con --kyodaku-de, CAL FDS.fds: un disco de una cara con el archivo de licencia (KYODAKU-) copiado de un disco del
usuario, que no es nuestro y no entra en el repositorio (como tools/fds/prueba_boton).
"""
import argparse
import pathlib
import subprocess
import sys
import tempfile

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI.parent / 'fds'))
CHIPS = {'VRC6': 2, '5B': 3, 'N163': 4, 'VRC7': 5, 'MMC5': 6}


def ensamblar(chip, cfg, salida):
    with tempfile.TemporaryDirectory() as t:
        o = pathlib.Path(t) / 'cal.o'
        subprocess.run(['ca65', '-D', f'CHIP={chip}', '-o', str(o), str(AQUI / 'cal.s')], check=True)
        subprocess.run(['ld65', '-C', str(AQUI / cfg), '-o', str(salida), str(o)], check=True)


def disco(kyodaku_de, prg, vec):
    import fds  # noqa: E402  (tools/fds/fds.py)
    cs, _ = fds.caras(open(kyodaku_de, 'rb').read())
    ky = next((x for x in fds.leer_cara(cs[0])['archivos'] if x['nombre'].startswith('KYODAKU')), None)
    if ky is None:
        sys.exit('ese disco no tiene archivo KYODAKU- en la cara A')

    def archivo(n, ident, nombre, dire, datos, tipo):
        cab = bytes([3, n, ident]) + nombre.ljust(8)[:8] + bytes([dire & 0xFF, dire >> 8, len(datos) & 0xFF,
                                                                     len(datos) >> 8, tipo])
        return cab + bytes([4]) + bytes(datos)
    b1 = bytes([1]) + fds.FIRMA + bytes([0x00]) + b'CAL' + b' ' + bytes([0, 0, 0, 0, 0, 2]) + bytes([0xFF] * 5)
    b1 += bytes(56 - len(b1))
    c = b1 + bytes([2, 3])
    c += archivo(0, 0, ky['cab'][3:11], ky['dir'], ky['datos'], ky['tipo'])
    c += archivo(1, 1, b'CALIBRA', 0x6000, prg, 0)
    c += archivo(2, 2, b'VECTORES', 0xDFF6, vec, 0)
    return c + bytes(fds.CARA - len(c))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kyodaku-de', help='un .fds del usuario del que copiar el archivo KYODAKU-')
    ap.add_argument('--salida', default=str(AQUI / 'out'))
    a = ap.parse_args()
    out = pathlib.Path(a.salida)
    out.mkdir(parents=True, exist_ok=True)
    for nombre, n in CHIPS.items():
        ensamblar(n, 'cart.cfg', out / f'CAL {nombre}.nes')
        print(out / f'CAL {nombre}.nes')
    if a.kyodaku_de:
        base = out / 'cal_fds'
        ensamblar(1, 'fds.cfg', base)
        prg = (out / 'cal_fds.prg').read_bytes()
        vec = (out / 'cal_fds.vec').read_bytes()
        (out / 'CAL FDS.fds').write_bytes(disco(a.kyodaku_de, prg, vec))
        for f in ('cal_fds', 'cal_fds.prg', 'cal_fds.vec'):
            (out / f).unlink(missing_ok=True)
        print(out / 'CAL FDS.fds')


if __name__ == '__main__':
    main()
