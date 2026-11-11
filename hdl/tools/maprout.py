#!/usr/bin/env python3
"""Ver / editar MAPROUT.BIN del EverDrive N8.

  maprout.py show RUTA/MAPROUT.BIN
  maprout.py set  RUTA/MAPROUT.BIN MAPPER RBF [--savestate]

`set` guarda antes una copia MAPROUT.BIN.bak-AAAAMMDD-HHMMSS junto al original.
RBF = número del archivo .RBF (p. ej. 100 -> MAPS/100.RBF), o 255 para "no soportado".
"""
import shutil
import sys
import time


def load(path):
    data = bytearray(open(path, "rb").read())
    if len(data) != 512:
        sys.exit(f"{path}: tamaño {len(data)}, se esperaban 512 bytes")
    return data


def show(path):
    data = load(path)
    for name, off in (("normal", 0), ("save state", 256)):
        entries = [f"{m}->{data[off + m]:03d}" for m in range(256) if data[off + m] != 0xFF]
        print(f"[{name}] {len(entries)} mappers")
        print("  " + " ".join(entries))


def set_entry(path, mapper, rbf, savestate):
    if not (0 <= mapper <= 254) or not (0 <= rbf <= 255):
        sys.exit("mapper 0..254, rbf 0..255")
    data = load(path)
    off = (256 if savestate else 0) + mapper
    backup = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, backup)
    old = data[off]
    data[off] = rbf
    open(path, "wb").write(data)
    print(f"copia: {backup}")
    print(f"offset 0x{off:03X}: {old:03d} -> {rbf:03d}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "show":
        show(a[1])
    elif len(a) in (4, 5) and a[0] == "set":
        set_entry(a[1], int(a[2], 0), int(a[3], 0), "--savestate" in a)
    else:
        sys.exit(__doc__)
