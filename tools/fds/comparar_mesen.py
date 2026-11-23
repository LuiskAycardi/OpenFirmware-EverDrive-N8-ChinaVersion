#!/usr/bin/env python3
"""comparar_mesen.py — Etapa F3 del FDS: cada .fds en el simulador del N8 (Mesen2 con nuestro HDL, tools/n8sim) frente
al FDS de Mesen2 (GPL-3.0-or-later, código propio).

  python3 -I tools/fds/comparar_mesen.py --bios BIOS.bin [--fotogramas 3000] [--salida DIR] JUEGO.fds [...]

  referencia  el .fds en el FDS de Mesen2, con la BIOS sin tocar (Firmware/disksys.rom) y «meter la cara que pide el
              juego» activado (FdsAutoInsertDisk), así las dos máquinas cambian de cara solas;
  n8          un contenedor iNES (mapper 254, 512 KiB de PRG) con la SRAM que deja el OS: caras, parche y BIOS
              parcheada (fds.imagen_ines), en Mesen2 con hdl/rtl como cartucho.

Nuestra carga es mucho más rápida que la del disco, así que los fotogramas no van a la par. La medida es cuántas de
las pantallas distintas del N8 (después del fotograma 300) aparecen también en la referencia, y si la última pantalla
del N8 sale en la referencia. Deja capturas de los dos en --salida. Necesita el Mesen2 parcheado de tools/n8sim
(tools/n8sim/run) y su libn8model.so. Ni la BIOS ni los juegos se copian al repositorio.
"""
import argparse
import concurrent.futures as cf
import json
import os
import queue
import traceback
import pathlib
import re
import shutil
import sys
import types

AQUI = pathlib.Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(RAIZ / 'tools' / 'n8sim'))
import fds  # noqa: E402
import difftest  # noqa: E402

INICIO = 300


def preparar(slot, bios):
    home = difftest.prepare_home(slot)
    (home / 'Firmware').mkdir(exist_ok=True)
    (home / 'Firmware' / 'disksys.rom').write_bytes(bios)
    s = json.loads((home / 'settings.json').read_text())
    s.setdefault('Nes', {}).update({'FdsAutoInsertDisk': True, 'FdsAutoLoadDisk': True, 'FdsFastForwardOnLoad': False})
    (home / 'settings.json').write_text(json.dumps(s))
    return home


def comparar(slot, ruta, bios, parche, a, salida):
    nombre = os.path.basename(ruta)
    clave = re.sub(r'[^A-Za-z0-9]+', '_', os.path.splitext(nombre)[0])[:60]
    d = salida / clave
    d.mkdir(parents=True, exist_ok=True)
    caras, _ = fds.caras(open(ruta, 'rb').read())
    img = d / 'n8.nes'
    img.write_bytes(fds.imagen_ines(bios, parche, caras))
    home = preparar(slot, bios)
    args = types.SimpleNamespace(script=a.guion, prgram_fill=None, model=a.modelo, clk=50.0)
    tiros = sorted({int(x) for x in a.capturas.split(',') if x.strip()} | {a.fotogramas})
    ref = difftest.run_one(home, str(ruta), 'ref', a.fotogramas, 7, tiros, d / 'ref', args)
    n8 = difftest.run_one(home, str(img), 'n8', a.fotogramas, 7, tiros, d / 'n8', args)
    img.unlink()                                     # lleva la BIOS: no se deja por ahí
    r = {'juego': nombre, 'clave': clave, 'fot_ref': len(ref['hashes']), 'fot_n8': len(n8['hashes'])}
    if len(ref['hashes']) < a.fotogramas or len(n8['hashes']) < a.fotogramas:
        r['estado'] = 'error_ref' if len(ref['hashes']) < a.fotogramas else 'error_n8'
        return r
    vistos = set(ref['hashes'])
    n8u = set(n8['hashes'][INICIO:])
    r['pantallas_n8'] = len(n8u)
    r['en_ref'] = len(n8u & vistos)
    r['ultima'] = n8['hashes'][-1] in vistos
    r['quieto_n8'] = len(set(n8['hashes'][INICIO:])) <= 2      # imagen fija (pantalla negra o colgado)
    frac = r['en_ref'] / max(1, r['pantallas_n8'])
    r['coincide'] = round(frac, 3)
    r['estado'] = 'bien' if (r['ultima'] or frac >= 0.1) and not r['quieto_n8'] else \
                  'quieto' if r['quieto_n8'] else 'distinto'
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bios', required=True)
    ap.add_argument('--parche', default=str(RAIZ / 'os' / 'build' / 'fds_parche.bin'))
    ap.add_argument('--modelo', default=str(RAIZ / 'tools' / 'n8sim' / 'libn8model.so'))
    ap.add_argument('--fotogramas', type=int, default=3000)
    ap.add_argument('--capturas', default='600,1200,2000')
    ap.add_argument('--guion', default='', help='botones, como en difftest: "120-126:start;300-306:a"')
    ap.add_argument('--salida', default=str(RAIZ / 'tools' / 'fds' / 'salida_mesen'))
    ap.add_argument('--hilos', type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument('--lista', help='archivo con una ruta de .fds por línea')
    ap.add_argument('fds', nargs='*')
    a = ap.parse_args()
    bios = open(a.bios, 'rb').read()
    crc, nom, estado, _ = fds.bios_info(bios)
    if estado != 'si':
        sys.exit(f'BIOS {nom or "?"} ({crc:08X}): no se puede parchear')
    parche = open(a.parche, 'rb').read()
    salida = pathlib.Path(a.salida).resolve()       # Mesen2 corre en su carpeta: las rutas, absolutas
    salida.mkdir(parents=True, exist_ok=True)
    res = []
    libres = queue.Queue()                           # una carpeta de Mesen2 por tarea a la vez
    for i in range(a.hilos):
        libres.put(i)

    def tarea(ruta):
        slot = libres.get()
        try:
            return comparar(slot, ruta, bios, parche, a, salida)
        except Exception as e:                        # un juego que falla no para la tanda
            return {'juego': os.path.basename(ruta), 'estado': 'error', 'error': f'{e}',
                    'traza': traceback.format_exc(limit=3)}
        finally:
            libres.put(slot)

    rutas = [r for r in a.fds if r.strip()]
    if a.lista:
        rutas += [l.strip() for l in open(a.lista) if l.strip()]
    with cf.ThreadPoolExecutor(a.hilos) as ex:
        for r in ex.map(tarea, rutas):
            res.append(r)
            print(f"{r['estado']:9s} {r['juego'][:70]}  "
                  + (f"pantallas {r['en_ref']}/{r['pantallas_n8']} en la ref., última {'sí' if r['ultima'] else 'no'}"
                     if 'coincide' in r else r.get('error', f"fotogramas ref {r.get('fot_ref')}, n8 {r.get('fot_n8')}")),
                  flush=True)
    (salida / 'resultados.json').write_text(json.dumps(sorted(res, key=lambda r: r['juego']), ensure_ascii=False,
                                                       indent=1))


if __name__ == '__main__':
    main()
