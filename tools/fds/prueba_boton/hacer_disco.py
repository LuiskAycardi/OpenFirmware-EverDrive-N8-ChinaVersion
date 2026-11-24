#!/usr/bin/env python3
"""hacer_disco.py — disco de prueba del cambio de cara a mano (GPL-3.0-or-later, código propio).

  make -C tools/fds/prueba_boton        (ensambla boton.s: programa.bin y vectores.bin)
  python3 -I tools/fds/prueba_boton/hacer_disco.py --kyodaku-de DISCO.fds [--salida BOTON.fds]

Dos caras con el mismo ID («BTN», cara 0 las dos): el cambio de cara automático no sabe elegir y solo cambia con
B + Select. Cada cara lleva el archivo de licencia que la BIOS comprueba al arrancar (KYODAKU-), el programa en $6000
y los vectores en $DFF6. El archivo de licencia no es nuestro: se copia de un disco del usuario al hacer la imagen,
que no entra en el repositorio (*.fds está en .gitignore).
"""
import argparse
import pathlib
import sys

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI.parent))
import fds  # noqa: E402


def archivo(n, ident, nombre, dire, datos, tipo):
    cab = bytes([3, n, ident]) + nombre.ljust(8)[:8] + bytes([dire & 0xFF, dire >> 8, len(datos) & 0xFF,
                                                                 len(datos) >> 8, tipo])
    return cab + bytes([4]) + bytes(datos)


def cara(kyodaku, programa, vectores):
    b1 = bytes([1]) + fds.FIRMA + bytes([0x00]) + b'BTN' + b' ' + bytes([0, 0, 0, 0, 0, 2]) + bytes([0xFF] * 5)
    b1 += bytes(56 - len(b1))
    c = b1 + bytes([2, 3])
    c += archivo(0, 0, kyodaku['cab'][3:11], kyodaku['dir'], kyodaku['datos'], kyodaku['tipo'])
    c += archivo(1, 1, b'BOTON', 0x6000, programa, 0)
    c += archivo(2, 2, b'VECTORES', 0xDFF6, vectores, 0)
    return c + bytes(fds.CARA - len(c))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kyodaku-de', required=True, help='un .fds del usuario del que copiar el archivo KYODAKU-')
    ap.add_argument('--salida', default=str(AQUI / 'BOTON.fds'))
    a = ap.parse_args()
    cs, _ = fds.caras(open(a.kyodaku_de, 'rb').read())
    ky = next((x for x in fds.leer_cara(cs[0])['archivos'] if x['nombre'].startswith('KYODAKU')), None)
    if ky is None:
        sys.exit('ese disco no tiene archivo KYODAKU- en la cara A')
    programa = (AQUI / 'programa.bin').read_bytes()
    vectores = (AQUI / 'vectores.bin').read_bytes()
    c = cara(ky, programa, vectores)
    pathlib.Path(a.salida).write_bytes(c + c)
    print(f'{a.salida}: 2 caras con el mismo ID, programa de {len(programa)} bytes')


if __name__ == '__main__':
    main()
