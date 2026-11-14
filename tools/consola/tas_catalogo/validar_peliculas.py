"""Valida películas descargadas contra las ROMs exactas y las capacidades del banco."""
import base64
import collections
import hashlib
import json
import pathlib
import sys
import zipfile

HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'tools/n8sim'))
import cobertura


def main(publicaciones=None, archivo_salida='validacion_tas.json'):
    base=ROOT/'tools/n8sim/cobertura/completa'
    seleccion=json.loads((base/'seleccion_juegos.json').read_text())['seleccion']
    partidas=json.loads((base/'ntsc_revisada/partidas.json').read_text())
    paths={pathlib.Path(r['rom']).name:r['rom'] for r in partidas}
    pubs=publicaciones if publicaciones is not None else json.loads((HERE/'publications.json').read_text())
    games={g['id']:g for g in json.loads((HERE/'games.json').read_text())}
    roms=[]
    for j in seleccion:
        b=pathlib.Path(paths[j['juego']]).read_bytes()
        digest=hashlib.md5(b[16:]).digest()
        roms.append(dict(**j,ruta=paths[j['juego']],md5_payload=digest.hex(),
                         checksum_fm2='base64:'+base64.b64encode(digest).decode(),
                         hashes_catalogo={hashlib.md5(b).hexdigest().upper(),digest.hex().upper(),
                                          hashlib.sha1(b).hexdigest().upper(),hashlib.sha1(b[16:]).hexdigest().upper()}))
    peliculas=[]
    extraidas=HERE/('fm2_externas' if publicaciones is not None else 'fm2')
    extraidas.mkdir(exist_ok=True)
    for pub in pubs:
        r=dict(id=pub['id'],publicacion=pub.get('url') or f"https://tasvideos.org/{pub['id']}M",
               titulo=pub['title'],game_id=pub['gameId'],formato=pub['movieFileName'].rsplit('.',1)[-1],
               verificado_consola_tasvideos='Verified' in pub['flags'],
               obsoleto=pub['obsoletedById'] is not None, fotogramas_publicacion=pub['frames'],
               errores_banco=[],roms_coincidentes=[])
        archivo=pathlib.Path(pub['archivo_zip']) if pub.get('archivo_zip') else HERE/'peliculas'/f"{pub['id']}.zip"
        if r['formato'].lower()!='fm2':
            r['errores_banco'].append('Formato no admitido por el banco actual (solo FM2)')
            peliculas.append(r)
            continue
        if not archivo.exists():
            r['errores_banco'].append('Descarga no disponible')
            peliculas.append(r)
            continue
        try:
            with zipfile.ZipFile(archivo) as z:
                nombres=[n for n in z.namelist() if n.lower().endswith('.fm2')]
                if not nombres:
                    r['errores_banco'].append('Formato no admitido por el banco actual (solo FM2)')
                    peliculas.append(r)
                    continue
                if len(nombres)!=1:
                    r['errores_banco'].append('Archivo con varias películas FM2: selección manual requerida')
                    peliculas.append(r)
                    continue
                # Primero comparar la cabecera: no extraer al repositorio cientos
                # de películas de juegos que no forman parte de nuestra selección.
                preliminar={}
                with z.open(nombres[0]) as entrada:
                    for raw in entrada:
                        linea=raw.decode('utf-8',errors='replace').rstrip('\r\n')
                        if linea.startswith('|'):
                            break
                        if ' ' in linea:
                            k,v=linea.split(' ',1);preliminar[k]=v.strip()
                checksum=preliminar.get('romChecksum','')
                coincide=any(checksum==rom['checksum_fm2'] or
                             checksum.lower().removeprefix('0x')==rom['md5_payload'] for rom in roms)
                if not coincide:
                    r['cabecera']=preliminar
                    r['errores_banco'].append('Checksum de película no coincide con ninguna ROM seleccionada')
                    peliculas.append(r)
                    continue
                datos=z.read(nombres[0])
            texto=datos.decode('utf-8',errors='replace')
            cab={}
            entradas=[]
            for linea in texto.splitlines():
                if linea.startswith('|'):entradas.append(linea.split('|'))
                elif ' ' in linea:
                    k,v=linea.split(' ',1);cab[k]=v.strip()
            r['cabecera']=cab
            r['fotogramas']=len(entradas)
            r['segundos_aproximados']=round(len(entradas)/60.0988,1)
            r['archivo_fm2']=str(extraidas/f"{pub['id']}.fm2")
            pathlib.Path(r['archivo_fm2']).write_bytes(datos)
            if not entradas:r['errores_banco'].append('Sin entradas de fotograma')
            if cab.get('palFlag','0')!='0':r['errores_banco'].append('Película PAL')
            if cab.get('fourscore','0')!='0':r['errores_banco'].append('Requiere Four Score')
            if cab.get('microphone','0')!='0':r['errores_banco'].append('Requiere micrófono')
            if cab.get('port0','1')!='1':r['errores_banco'].append('Puerto 1 no es mando NES estándar')
            if cab.get('port1','0') not in ('0','1') or cab.get('port2','0')!='0':
                r['errores_banco'].append('Periférico adicional no admitido')
            if cab.get('binary','0')!='0':r['errores_banco'].append('FM2 binario no admitido')
            if cab.get('savestate') or cab.get('startsFromSavestate','0')!='0':
                r['errores_banco'].append('Arranca desde savestate')
            if cab.get('saveram') or cab.get('startsFromSaveRam','0')!='0':
                r['errores_banco'].append('Requiere estado inicial de SRAM no reproducido')
            for n,campos in enumerate(entradas):
                cmd=int(campos[1] or 0)
                if cmd and not (n==0 and cmd==2):
                    r['errores_banco'].append('Reset/órdenes durante la película no reproducidos por el banco')
                    break
            if any(len(c)>3 and any(x not in '. ' for x in c[3]) for c in entradas):
                r['errores_banco'].append('Usa botones del segundo mando')
            checksum=cab.get('romChecksum','')
            for rom in roms:
                if checksum==rom['checksum_fm2'] or checksum.lower().removeprefix('0x')==rom['md5_payload']:
                    r['roms_coincidentes'].append(rom['juego'])
        except Exception as e:r['errores_banco'].append(f'Error al inspeccionar: {e}')
        peliculas.append(r)
    por_rom=[]
    for rom in roms:
        exactas=[p for p in peliculas if rom['juego'] in p['roms_coincidentes']]
        aptas=[p for p in exactas if not p['errores_banco']]
        aptas.sort(key=lambda p:(not p['verificado_consola_tasvideos'],p['obsoleto'],p['fotogramas']))
        nombre=cobertura._norm(rom['juego'])
        ids={g['id'] for g in games.values() if any(cobertura._norm(n)==nombre for n in
             [g['displayName']]+[(v.get('name') or '') for v in g['versions']])}
        versiones={v['id'] for g in games.values() for v in g['versions']
                   if (v.get('md5') or '').upper() in rom['hashes_catalogo']
                   or (v.get('sha1') or '').upper() in rom['hashes_catalogo']}
        catalogo=[p['id'] for p in pubs if p['gameVersionId'] in versiones]
        relacionadas=[p for p in peliculas if p['game_id'] in ids]
        estado=('Candidata FM2 con checksum exacto; falta validar sincronización' if aptas else
                'Checksum exacto pero entradas incompatibles con el banco' if exactas else
                'Publicaciones localizadas; sin FM2 compatible con checksum exacto' if relacionadas else
                'Sin publicación identificada por título o hash en este cruce')
        por_rom.append(dict(mapper=rom['mapper'],juego=rom['juego'],ruta=rom['ruta'],
                            estado=estado,md5_payload=rom['md5_payload'],
                            publicaciones_relacionadas=[p['id'] for p in relacionadas],
                            checksum_exacto_catalogo=catalogo,
                            checksum_exacto=[p['id'] for p in exactas],
                            aptas=[p['id'] for p in aptas],
                            recomendada=aptas[0]['id'] if aptas else None))
    resultado=dict(fecha='2026-11-14',roms_seleccionadas=len(roms),publicaciones_revisadas=len(peliculas),
                   roms=por_rom,peliculas=peliculas)
    (HERE/archivo_salida).write_text(json.dumps(resultado,ensure_ascii=False,indent=1)+'\n')
    print('ROMs por estado',dict(collections.Counter(r['estado'] for r in por_rom)))
    for r in por_rom:
        if r['aptas']:
            p=next(p for p in peliculas if p['id']==r['recomendada'])
            print(r['mapper'],r['juego'],'TAS',r['recomendada'],'verificado',p['verificado_consola_tasvideos'],
                  'min',round(p['segundos_aproximados']/60,1))
    print('Errores',dict(collections.Counter(e for p in peliculas for e in p['errores_banco'])))


if __name__=='__main__':main()
