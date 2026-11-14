#!/usr/bin/env python3
"""Genera MAPROUT.BIN (tabla mapper -> RBF del OS del EverDrive N8) a partir de hdl/rtl/n8_top.v.

El archivo tiene 512 bytes: tabla normal (bytes 0-255) y tabla de save state (256-511); cada byte es
el número del RBF de MAPS/ que atiende ese mapper, o $FF si no está soportado. Aquí:
  - cada mapper del selector de n8_top.v va al RBF en cuyo bloque `ifdef N8_RBF_nnn` aparece
    (el mapper 0 lo tienen todos; va al 100);
  - 254 (FDS) queda apuntando a 254.RBF, el del propio cartucho, si se pide con --fds;
  - la tabla de save state queda vacía: nuestros RBF no implementan save states.

  python3 -I hdl/tools/gen_maprout.py SALIDA/MAPROUT.BIN [--fds] [--lista]
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def routing(text):
    """{mapper: rbf} según los bloques `ifdef N8_RBF_nnn del case (mapper_id) del selector `g`."""
    body = text.split("case (mapper_id)", 1)[1].split("endcase", 1)[0]
    rbf, pending, out = None, [], {}
    for line in body.splitlines():
        m = re.search(r"`ifdef N8_RBF_(\d+)", line)
        if m:
            rbf = int(m.group(1))
        code = line.split("//", 1)[0]
        pending += [int(n) for n in re.findall(r"8'd(\d+)", code)]
        if re.search(r"\bg\s*=\s*bus_\w+", code):
            for n in pending:
                out[n] = rbf
            pending = []
    out.setdefault(0, 100)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("salida")
    ap.add_argument("--fds", action="store_true", help="mapper 254 (FDS) -> 254.RBF del cartucho")
    ap.add_argument("--lista", action="store_true", help="escribir también la lista de mappers por RBF")
    ap.add_argument("--base", metavar="MAPROUT", help="partir de este MAPROUT (el de fábrica): los mappers que no "
                    "implementamos siguen en sus RBF, y su tabla de save state se conserva")
    ap.add_argument("--maps", metavar="DIR", help="con --base: carpeta MAPS de la SD; los mappers de la base cuyo "
                    "RBF no esté ahí pasan a $FF (no soportado)")
    a = ap.parse_args()
    r = routing((ROOT / "hdl/rtl/n8_top.v").read_text())
    if any(v is None for v in r.values()):
        sys.exit("mapper fuera de un bloque N8_RBF_nnn: " + str(sorted(k for k, v in r.items() if v is None)))
    data = bytearray([0xFF] * 512)
    de_base = {}
    if a.base:
        base = pathlib.Path(a.base).read_bytes()
        if len(base) not in (256, 512):
            sys.exit(f"{a.base}: {len(base)} bytes; un MAPROUT mide 256 o 512")
        data[:len(base)] = base
        if a.maps:                                   # rutas de la base a RBF que no existen -> no soportado
            for i in range(512):
                if data[i] != 0xFF and not (pathlib.Path(a.maps) / f"{data[i]:03d}.RBF").exists():
                    data[i] = 0xFF
    for m, v in r.items():
        data[m] = v
        data[256 + m] = 0xFF                         # nuestros RBF no tienen save states
    if a.base:
        de_base = {m: data[m] for m in range(256) if data[m] != 0xFF and m not in r}
    if a.fds:
        data[254] = 254
    out = pathlib.Path(a.salida)
    out.write_bytes(bytes(data))
    por_rbf = {}
    for m, v in sorted(r.items()):
        por_rbf.setdefault(v, []).append(m)
    print(f"{out}: {len(r)} mappers en {len(por_rbf)} RBF" + (" + FDS (254)" if a.fds else "")
          + (f" + {len(de_base)} de la base ({a.base})" if a.base else ""))
    if a.lista:
        for v in sorted(por_rbf):
            print(f"  {v:03d}.RBF ({len(por_rbf[v])}): " + ", ".join(map(str, por_rbf[v])))
        if de_base:
            print("  de la base: " + ", ".join(f"{m}->{v:03d}" for m, v in sorted(de_base.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
