"""Descarga solo películas de fuentes públicas y aplica la misma revisión estática."""
import concurrent.futures as cf
import hashlib
import html
import io
import json
import pathlib
import re
import urllib.parse
import urllib.request
import zipfile

import validar_peliculas

HERE=pathlib.Path(__file__).resolve().parent
OUT=HERE/'externos'


def descargar(url):
    # Los índices de algunos archivos publican espacios sin escapar.
    url=urllib.parse.quote(url,safe=':/?&=%+#')
    with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'N8-TAS-static-audit/1.0'}),timeout=40) as r:
        return r.read()


def main():
    OUT.mkdir(exist_ok=True)
    candidatos=[]
    fuentes=[]
    acbit='https://acbit.net/static/tas/'
    try:
        indice=descargar(acbit).decode()
        (OUT/'acbit_indice.html').write_text(indice)
        links=[html.unescape(x) for x in re.findall(r'href=[\"\']([^\"\']+)',indice,re.I)]
        for link in links:
            nombre=urllib.parse.unquote(link)
            if nombre.lower().endswith('.fm2') or (nombre.lower().endswith('.zip') and
                    any(k in nombre.lower() for k in ('high','climber','joust'))):
                candidatos.append(dict(fuente=acbit,nombre=nombre,url=urllib.parse.urljoin(acbit,link)))
        fuentes.append(dict(fuente=acbit,estado='Índice consultado'))
    except Exception as e:fuentes.append(dict(fuente=acbit,error=str(e)))
    for arbol in sorted(OUT.glob('*_arbol.json')):
        repo=arbol.name.removesuffix('_arbol.json').replace('_','/',1)
        tree=json.loads(arbol.read_text())
        archivos=[x for x in tree['tree'] if x['type']=='blob' and
                  x['path'].lower().endswith(('.fm2','.fm3','.bk2','.bkm','.fcm','.fmv','.r08','.tasd'))]
        fuentes.append(dict(fuente=f'https://github.com/{repo}',estado='Árbol consultado',
                            arbol_sha=tree['sha'],truncado=tree.get('truncated',False),
                            archivos=[x['path'] for x in archivos]))
        for f in archivos:
            # Los otros formatos quedan inventariados, no se convierten aquí.
            if not f['path'].lower().endswith('.fm2'):continue
            candidatos.append(dict(fuente=f'https://github.com/{repo}',nombre=f['path'],
                url=f"https://raw.githubusercontent.com/{repo}/HEAD/{f['path']}",
                pagina=f"https://github.com/{repo}/blob/HEAD/{f['path']}",blob_sha=f['sha']))
    def uno(c):
        try:
            b=descargar(c['url'])
            if c.get('blob_sha'):
                blob=hashlib.sha1(f'blob {len(b)}\0'.encode()+b).hexdigest()
                if blob!=c['blob_sha']:raise ValueError('El archivo no coincide con el árbol consultado')
            return c,b,None
        except Exception as e:return c,None,str(e)
    peliculas=[]
    for c,b,error in cf.ThreadPoolExecutor(max_workers=4).map(uno,candidatos):
        if error:
            fuentes.append(dict(fuente=c['url'],error=error))
            continue
        id_base=hashlib.sha256(c['url'].encode()).hexdigest()[:12]
        original=OUT/f'descarga_{id_base}'
        original.write_bytes(b)
        if c['nombre'].lower().endswith('.zip'):
            with zipfile.ZipFile(io.BytesIO(b)) as z:
                entries=[(n,z.read(n)) for n in z.namelist() if n.lower().endswith('.fm2')]
        else:entries=[(c['nombre'],b)]
        for n,datos in entries:
            id_='ext_'+hashlib.sha256((c['url']+'#'+n).encode()).hexdigest()[:12]
            archivo=OUT/f'{id_}.zip'
            with zipfile.ZipFile(archivo,'w',zipfile.ZIP_DEFLATED) as z:
                z.writestr(pathlib.Path(n).name,datos)
            peliculas.append(dict(id=id_,title=n,movieFileName=n,gameId=None,gameVersionId=None,
                flags=[],obsoletedById=None,frames=None,archivo_zip=str(archivo),
                url=c.get('pagina') or c['url'],fuente=c['fuente'],sha256=hashlib.sha256(datos).hexdigest(),
                procedencia='Archivo externo: no se presupone publicación ni verificación en consola'))
    (OUT/'fuentes.json').write_text(json.dumps(fuentes,ensure_ascii=False,indent=1)+'\n')
    (OUT/'peliculas.json').write_text(json.dumps(peliculas,ensure_ascii=False,indent=1)+'\n')
    print('Fuentes',len(fuentes),'descargas candidatas',len(candidatos),'películas FM2',len(peliculas),flush=True)
    validar_peliculas.main(peliculas,'validacion_externa.json')


if __name__=='__main__':main()
