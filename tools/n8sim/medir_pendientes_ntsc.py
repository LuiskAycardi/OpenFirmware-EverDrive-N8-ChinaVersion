#!/usr/bin/env python3
"""Audita memoria y mide candidatos pendientes; guarda resultados reanudables por ROM."""
import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import pathlib
import re

import cobertura
import memoria_n8


def escribir(ruta, valor):
    tmp = ruta.with_suffix(ruta.suffix + '.tmp')
    tmp.write_text(json.dumps(valor, ensure_ascii=False, indent=1) + '\n')
    tmp.replace(ruta)


def medir(rom, mapper, lib, clk, frames, carpeta):
    r = cobertura.jugar(os.getpid(), rom, mapper, lib, clk, frames, 7, carpeta)
    if r['fotogramas'] != frames or not r['cov']:
        r['error'] = f"Partida incompleta: {r['fotogramas']}/{frames} fotogramas"
    escribir(carpeta / 'resultado.json', r)
    return r


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--inventario', type=pathlib.Path, default=cobertura.HERE / 'cobertura/completa/roms_pendientes_ntsc.json')
    ap.add_argument('--out', type=pathlib.Path, default=cobertura.HERE / 'cobertura/completa/medicion_pendientes_ntsc')
    ap.add_argument('--jobs', type=int, default=4)
    ap.add_argument('--frames', type=int, default=1200)
    ap.add_argument('--solo-auditar', action='store_true')
    a = ap.parse_args()
    salida = a.out.resolve()
    salida.mkdir(parents=True, exist_ok=True)
    inv = json.loads(a.inventario.read_text())
    auditoria, plan = [], []
    for m, d in inv['mappers'].items():
        for r in d['roms']:
            audit = memoria_n8.revisar(r['ruta'])
            audit.update(rom=r['ruta'], mapper=int(m), ntsc=cobertura.compatible_ntsc(r['ruta']))
            auditoria.append(audit)
            if audit['admitida'] and audit['ntsc']:
                plan.append((r['ruta'], int(m)))
    escribir(salida / 'auditoria_memoria.json', auditoria)
    escribir(salida / 'plan.json', dict(frames=a.frames, seed=7, jobs=a.jobs, roms=plan))
    print(f'Auditoría: {len(auditoria)} ROMs; {len(plan)} admitidas para medir; '
          f'{len({m for _,m in plan})} mappers.', flush=True)
    if a.solo_auditar:
        return
    texto = (cobertura.RTL_DIR / 'n8_top.v').read_text()
    tabla = cobertura.simtop.mapper_table(texto)
    cache = cobertura.modelos_cov({tabla[m] for _,m in plan},a.jobs)
    clk50 = set()
    for linea in texto.splitlines():
        match = cobertura.simtop.INST.match(linea)
        if match:
            src = (cobertura.RTL_DIR / f'{match.group(3)}.v').read_text()
            if 'posedge clk' in src or 'a12_filter' in src or match.group(2) in ('N8_MAPPER_D','N8_MAPPER_XD','N8_MAPPER_DS','N8_MAPPER_XDP'):
                clk50.add(match.group(5))
    res = []
    with cf.ProcessPoolExecutor(max_workers=a.jobs) as ex:
        pendientes = {}
        for rom,m in plan:
            clave = re.sub('[^A-Za-z0-9]+','_',pathlib.Path(rom).stem)[:65]
            clave += '_' + hashlib.sha256(rom.encode()).hexdigest()[:10]
            d = salida / f'{m:03d}' / clave
            d.mkdir(parents=True,exist_ok=True)
            guardado = d / 'resultado.json'
            if guardado.exists():
                r = json.loads(guardado.read_text())
                if not r.get('error') and r.get('fotogramas') == a.frames and r.get('cov') and pathlib.Path(r['cov']).is_file():
                    res.append(r)
                    continue
            bus = tabla[m]
            f = ex.submit(medir,rom,m,cache/f'lib_{bus}.so',50.0 if bus in clk50 else 25.0,a.frames,d)
            pendientes[f] = (rom,m)
        print(f'Reutilizadas {len(res)}; nuevas {len(pendientes)}; modelos {cache}',flush=True)
        for f in cf.as_completed(pendientes):
            rom,m = pendientes[f]
            try:
                r = f.result()
            except Exception as e:
                r = dict(rom=rom,mapper=m,error=str(e),cov=None)
            res.append(r)
            escribir(salida / 'partidas_todas.json',res)
            buenas = [r for r in res if not r.get('error')]
            escribir(salida / 'partidas.json',buenas)
            print(f"[{len(res)}/{len(plan)}] mapper {m}: {pathlib.Path(rom).name}: "
                  f"{r.get('secs','?')} s {r.get('error','OK')}",flush=True)
    cobertura.informe(salida)


if __name__ == '__main__':
    main()
