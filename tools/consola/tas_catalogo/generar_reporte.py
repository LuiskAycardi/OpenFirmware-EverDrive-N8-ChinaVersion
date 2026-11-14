"""Lista completa de la revisión en TASVideos, sin ejecutar emuladores."""
import collections
import hashlib
import json
import pathlib

HERE=pathlib.Path(__file__).resolve().parent


def enlaces(ids):
    return ', '.join(f'[{i}](https://tasvideos.org/{i}M)' for i in ids) or '—'


def main():
    d=json.loads((HERE/'validacion_tas.json').read_text())
    pubs={p['id']:p for p in d['peliculas']}
    catalogo=json.loads((HERE/'publications.json').read_text())
    fm2=[p for p in catalogo if p['movieFileName'].lower().endswith('.fm2')]
    assert len(d['roms'])==204
    assert all((HERE/'peliculas'/f"{p['id']}.zip").exists() for p in fm2)
    assert not any('Descarga no disponible' in p['errores_banco'] or
                   any(e.startswith('Error al inspeccionar:') for e in p['errores_banco'])
                   for p in d['peliculas'] if p['formato']=='fm2')
    aptas=[r for r in d['roms'] if r['aptas']]
    especiales=[r for r in d['roms'] if r['checksum_exacto'] and not r['aptas']]
    otros_formatos=[r for r in d['roms'] if not r['aptas'] and r['checksum_exacto_catalogo']]
    md=['# TASVideos: revisión completa de las ROMs seleccionadas', '',
        'Fecha de consulta: **14 de noviembre de 2026**. Revisión documental y de archivos; '
        '**sin validación de sincronización en Mesen2 ni en la NES**. Las dos reproducciones '
        'que se habían iniciado se detuvieron por instrucción del usuario y no se usan como evidencia.', '',
        f'Se cruzaron **{len(d["roms"])} ROMs** con **{len(catalogo)} publicaciones NES** '
        f'(actuales e históricas). Se descargaron y revisaron las cabeceras de **las {len(fm2)} '
        'películas FM2 del catálogo completo**, por checksum, sin depender del nombre del juego. '
        'Las entradas de las películas coincidentes se inspeccionaron para detectar requisitos que '
        'el banco no reproduce.', '',
        'Fuentes: [API oficial](https://tasvideos.org/api), '
        '[catálogo NES de TASVideos](https://tasvideos.org/movies-nes). '
        'Los metadatos consultados, los ZIP originales y las películas coincidentes se conservan '
        'en esta carpeta. Las publicaciones se enlazan individualmente en las tablas.', '',
        '## Resultado', '',
        f'- **{len(aptas)} ROMs** tienen al menos una FM2 con checksum exacto y entradas admitidas por el banco.',
        f'- **{sum(pubs[r["recomendada"]]["verificado_consola_tasvideos"] for r in aptas)}** '
        'de ellas tienen una película marcada como verificada en consola por TASVideos.',
        f'- **{len(especiales)} ROMs** tienen FM2 con checksum exacto, pero requieren entradas/periféricos no admitidos.',
        f'- **{len(otros_formatos)} ROMs adicionales** coinciden por hash con una versión de ROM del catálogo '
        'que tiene publicaciones en otro formato. Son candidatas a adaptar; no son ejecutables con el lector actual.', '',
        '## Criterios aplicados', '',
        'Se compara el MD5 de la ROM sin cabecera iNES con `romChecksum` de la FM2, tal como hace '
        '`tools/consola/tas.py`. La película debe ser NTSC, partir sin savestate/SRAM precargada, '
        'usar mando NES estándar en el primer puerto y no depender de Four Score, micrófono, '
        'segundo mando, periféricos adicionales o resets intermedios. Solo se admite la orden de '
        'encendido inicial; el banco actual no ejecuta los otros comandos de la película.', '',
        'La verificación en consola corresponde a la película publicada y a la configuración usada '
        'por sus verificadores, no a nuestra NES/N8. El checksum exacto y el formato compatible no '
        'prueban sincronización con Mesen2 ni con el arranque desde el menú N8. El desplazamiento '
        'de entrada y el estado inicial siguen pendientes de validar.', '',
        'Se incluyen películas sustituidas por otras más nuevas cuando son las que coinciden con '
        'nuestra ROM y formato. La columna «Histórica» identifica esos casos. Para elegir una película '
        'se prioriza verificación en consola, luego publicación vigente y después menor duración.', '',
        '## FM2 con checksum exacto y entradas admitidas', '',
        '| Mapper | ROM exacta | TAS recomendado | Duración | Verificado en consola por TASVideos | Histórica |',
        '| --- | --- | --- | --- | --- | --- |']
    for r in aptas:
        p=pubs[r['recomendada']]
        segundos=round(p['segundos_aproximados'])
        md.append(f"| {r['mapper']} | {r['juego']} | {enlaces([p['id']])} | "
                  f"{segundos//60}:{segundos%60:02d} | {'Sí' if p['verificado_consola_tasvideos'] else 'No consta'} | "
                  f"{'Sí' if p['obsoleto'] else 'No'} |")
    md+=['', '## Coincidencia exacta de ROM, pero entradas no admitidas', '',
         '| Mapper | ROM | Publicaciones FM2 | Motivo |', '| --- | --- | --- | --- |']
    for r in especiales:
        motivos=sorted({e for i in r['checksum_exacto'] for e in pubs[i]['errores_banco']})
        md.append(f"| {r['mapper']} | {r['juego']} | {enlaces(r['checksum_exacto'])} | {'; '.join(motivos)} |")
    md+=['', '## Coincidencia de hash en catálogo, pero formato pendiente de adaptación', '',
         'La coincidencia de MD5/SHA1 es con la versión de ROM registrada en TASVideos. '
         'No se ha convertido ni comprobado el flujo de entradas BK2/BKM.', '',
         '| Mapper | ROM | Publicaciones | Formatos |', '| --- | --- | --- | --- |']
    for r in otros_formatos:
        md.append(f"| {r['mapper']} | {r['juego']} | {enlaces(r['checksum_exacto_catalogo'])} | "
                  f"{', '.join(sorted({pubs[i]['formato'] for i in r['checksum_exacto_catalogo']}))} |")
    md+=['', '## Lista completa de las 204 ROMs', '',
         '«Sin coincidencia FM2» significa que ninguna de las 809 películas FM2 publicadas consultadas '
         'declara el checksum de nuestra ROM. No significa que no pueda existir un TAS en envíos, '
         'userfiles, otras webs o formatos diferentes. Las coincidencias por título son orientativas '
         'y no sustituyen el checksum.', '',
         '| Mapper | ROM seleccionada | Resultado para el banco actual | Publicaciones con checksum exacto | Publicaciones relacionadas por título |',
         '| --- | --- | --- | --- | --- |']
    for r in d['roms']:
        if r['aptas']:
            estado='FM2 candidata; sincronización pendiente'
        elif r['checksum_exacto']:
            estado='FM2 exacta; requiere adaptar entradas/periféricos'
        elif r['checksum_exacto_catalogo']:
            estado='ROM exacta en catálogo; requiere otro formato'
        else:
            estado='Sin coincidencia FM2 con esta ROM'
        exactas=sorted(set(r['checksum_exacto']+r['checksum_exacto_catalogo']))
        md.append(f"| {r['mapper']} | {r['juego'].replace('|','/')} | {estado} | {enlaces(exactas)} | "
                  f"{enlaces(r['publicaciones_relacionadas'])} |")
    md+=['', '## Archivos locales de las películas candidatas', '',
         '| Mapper | ROM | Película | Otras FM2 compatibles |', '| --- | --- | --- | --- |']
    for r in aptas:
        p=pubs[r['recomendada']]
        md.append(f"| {r['mapper']} | {r['juego']} | [FM2 {p['id']}](fm2/{p['id']}.fm2) | {enlaces(r['aptas'])} |")
    md+=['', 'No se han copiado ROMs a la SD ni iniciado pruebas en la consola. '
         'La siguiente fase será comprobar sincronización únicamente después de presentar y revisar esta lista.', '']
    (HERE/'reporte_tas.md').write_text('\n'.join(md))
    manifest=dict(fecha=d['fecha'],fuente='https://tasvideos.org/api/v1/publications?Systems=NES&ShowObsoleted=true',
                  publicaciones_nes=len(catalogo),fm2_nes=len(fm2),fm2_consultadas_sin_descarga_fallida=len(fm2),
                  roms=204,candidatas_fm2=len(aptas),exactas_entradas_incompatibles=len(especiales),
                  exactas_catalogo_otro_formato=len(otros_formatos),
                  pruebas_mesen='Detenidas por instrucción del usuario; sin resultados usados',
                  pruebas_consola='No iniciadas',
                  peliculas=[dict(publicacion=r['recomendada'],rom=r['juego'],mapper=r['mapper'],
                        archivo=pubs[r['recomendada']]['archivo_fm2'],
                        sha256=hashlib.sha256(pathlib.Path(pubs[r['recomendada']]['archivo_fm2']).read_bytes()).hexdigest())
                        for r in aptas])
    (HERE/'resumen_revision.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=1)+'\n')
    print('Reporte completo:',HERE/'reporte_tas.md')
    print({k:v for k,v in manifest.items() if k!='peliculas'})


if __name__=='__main__':main()
