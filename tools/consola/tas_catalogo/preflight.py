"""Reproduce candidatos TAS en Mesen2 nativo; no conecta con la NES ni el Nano."""
import argparse
import concurrent.futures as cf
import json
import pathlib
import sys
import time

HERE=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import referencia
import tas


def reproducir(trabajo):
    rom,pub,desfase=trabajo
    destino=HERE/'referencias'/f"{pub['id']}_{desfase}"
    destino.mkdir(parents=True,exist_ok=True)
    referencia.CASA=destino/'casa'
    _,mandos,_=tas.leer_fm2(pub['archivo_fm2'])
    entrada=destino/'entrada.bin'
    entrada.write_bytes(bytes(mandos))
    fin=len(mandos)+1800
    shots=sorted({len(mandos)//4,len(mandos)//2,3*len(mandos)//4,len(mandos),fin})
    t=time.monotonic()
    try:
        ref=referencia.generar(rom['ruta'],'',shots,fin,destino,entrada=entrada,desfase=desfase)
        r=dict(publicacion=pub['id'],rom=rom['juego'],desfase=desfase,estado='Reproducida; final pendiente de inspección',
               segundos=round(time.monotonic()-t,1),directorio=str(destino),
               fotogramas=fin,capturas=[str(f) for f in sorted(destino.glob('f*.png'))])
    except Exception as e:
        r=dict(publicacion=pub['id'],rom=rom['juego'],desfase=desfase,error=str(e))
    (destino/'preflight.json').write_text(json.dumps(r,ensure_ascii=False,indent=1))
    return r


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--ids',default='2194,6243')
    ap.add_argument('--desfases',default='1')
    ap.add_argument('--jobs',type=int,default=2)
    a=ap.parse_args()
    datos=json.loads((HERE/'validacion_tas.json').read_text())
    pubs={p['id']:p for p in datos['peliculas']}
    ids=[int(n) for n in a.ids.split(',')]
    tareas=[]
    for id_ in ids:
        rom=next(r for r in datos['roms'] if id_ in r['aptas'])
        for desfase in map(int,a.desfases.split(',')):
            tareas.append((rom,pubs[id_],desfase))
    with cf.ProcessPoolExecutor(max_workers=a.jobs) as ex:
        for r in ex.map(reproducir,tareas):print(json.dumps(r,ensure_ascii=False),flush=True)


if __name__=='__main__':main()
