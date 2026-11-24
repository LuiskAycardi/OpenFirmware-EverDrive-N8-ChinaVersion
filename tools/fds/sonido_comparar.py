#!/usr/bin/env python3
"""sonido_comparar.py — compara el sonido FDS de nuestro HDL con el de Mesen2 (GPL-3.0-or-later, código propio).

  N8_AUDIO=1 python3 -I tools/fds/comparar_mesen.py ... --salida DIR JUEGO.fds
  python3 -I tools/fds/sonido_comparar.py DIR/<juego> [--ciclos 15000000]

comparar_mesen.py deja ref/audio.txt (FDS de Mesen2) y n8/audio.txt (nuestro snd_fds.v): «ciclo nivel» en cada
cambio (nivel = 0-63 x 16). Nuestra carga del disco es más rápida que la del FDS de Mesen2, así que la música empieza
en otro ciclo: se alinea por el primer nivel distinto de cero y se compara a partir de ahí, (1) ciclo a ciclo,
tolerando desfases de unos pocos ciclos alrededor de cada cambio, y (2) por fotograma (29 781 ciclos): nivel medio.
Esto vale mientras el juego no lea el disco con la música sonando (entonces cada máquina llega a otro sitio).

  python3 -I tools/fds/sonido_comparar.py DIR/<juego> --contra replay.txt

compara ref/audio.txt con la salida de tools/fds/sonido_replay (snd_fds.v con las mismas escrituras que hizo Mesen2,
en los mismos ciclos): sin alinear nada, es la prueba del sintetizador.
"""
import argparse
import pathlib

FOT = 29781


def cargar(p):
    return [tuple(map(int, l.split())) for l in pathlib.Path(p).read_text().splitlines() if l.strip()]


def nivel_en(pts, c):
    lo, hi = 0, len(pts) - 1
    if not pts or pts[0][0] > c:
        return 0
    while lo < hi:
        m = (lo + hi + 1) // 2
        if pts[m][0] <= c:
            lo = m
        else:
            hi = m - 1
    return pts[lo][1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('carpeta')
    ap.add_argument('--ciclos', type=int, default=15_000_000, help='cuántos ciclos comparar desde el primer sonido')
    ap.add_argument('--tol', type=int, default=4)
    ap.add_argument('--contra', help='en vez de n8/audio.txt, este archivo y sin alinear (salida de sonido_replay)')
    a = ap.parse_args()
    d = pathlib.Path(a.carpeta)
    ref = cargar(d / 'ref' / 'audio.txt')
    n8 = cargar(a.contra) if a.contra else cargar(d / 'n8' / 'audio.txt')
    r0 = next((c for c, v in ref if v), None)
    n0 = next((c for c, v in n8 if v), None)
    if r0 is None or n0 is None:
        print(f'{d.name}: sin sonido (ref {r0}, n8 {n0})')
        return
    if not a.contra:
        n8 = [(c - n0 + r0, v) for c, v in n8]
    fin = min(r0 + a.ciclos, ref[-1][0], n8[-1][0])
    cortes = sorted({c for c, _ in ref if r0 <= c < fin} | {c for c, _ in n8 if r0 <= c < fin} | {fin})
    mal = 0
    tramos = 0
    pico = 0
    primero = None
    for x, y in zip(cortes, cortes[1:]):
        lr, ln = nivel_en(ref, x), nivel_en(n8, x)
        if lr != ln and y - x > a.tol:
            mal += y - x
            tramos += 1
            pico = max(pico, abs(lr - ln))
            if primero is None:
                primero = (x - r0, lr, ln)
    total = fin - r0
    fots = total // FOT
    medias_mal = 0
    for f in range(fots):
        s = r0 + f * FOT
        mr = sum(nivel_en(ref, s + k) for k in range(0, FOT, 64)) / (FOT / 64)
        mn = sum(nivel_en(n8, s + k) for k in range(0, FOT, 64)) / (FOT / 64)
        if abs(mr - mn) > 8:
            medias_mal += 1
    print(f'{d.name}: {total} ciclos ({fots} fotogramas) desde el primer sonido; cambios ref {len(ref)}, n8 {len(n8)}')
    print(f'  ciclo a ciclo: {100 * mal / max(1, total):.3f} % distinto en {tramos} tramos (pico {pico}); primero {primero}')
    print(f'  por fotograma: {medias_mal} de {fots} con el nivel medio distinto (> 8)')


if __name__ == '__main__':
    main()
