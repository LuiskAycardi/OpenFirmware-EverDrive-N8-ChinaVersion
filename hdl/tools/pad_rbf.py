#!/usr/bin/env python3
"""Rellena un .RBF con 0xFF hasta un múltiplo de 512 bytes (formato que espera el OS del N8)."""
import sys

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
pad = (-len(data)) % 512
open(dst, "wb").write(data + b"\xff" * pad)
print(f"{dst}: {len(data)} bytes + {pad} de relleno = {len(data) + pad}")
if len(data) > 100_000:
    print("AVISO: el RBF parece sin comprimir (los oficiales miden 50-75 KB). "
          "Revisar la compresión del bitstream en Quartus.")
