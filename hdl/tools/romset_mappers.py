#!/usr/bin/env python3
"""Cuenta los juegos de un romset (.nes con cabecera) por mapper y los cruza con los mappers que enruta
hdl/rtl/n8_top.v. Separa lo que no puede funcionar en el N8 aunque tengamos el mapper:
mapper > 255, PRG o CHR de más de 512 KB.

  python3 -I hdl/tools/romset_mappers.py CARPETA [--json salida.json]
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/n8sim"))
import simtop  # noqa: E402

LIM = 512 * 1024


def header(p):
    h = p.open("rb").read(16)
    if len(h) < 16 or h[:4] != b"NES\x1a":
        return None
    nes2 = (h[7] & 0x0C) == 0x08
    mapper = (h[6] >> 4) | (h[7] & 0xF0)
    sub = 0
    prg, chr_ = h[4], h[5]
    if nes2:
        mapper |= (h[8] & 0x0F) << 8
        sub = h[8] >> 4
        prg |= (h[9] & 0x0F) << 8
        chr_ |= (h[9] & 0xF0) << 4
    return mapper, sub, prg * 16384, chr_ * 8192, nes2


def kind(name):
    if re.search(r"\((?:[^)]*\b)?(?:Unl|Pirate|Aftermarket|Homebrew)\b", name):
        return "unl"
    if re.search(r"\b(?:Beta|Proto|Demo|Sample)\b", name):
        return "proto"
    return "lic"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("carpeta")
    ap.add_argument("--json")
    a = ap.parse_args()
    ours = set(simtop.mapper_table((ROOT / "hdl/rtl/n8_top.v").read_text())) | {0}
    per = collections.defaultdict(lambda: {"lic": [], "unl": [], "proto": [], "big": []})
    bad = 0
    for p in sorted(Path(a.carpeta).iterdir()):
        if not p.is_file():
            continue
        h = header(p)
        if h is None:
            bad += 1
            continue
        m, sub, prg, chr_, _ = h
        e = per[m]
        if prg > LIM or chr_ > LIM:
            e["big"].append(p.stem)
        else:
            e[kind(p.stem)].append(p.stem)
    total = sum(len(v) for e in per.values() for v in e.values())
    rows = []
    for m, e in per.items():
        n = len(e["lic"]) + len(e["unl"]) + len(e["proto"])
        rows.append((m, m in ours, len(e["lic"]), len(e["unl"]), len(e["proto"]), len(e["big"]), n))
    have = [r for r in rows if r[1]]
    miss = [r for r in rows if not r[1]]
    fit = lambda rs: sum(r[6] for r in rs)  # noqa: E731
    print(f"{total} ROMs leídas ({bad} sin cabecera iNES), {len(rows)} mappers distintos")
    print(f"Cubiertos: {len(have)} mappers, {fit(have)} ROMs que caben en el N8 "
          f"(+{sum(r[5] for r in have)} demasiado grandes)")
    print(f"Faltan:    {len(miss)} mappers, {fit(miss)} ROMs que cabrían "
          f"(+{sum(r[5] for r in miss)} demasiado grandes)")
    print("\nFaltan (mapper <= 255, ordenados por ROMs que cabrían):  mapper  lic  unl  proto  >512K")
    for r in sorted((r for r in miss if r[0] <= 255), key=lambda r: (-r[6], r[0])):
        if r[6] or r[5]:
            ej = (per[r[0]]["lic"] + per[r[0]]["unl"] + per[r[0]]["proto"] + per[r[0]]["big"])[0]
            print(f"  {r[0]:4d}  {r[2]:4d} {r[3]:4d} {r[4]:5d} {r[5]:6d}   p. ej. {ej[:60]}")
    hi = [r for r in miss if r[0] > 255]
    print(f"\nMappers > 255 (no direccionables con MAPROUT de 8 bits): {len(hi)} mappers, "
          f"{sum(r[6] + r[5] for r in hi)} ROMs")
    if a.json:
        Path(a.json).write_text(json.dumps({str(m): e for m, e in per.items()}, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
