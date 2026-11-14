"""Resume la búsqueda externa y distingue películas nuevas de copias ya revisadas."""
import hashlib
import json
import pathlib
import sys

HERE=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import tas


def main():
    previo=json.loads((HERE/'validacion_tas.json').read_text())
    externo=json.loads((HERE/'validacion_externa.json').read_text())
    fuentes=json.loads((HERE/'externos/fuentes.json').read_text())
    metadata=json.loads((HERE/'externos/peliculas.json').read_text())
    originales={}
    for p in previo['peliculas']:
        if p.get('archivo_fm2') and p['roms_coincidentes']:
            _,inputs,ordenes=tas.leer_fm2(p['archivo_fm2'])
            clave=(hashlib.sha256(bytes(inputs)).hexdigest(),tuple(ordenes))
            originales.setdefault(clave,[]).append(p['id'])
    for p in externo['peliculas']:
        if p['roms_coincidentes']:
            _,inputs,ordenes=tas.leer_fm2(p['archivo_fm2'])
            clave=(hashlib.sha256(bytes(inputs)).hexdigest(),tuple(ordenes))
            p['mismas_entradas_que_tasvideos']=originales.get(clave,[])
    (HERE/'validacion_externa.json').write_text(json.dumps(externo,ensure_ascii=False,indent=1)+'\n')
    cubiertas={r['juego'] for r in previo['roms'] if r['aptas']}
    nuevas=[r for r in externo['roms'] if r['aptas'] and r['juego'] not in cubiertas]
    exactas=[p for p in externo['peliculas'] if p['roms_coincidentes']]
    md=['# Búsqueda de TAS en repositorios externos', '',
        'Fecha: **14 de noviembre de 2026**. Revisión estática de fuentes y archivos; '
        '**sin ejecutar Mesen, FCEUX ni la consola**.', '',
        f'Se inspeccionaron **14 árboles completos de repositorios GitHub** y el índice público '
        f'de dwangoAC en acbit. Se descargaron **{len(externo["peliculas"])} películas FM2** '
        '(contando copias/versiones) y se cruzaron contra los checksums de las **204 ROMs seleccionadas**.', '',
        f'Resultado: **{len(nuevas)} ROMs adicionales** con FM2 utilizable por el banco actual. '
        f'Las **{len(exactas)} coincidencias exactas** corresponden a Akumajou Densetsu, que ya '
        'estaba entre las 14 candidatas. Ambas tienen las mismas entradas y órdenes que '
        '[TASVideos 1979](https://tasvideos.org/1979M); no son recorridos nuevos.', '',
        '## Fuentes inspeccionadas', '',
        '| Fuente | Resultado del árbol/índice |', '| --- | --- |']
    for f in fuentes:
        if f.get('arbol_sha'):
            paths=f['archivos']
            fm2=sum(x.lower().endswith('.fm2') for x in paths)
            resultado=f'{fm2} archivos FM2; {len(paths)-fm2} películas de otros formatos'
            if f.get('truncado'):resultado+='; árbol truncado'
        else:resultado=f.get('estado') or f.get('error','Sin detalle')
        md.append(f"| [{f['fuente']}]({f['fuente']}) | {resultado} |")
    md+=['', 'Microstorage (`dehacked.2y.net`) se intentó por HTTPS y HTTP: '
         'ambas conexiones fueron rechazadas. No se cuentan sus archivos como revisados.', '',
         '## Hallazgos relevantes', '',
         '| Juego seleccionado | Mapper | Fuente | Resultado |', '| --- | --- | --- | --- |',
         '| Akumajou Densetsu (Japan) | 24 | '
         '[jedahan/autones](https://github.com/jedahan/autones/tree/master/movies) | '
         'Dos FM2 con checksum exacto y entradas admitidas; ambas duplican las entradas de TASVideos 1979. |',
         '| High Speed (USA) | 119 | [Archivo de dwangoAC](https://acbit.net/static/tas/) | '
         'Cuatro películas/versiones declaran MD5 `e9604d2edfe39495d617d51144942d94`; '
         'nuestra ROM declara/calcula `b472f97c9f85b13eaabc4400cfe3b7bd`. '
         'Tampoco coincide la ROM europea disponible. No se aceptan por nombre. |',
         '| Crazy Climber (Japan) | 180 | [Archivo de dwangoAC](https://acbit.net/static/tas/) | '
         'La BK2 encontrada declara plataforma WSWAN y núcleo Cygne/Mednafen: es WonderSwan, no NES. |',
         '| Mega Man 2 (USA) (iam8bit) | 30 | '
         '[TAS_Fun-](https://github.com/camdenspielman-hub/TAS_Fun-) y '
         '[retrochallenges-assets](https://github.com/heliacode/retrochallenges-assets) | '
         'Se localizaron películas de Rockman/Mega Man 2; sus checksums no coinciden con nuestra ROM seleccionada. |',
         '| Juegos del paquete TASDeck | — | [TASDeck](https://github.com/ChuckCaplan/TASDeck) | '
         'Tres dumps R08 inventariados; no se han convertido ni se acredita identidad de ROM con ellos. |', '',
         '## Auditoría de las 43 películas FM2', '',
         '| Archivo | Fuente | Coincidencia exacta | Resultado |', '| --- | --- | --- | --- |']
    for p in externo['peliculas']:
        coincide='; '.join(p['roms_coincidentes']) or 'No'
        resultado='; '.join(p['errores_banco']) or 'Formato/entradas admitidos; sincronización pendiente'
        if p.get('mismas_entradas_que_tasvideos'):
            resultado+='; mismas entradas que TASVideos '+', '.join(map(str,p['mismas_entradas_que_tasvideos']))
        md.append(f"| {p['titulo'].replace('|','/')} | [Origen]({p['publicacion'].replace(' ','%20')}) | "
                  f"{coincide} | {resultado} |")
    md+=['', 'Las copias GitHub se comprobaron contra el SHA del blob publicado en el árbol consultado. '
         'Se conservaron las fuentes, archivos descargados y hashes. No se descargaron ROMs ni '
         'se ejecutó código de los repositorios externos.', '',
         'La búsqueda cubre las fuentes enumeradas; no demuestra que no existan otras películas '
         'en archivos privados, envíos, userfiles o repositorios no encontrados. '
         'La lista principal sigue teniendo **14 ROMs con FM2 candidata**, pendientes de sincronización.', '']
    (HERE/'reporte_fuentes_externas.md').write_text('\n'.join(md))
    resumen=dict(fecha='2026-11-14',repositorios_github=14,archivos_fm2=len(externo['peliculas']),
                  coincidencias_exactas=len(exactas),roms_adicionales=len(nuevas),
                  roms_candidatas_totales=len(cubiertas|{r['juego'] for r in nuevas}),
                  microstorage='Conexión rechazada por HTTP y HTTPS',
                  nuevas_roms=nuevas,pruebas_emulador=False,pruebas_consola=False)
    (HERE/'externos/resumen.json').write_text(json.dumps(resumen,ensure_ascii=False,indent=1)+'\n')
    principal=HERE/'reporte_tas.md'
    texto=principal.read_text().split('\n## Búsqueda en otros repositorios\n')[0]
    texto+='\n## Búsqueda en otros repositorios\n\nSe revisaron 43 películas FM2 de fuentes externas. '
    texto+='Las dos coincidencias exactas repiten una película ya revisada de Akumajou Densetsu. '
    texto+='La selección sigue en 14 ROMs candidatas. '
    texto+='[Fuentes, hallazgos y motivos de descarte](reporte_fuentes_externas.md).\n'
    principal.write_text(texto)
    print(resumen)


if __name__=='__main__':main()
