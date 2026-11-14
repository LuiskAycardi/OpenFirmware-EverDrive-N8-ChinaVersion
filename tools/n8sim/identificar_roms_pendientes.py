#!/usr/bin/env python3
"""Inventario sin filtros editoriales de ROMs para mappers aún sin cobertura NTSC."""
import argparse
import collections
import json
import pathlib

import cobertura


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--coleccion', type=pathlib.Path, default=cobertura.ROMSET)
    ap.add_argument('--seleccion', type=pathlib.Path,
                    default=cobertura.HERE / 'cobertura/completa/seleccion_juegos.json')
    args = ap.parse_args()
    seleccion = json.loads(args.seleccion.read_text())
    pendientes = set(seleccion['mappers_sin_partidas'])
    roms = collections.defaultdict(list)
    examinadas = 0
    for ruta in sorted(args.coleccion.rglob('*')):
        if not ruta.is_file() or ruta.suffix.lower() != '.nes':
            continue
        examinadas += 1
        info = cobertura.difftest.ines(ruta)
        if not info or info['mapper'] not in pendientes:
            continue
        with ruta.open('rb') as f:
            h = f.read(16)
        nes2 = (h[7] & 12) == 8
        timing = (h[12] & 3) if nes2 else (h[9] & 1)
        compatible = cobertura.compatible_ntsc(ruta)
        motivo = cobertura.difftest.supported(info)
        roms[info['mapper']].append(dict(
            archivo=ruta.name, ruta=str(ruta.resolve()),
            temporizacion=('NTSC', 'PAL', 'multirregión', 'Dendy')[timing],
            compatible_ntsc_cabecera=compatible,
            submapper=h[8] >> 4 if nes2 else None,
            prg_kb=info['prg_kb'], chr_kb=info['chr_kb'],
            limite_banco=motivo,
            candidato_para_medir=compatible and motivo is None,
            excluida_por_filtro_previo=bool(cobertura.EXCLUIR.search(ruta.name)
                                           or cobertura.difftest.SKIP_NAME.search(ruta.name)),
            cobertura_medida=False))
    grupos = collections.defaultdict(list)
    detalle = {}
    for m in sorted(pendientes):
        filas = roms[m]
        if any(r['candidato_para_medir'] for r in filas):
            estado = 'Candidatos NTSC/multirregión para medir'
        elif any(r['compatible_ntsc_cabecera'] for r in filas):
            estado = 'NTSC/multirregión fuera del límite del banco'
        elif filas:
            estado = 'Solo PAL o Dendy'
        else:
            estado = 'Sin ROMs en la colección'
        grupos[estado].append(m)
        detalle[m] = dict(estado=estado, roms=filas)
    resultado = dict(coleccion=str(args.coleccion.resolve()), archivos_nes_examinados=examinadas,
                     mappers_pendientes=len(pendientes), grupos=dict(grupos), mappers=detalle)
    carpeta = args.seleccion.parent
    (carpeta / 'roms_pendientes_ntsc.json').write_text(json.dumps(resultado, ensure_ascii=False, indent=2) + '\n')
    md = ['# ROMs identificadas para los mappers pendientes', '',
          f'Colección: `{args.coleccion.resolve()}`. Se examinaron **{examinadas} archivos .nes** '
          f'recursivamente para los **{len(pendientes)} mappers** sin medición NTSC.', '',
          'Se incluyen Pirate, Aftermarket, homebrew, demos y betas si existen: las etiquetas no '
          'descartan una ROM de este inventario. La temporización se lee de la cabecera; se admiten '
          'NTSC y multirregión y se excluyen PAL y Dendy de los candidatos.', '',
          '**Identificar una ROM no prueba su funcionamiento en la NES ni mide su cobertura.** '
          'Estos candidatos aún no sustituyen los juegos medidos del listado principal. '
          'Los tamaños superiores a 512 KB de PRG o CHR quedan fuera del banco actual. '
          'También se registra el submapper, cuya compatibilidad debe comprobarse antes de medir.', '']
    for estado, mappers in grupos.items():
        md += [f'## {estado} ({len(mappers)} mappers)', '', ', '.join(map(str, mappers)), '']
    md += ['## Candidatos compatibles con el límite de memoria del banco', '',
           '| Mapper | ROM | Temporización | Submapper | PRG / CHR (KB) |',
           '| --- | --- | --- | --- | --- |']
    for m, d in detalle.items():
        for r in d['roms']:
            if r['candidato_para_medir']:
                md.append(f"| {m} | {r['archivo'].replace('|', '/')} | {r['temporizacion']} | "
                          f"{r['submapper']} | {r['prg_kb']} / {r['chr_kb']} |")
    md += ['', '## ROMs NTSC/multirregión fuera del límite de memoria', '',
           '| Mapper | ROM | Temporización | Límite | PRG / CHR (KB) |',
           '| --- | --- | --- | --- | --- |']
    for m, d in detalle.items():
        for r in d['roms']:
            if r['compatible_ntsc_cabecera'] and r['limite_banco']:
                md.append(f"| {m} | {r['archivo'].replace('|', '/')} | {r['temporizacion']} | "
                          f"{r['limite_banco']} | {r['prg_kb']} / {r['chr_kb']} |")
    (carpeta / 'roms_pendientes_ntsc.md').write_text('\n'.join(md) + '\n')
    for estado, mappers in grupos.items():
        print(f'{estado}: {len(mappers)} mappers ({", ".join(map(str, mappers))})')
    print(f'Archivos examinados: {examinadas}; candidatos para medir: '
          f'{sum(r["candidato_para_medir"] for d in detalle.values() for r in d["roms"])}')


if __name__ == '__main__':
    main()
