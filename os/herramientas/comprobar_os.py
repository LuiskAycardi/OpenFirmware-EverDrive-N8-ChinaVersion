#!/usr/bin/env python3
"""comprobar_os.py OS.BIN — Comprueba los requisitos de la BIOS (docs/bios-n8-clon.md §3)."""
import sys

d = open(sys.argv[1], 'rb').read()
errores = []
if len(d) % 0x2000 or not 0x2000 <= len(d) <= 0x10000:
    errores.append(f'tamaño {len(d)}: tiene que ser múltiplo de 8 KiB, entre 8 y 64 KiB')
inicio = 0x10000 - len(d)                 # dirección de CPU del primer byte (el archivo acaba en $FFFF)
if inicio > 0x8000:
    errores.append('el archivo no cubre $8000: la BIOS salta ahí')
else:
    if d[0x8000 - inicio] == 0xEA:
        errores.append('el primer byte de $8000 es $EA: el 255.RBF de fábrica activaría su cargador')
if any(d[0xFC00 - inicio:0xFFFA - inicio]):
    errores.append('hay datos en $FC00-$FFF9: la BIOS los pisa')
if errores:
    sys.exit('OS.BIN no válido:\n  ' + '\n  '.join(errores))
print(f'{sys.argv[1]}: {len(d)} bytes, requisitos de la BIOS cumplidos')
