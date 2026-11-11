#!/usr/bin/env python3
"""Compara el sonido de expansión de nuestro RBF con el de Mesen2 (banco N8).

Cada ejecución de difftest.py con N8_AUDIO=1 deja ref/audio.txt (Mesen2) y n8/audio.txt (nuestro modelo):
líneas "ciclo_de_CPU nivel" cada vez que el nivel cambia. Aquí se reconstruyen las dos señales
escalonadas y se comparan de dos maneras:
  1) exacta: ciclos en que difieren, tolerando desfases de hasta TOL ciclos alrededor de cada cambio
     (nuestras escrituras se aplican en la bajada de M2; las de Mesen2, al momento);
  2) por fotograma (29 781 ciclos): nivel medio y número de cambios. Es lo que se oye y no depende de la
     fase de los generadores, que en el 5B empiezan a contar al encender en Mesen2 y al salir del menú
     del OS en el N8 (en el chip real la fase también es arbitraria).

  python3 -I audiodiff.py reports/CARPETA [--tol 3]
"""
import argparse
import pathlib


def load(p):
    pts = []
    if p.exists():
        for line in p.read_text().splitlines():
            c, v = line.split()
            pts.append((int(c), int(v)))
    return pts


def compare(ref, n8, tol):
    if not ref and not n8:
        return None
    end = max(ref[-1][0] if ref else 0, n8[-1][0] if n8 else 0) + 1
    start = min(ref[0][0] if ref else end, n8[0][0] if n8 else end)
    cuts = sorted({c for c, _ in ref} | {c for c, _ in n8} | {end})
    changes = sorted({c for c, _ in ref} | {c for c, _ in n8})

    def level_at(pts, idx_holder, c):
        i = idx_holder[0]
        while i + 1 < len(pts) and pts[i + 1][0] <= c:
            i += 1
        idx_holder[0] = i
        return pts[i][1] if pts and pts[i][0] <= c else 0

    ia, ib = [0], [0]
    bad = 0
    bad_segs = 0
    first = None
    peak = 0
    for a, b in zip(cuts, cuts[1:]):
        if a < start:
            continue
        la, lb = level_at(ref, ia, a), level_at(n8, ib, a)
        if la != lb:
            ln = b - a
            # tramo corto justo después de un cambio: desfase de temporización, no error
            if ln <= tol:
                continue
            bad += ln
            bad_segs += 1
            peak = max(peak, abs(la - lb))
            if first is None:
                first = a
    total = end - start
    return {"ciclos": total, "distintos": bad, "tramos": bad_segs, "primero": first, "max_dif": peak,
            "cambios_ref": len(ref), "cambios_n8": len(n8)}


FRAME = 29781


def per_frame(pts, start, end):
    """[(nivel medio, cambios)] por fotograma."""
    out = []
    i = 0
    lvl = 0
    while i < len(pts) and pts[i][0] <= start:
        lvl = pts[i][1]
        i += 1
    for f0 in range(start, end - FRAME + 1, FRAME):
        f1 = f0 + FRAME
        acc = 0
        t = f0
        ch = 0
        while i < len(pts) and pts[i][0] < f1:
            acc += lvl * (pts[i][0] - t)
            t = pts[i][0]
            lvl = pts[i][1]
            ch += 1
            i += 1
        acc += lvl * (f1 - t)
        out.append((acc / FRAME, ch))
    return out


def compare_frames(ref, n8):
    if not ref or not n8:
        return None
    start = min(ref[0][0], n8[0][0])
    end = min(ref[-1][0], n8[-1][0])
    a, b = per_frame(ref, start, end), per_frame(n8, start, end)
    if not a:
        return None
    top = max(1, max(v for v, _ in a), max(v for v, _ in b))
    bad = 0
    for (ma, ca), (mb, cb) in zip(a, b):
        if abs(ma - mb) > 0.05 * top or abs(ca - cb) > max(4, 0.1 * max(ca, cb)):
            bad += 1
    return bad, len(a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("carpeta")
    ap.add_argument("--tol", type=int, default=3)
    a = ap.parse_args()
    root = pathlib.Path(a.carpeta)
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        r = compare(load(d / "ref" / "audio.txt"), load(d / "n8" / "audio.txt"), a.tol)
        if r is None:
            print(f"{d.name}: sin sonido de expansión en ninguna de las dos")
            continue
        pct = 100.0 * r["distintos"] / max(1, r["ciclos"])
        estado = "idéntico" if r["distintos"] == 0 else ("casi" if pct < 0.5 else "distinto")
        linea = (f"{d.name}: {estado}  {pct:.3f} % de {r['ciclos']} ciclos distintos en {r['tramos']} tramos"
                 f" (máx. {r['max_dif']}, primero en {r['primero']}); cambios ref {r['cambios_ref']}, n8 {r['cambios_n8']}")
        if r["distintos"]:
            fr = compare_frames(load(d / "ref" / "audio.txt"), load(d / "n8" / "audio.txt"))
            if fr:
                malos, tot = fr
                veredicto = "EQUIVALENTE" if malos <= tot * 0.01 else "DISTINTO"
                linea += f"\n    por fotograma: {veredicto} ({malos} de {tot} fotogramas con nivel medio o cambios distintos)"
        print(linea)


if __name__ == "__main__":
    main()
