"""Descarga las publicaciones NES asociadas por título/hash a las ROMs seleccionadas."""
import concurrent.futures as cf
import json
import pathlib
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0,str(ROOT/'tools/n8sim'))
import cobertura


def main():
    games=json.loads((HERE/'games.json').read_text())
    pubs=json.loads((HERE/'publications.json').read_text())
    sel=json.loads((ROOT/'tools/n8sim/cobertura/completa/seleccion_juegos.json').read_text())
    titulos={cobertura._norm(j['juego']) for j in sel['seleccion']}
    ids=set()
    for g in games:
        nombres=[g['displayName']]+[(v.get('name') or '') for v in g['versions']]
        nombres += (g.get('aliases') or '').replace(';','\n').splitlines()
        if any(cobertura._norm(n) in titulos for n in nombres):
            ids.add(g['id'])
    # Revisar TODAS las FM2 NES permite encontrar una coincidencia de ROM aunque
    # TASVideos use un título/alias diferente del nombre de nuestra colección.
    candidatos=[p for p in pubs if p['gameId'] in ids or p['movieFileName'].lower().endswith('.fm2')]
    (HERE/'publicaciones_candidatas.json').write_text(json.dumps(candidatos,ensure_ascii=False,indent=1))
    d=HERE/'peliculas'
    d.mkdir(exist_ok=True)
    def descargar(p):
        ruta=d/f"{p['id']}.zip"
        if ruta.exists():return dict(id=p['id'],archivo=str(ruta))
        try:
            req=urllib.request.Request(f"https://tasvideos.org/{p['id']}M?handler=Download",
                                      headers={'User-Agent':'N8-local-TAS-compatibility-audit/1.0'})
            with urllib.request.urlopen(req,timeout=45) as r:datos=r.read()
            ruta.write_bytes(datos)
            return dict(id=p['id'],archivo=str(ruta))
        except Exception as e:return dict(id=p['id'],error=str(e))
    resultados=[]
    with cf.ThreadPoolExecutor(max_workers=4) as ex:
        for i,r in enumerate(ex.map(descargar,candidatos),1):
            resultados.append(r)
            if i%20==0 or r.get('error'):print(i,len(candidatos),r,flush=True)
    (HERE/'descargas.json').write_text(json.dumps(resultados,ensure_ascii=False,indent=1))
    print('Descargadas',sum('archivo' in r for r in resultados),'de',len(resultados),flush=True)


if __name__=='__main__':main()
