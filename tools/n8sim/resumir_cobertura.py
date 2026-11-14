#!/usr/bin/env python3
"""Audita una tanda existente y exporta su selección de juegos, sin repetir partidas."""
import argparse
import json
import pathlib

import cobertura


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('carpeta', type=pathlib.Path)
    ap.add_argument('--ntsc', action='store_true', help='exporta solo partidas NTSC/multirregión a una subcarpeta')
    ap.add_argument('--adicional', type=pathlib.Path, help='carpeta con nuevas partidas que añadir al análisis')
    args = ap.parse_args()
    carpeta = args.carpeta.resolve()
    resumen_anterior = json.loads((carpeta / 'cobertura.json').read_text())
    partidas = json.loads((carpeta / 'partidas.json').read_text())
    if args.adicional:
        adicionales = json.loads((args.adicional / 'partidas.json').read_text())
        existentes = {r['rom'] for r in partidas}
        partidas += [r for r in adicionales if r['rom'] not in existentes]
    excluidas = []
    if args.ntsc:
        excluidas = [r for r in partidas if not cobertura.compatible_ntsc(r['rom'])]
        partidas = [r for r in partidas if cobertura.compatible_ntsc(r['rom'])]
        carpeta = carpeta / 'ntsc'
        carpeta.mkdir(exist_ok=True)
        (carpeta / 'partidas.json').write_text(json.dumps(partidas, ensure_ascii=False, indent=1))
        (carpeta / 'excluidas.json').write_text(json.dumps(excluidas, ensure_ascii=False, indent=1))
        cobertura.informe(carpeta)
    resumen = json.loads((carpeta / 'cobertura.json').read_text())
    fallos = [r for r in partidas if r.get('error') or not r.get('cov')
              or not pathlib.Path(r['cov']).is_file()]
    if fallos:
        raise SystemExit(f'Tanda incompleta: {len(fallos)} partidas sin cobertura válida')
    tas = cobertura.con_tas()
    tabla = cobertura.simtop.mapper_table((cobertura.RTL_DIR / 'n8_top.v').read_text())
    ausentes = sorted(set(tabla) - {int(m) for m in resumen})
    salida = []
    for m, datos in sorted(resumen.items(), key=lambda par: int(par[0])):
        total = datos['puntos_instancia']
        for orden, juego in enumerate(datos['elegir'], 1):
            salida.append(dict(mapper=int(m), orden=orden, **juego,
                puntos_instancia=total, alcanzado=datos['alcanzado'],
                porcentaje_rtl=round(100 * juego['acumulado'] / total, 2) if total else None,
                tas_publicado_lista_local=cobertura._norm(juego['juego']) in tas,
                tas_verificado_consola=None))
    ntas = sum(j['tas_publicado_lista_local'] for j in salida)
    timings = {}
    if args.ntsc:
        for r in partidas:
            with open(r['rom'], 'rb') as f:
                h = f.read(16)
            timings[pathlib.Path(r['rom']).name] = ('multirregión' if
                (h[7] & 12) == 8 and (h[12] & 3) == 2 else 'NTSC')
        for j in salida:
            j['temporizacion_cabecera'] = timings[j['juego']]
    md = ['# Juegos seleccionados para probar los mappers' + (' — NES NTSC' if args.ntsc else ''), '',
          f'Tanda auditada: **{len(partidas)} partidas**, **{len(resumen)} mappers**, '
          f'**{len(salida)} juegos seleccionados**. Todas las partidas tienen archivo de cobertura.', '',
          '## Cómo leer los resultados', '',
          '- La selección voraz conserva el 100 % de los puntos alcanzados por los candidatos de cada mapper. '
          'Es una aproximación al conjunto mínimo; no garantiza el mínimo matemático.',
          '- Los puntos combinan cobertura de líneas y conmutación de bits. El porcentaje RTL usa como '
          'denominador los puntos instrumentados de la instancia, que puede compartir variantes de mapper. '
          'No mide directamente el porcentaje de funciones correctas.',
          '- Las partidas duran 1.200 fotogramas con entradas sintéticas; pueden quedarse en títulos o demos. '
          'No son recorridos completos con TAS ni validación de corrección del hardware.',
          f'- {ntas} juegos coinciden por título normalizado con la lista local de publicaciones TASVideos '
          '(2026-11-12). Esto no confirma región, revisión, checksum ni verificación en consola. '
          'La API y el listado de películas verificadas no fueron accesibles durante esta revisión; '
          'el estado de verificación queda pendiente, nunca se marca como falso.',
          ('- Filtro por temporización de cabecera: solo NTSC (0) o multirregión (2); '
           f'se excluyen {len(excluidas)} partidas PAL (1) o Dendy (3). Una ROM multirregión '
           'puede incluir Europe en el nombre y ser compatible con NTSC. Se reutilizan las mediciones '
           'de esas ROMs, sin transferir cobertura entre versiones regionales.' if args.ntsc else
           '- La selección medida incluye ROMs PAL y puede incluir betas. Para la NES NTSC se debe comprobar '
           'región y revisión; cambiar una ROM requiere volver a medir su cobertura.'), '',
          'Referencia para verificar películas: '
          '[TASVideos: Console Verification](https://tasvideos.org/ConsoleVerification/Legacy/Movies).', '',
          '## Selección por mapper', '',
          '| Mapper | Juegos en orden de aportación | Puntos alcanzados / RTL | RTL alcanzado |',
          '| --- | --- | --- | --- |']
    for m, datos in sorted(resumen.items(), key=lambda par: int(par[0])):
        juegos = [f"{j['juego'].removesuffix('.nes')} (+{j['nuevos']})"
                  + (f" [{timings[j['juego']]}]" if args.ntsc else '')
                  + (' [TAS publicado*]' if cobertura._norm(j['juego']) in tas else '')
                  for j in datos['elegir']]
        total = datos['puntos_instancia']
        pct = 100 * datos['alcanzado'] / total if total else 0
        md.append(f"| {m} | {'; '.join(juegos).replace('|', '/')} | "
                  f"{datos['alcanzado']} / {total} | {pct:.1f} % |")
    sin_ntsc = sorted(set(map(int, resumen_anterior)) - set(map(int, resumen))) if args.ntsc else []
    if args.ntsc:
        md += ['', '## Efecto del filtro NTSC', '',
               f'Se excluyeron {len(excluidas)} partidas por cabecera PAL o Dendy. '
               'Se recalculó la selección usando los puntos de cada ROM admitida; '
               'no se sustituyeron nombres conservando mediciones de otra región.', '',
               'Mappers que tenían resultados en la tanda original y quedan sin medición compatible: '
               + (', '.join(map(str, sin_ntsc)) or 'ninguno') + '.', '',
               'La cobertura anterior incluía candidatos incompatibles. No se garantiza conservar esos '
               'puntos tras retirarlos; los porcentajes de la tabla corresponden exclusivamente '
               'a las ROMs admitidas.']
    md += ['', '## Mappers sin partidas en esta tanda', '',
           ', '.join(map(str, ausentes)), '',
           'Estos números existen en el top actual pero no tienen resultados en la tanda. '
           'No se les asigna cobertura cero ni se presupone que carezcan de ROMs en cualquier colección.', '',
           '## Siguiente validación', '',
           'Conservar los juegos complementarios: cada uno aporta puntos que el principal no alcanza. '
           'Para preparar recorridos completos, elegir una película concreta, comprobar checksum y región, '
           'reproducirla primero en Mesen2 con cobertura y después en la NES. '
           'La reproducción en consola y el aumento de cobertura mediante TAS no se han ejecutado aquí.', '']
    (carpeta / 'seleccion_juegos.md').write_text('\n'.join(md))
    (carpeta / 'seleccion_juegos.json').write_text(json.dumps({
        'partidas': len(partidas), 'mappers': len(resumen), 'juegos': len(salida),
        'coincidencias_tas_local': ntas, 'mappers_sin_partidas': ausentes,
        'mappers_sin_medicion_ntsc_previamente_medidos': sin_ntsc,
        'seleccion': salida}, ensure_ascii=False, indent=2) + '\n')
    print(f'{len(partidas)} partidas válidas; {len(resumen)} mappers; {len(salida)} juegos; '
          f'{ntas} coincidencias TAS; {len(ausentes)} mappers sin partidas.')
    print(carpeta / 'seleccion_juegos.md')


if __name__ == '__main__':
    main()
