#!/usr/bin/env python3
"""tas.py — películas TAS de NES (formato .fm2 de FCEUX) como entrada del banco de consola.

Una película .fm2 tiene una línea por fotograma desde el encendido: |orden|RLDUTSBA|RLDUTSBA||, donde cada
letra es un botón pulsado y '.' uno suelto (mando 1 y mando 2). Aquí se convierte en un byte por fotograma con
la máscara del Nano (bit 0 = A, 1 = B, 2 = Select, 3 = Start, 4 = Arriba, 5 = Abajo, 6 = Izquierda,
7 = Derecha), que es lo que reproduce Mesen2 (mesen_ref.lua, N8_INPUT_FILE) y lo que el Nano entrega en la
consola fotograma a fotograma.

  python3 -I tas.py info PELICULA.fm2 [ROM.nes]     # cabecera, fotogramas, comprobación de la ROM
  python3 -I tas.py convertir PELICULA.fm2 SALIDA.bin
"""
import argparse
import base64
import hashlib
import pathlib
import sys

ORDEN_FM2 = "RLDUTSBA"                      # de izquierda a derecha en la película
BIT = {"A": 0, "B": 1, "S": 2, "T": 3, "U": 4, "D": 5, "L": 6, "R": 7}


def leer_fm2(ruta):
    """(cabecera, [byte por fotograma del mando 1], [orden por fotograma])."""
    cab, mandos, ordenes = {}, [], []
    for linea in pathlib.Path(ruta).read_text(errors="replace").splitlines():
        if linea.startswith("|"):
            campos = linea.split("|")
            ordenes.append(int(campos[1] or 0))
            m = campos[2] if len(campos) > 2 else ""
            b = 0
            for i, c in enumerate(m[:8]):
                if c not in ". ":
                    b |= 1 << BIT[ORDEN_FM2[i]]
            mandos.append(b)
        elif " " in linea:
            k, v = linea.split(" ", 1)
            cab[k] = v.strip()
    return cab, mandos, ordenes


def md5_rom(ruta_rom):
    """Checksum de FCEUX: md5 de la ROM sin la cabecera iNES de 16 bytes, en base64."""
    datos = pathlib.Path(ruta_rom).read_bytes()
    return "base64:" + base64.b64encode(hashlib.md5(datos[16:]).digest()).decode()


LUA_FCEUX = pathlib.Path(__file__).resolve().parent / "tas_catalogo" / "lag_fceux.lua"


def lag_fceux(pelicula, rom, salida, shots=(), extra=0, timeout=1800):
    """Reproduce la película en FCEUX (su emulador de origen) y devuelve [lag del fotograma 0, 1, ...] (True = el juego
    no leyó el mando). Si se piden, deja capturas f%05d.png en 'salida' (FCEUX recorta 8 líneas arriba y abajo: 256x224)."""
    import os
    import subprocess
    salida = pathlib.Path(salida)
    salida.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, N8_LAG_OUT=str(salida / "lag.txt"), N8_SHOTS=",".join(str(x) for x in shots),
               N8_SHOT_DIR=str(salida), N8_EXTRA=str(extra))
    subprocess.run(["fceux", "--sound", "0", "--playmov", str(pelicula), "--loadlua", str(LUA_FCEUX), str(rom)],
                   env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
    lag = {}
    for linea in (salida / "lag.txt").read_text().split("\n"):
        if linea.strip():
            f, v = linea.split()
            lag[int(f)] = v == "1"
    return [lag.get(i, False) for i in range(max(lag) + 1)] if lag else []


def por_lecturas(mandos, lag):
    """Entrada por lectura del mando: los bytes de los fotogramas en que FCEUX vio leer el mando (sin los de lag)."""
    return bytes(b for i, b in enumerate(mandos) if not (i < len(lag) and lag[i]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("accion", choices=["info", "convertir"])
    ap.add_argument("pelicula")
    ap.add_argument("otro", nargs="?", help="info: ROM para comprobar; convertir: archivo de salida")
    a = ap.parse_args()
    cab, mandos, ordenes = leer_fm2(a.pelicula)
    if a.accion == "info":
        print(f"{a.pelicula}: {len(mandos)} fotogramas, ROM {cab.get('romFilename')} ({cab.get('romChecksum')})")
        print(f"  PAL={cab.get('palFlag')}  órdenes no nulas: {sum(1 for o in ordenes if o)} "
              f"(fotogramas {[i for i, o in enumerate(ordenes) if o][:5]})")
        print(f"  fotogramas con algún botón: {sum(1 for b in mandos if b)}; cambios de botones: "
              f"{sum(1 for x, y in zip(mandos, mandos[1:]) if x != y)}")
        if a.otro:
            ok = md5_rom(a.otro) == cab.get("romChecksum")
            print(f"  ROM {a.otro}: {'coincide' if ok else 'NO coincide'}")
            return 0 if ok else 1
    else:
        pathlib.Path(a.otro).write_bytes(bytes(mandos))
        print(f"{a.otro}: {len(mandos)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
