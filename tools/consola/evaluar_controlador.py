#!/usr/bin/env python3
"""Evalúa la predicción visual a 100 ms con un MP4 256x240 del controlador.

Compara distancias detectadas, no coordenadas de RAM ni etiquetas externas.
Solo usa pares de hueco/pared compatibles con el mismo objetivo visible.
"""
import argparse
import json
import pathlib
import subprocess
import sys

import numpy as np

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from controlador import Marcador, ROOT, SMB


def evaluar(video, segundos=30):
    perfil = SMB(Marcador.cargar(ROOT/'perfiles/smb-digitos.json'))
    cmd = ['ffmpeg','-hide_banner','-loglevel','error','-i',str(video),'-t',str(segundos),
           '-vf','fps=20,scale=256:240','-f','rawvideo','-pix_fmt','rgb24','pipe:1']
    proc = subprocess.Popen(cmd,stdout=subprocess.PIPE)
    rows = []
    try:
        while True:
            raw = proc.stdout.read(256*240*3)
            if not raw:
                break
            if len(raw) != 256*240*3:
                raise RuntimeError('fotograma incompleto')
            rows.append(perfil.ver(np.frombuffer(raw,np.uint8).reshape(240,256,3),len(rows)/20))
        if proc.wait() != 0:
            raise RuntimeError('ffmpeg no pudo decodificar el vídeo')
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait()
        proc.stdout.close()
    base, fixed, pred = [], [], []
    for a,b in zip(rows,rows[2:]):
        if a.mario is None or b.mario is None or a.nivel != b.nivel:
            continue
        for k in ('hueco','pared'):
            d0,d1 = getattr(a,k),getattr(b,k)
            if d0 is not None and d1 is not None and d0>20 and d1>5 and 0<=d0-d1<=25:
                base.append(abs(d0-d1))
                fixed.append(abs(d0-160*.1-d1))
                pred.append(abs(d0-max(0,a.cierre.get(k,a.vx))*.1-d1))
    if not pred:
        raise RuntimeError('no hay pares de obstáculos compatibles en este vídeo')
    return {'video':str(video.resolve()),'fotogramas':len(rows),'horizonte_s':.1,
            'pares_compatibles':len(pred), 'error_posicion_sin_actualizar_px':float(np.mean(base)),
            'error_velocidad_fija_160_px_s':float(np.mean(fixed)),
            'error_prediccion_visual_px':float(np.mean(pred)),
            'limite':'distancias detectadas en pares compatibles; no verdad externa ni prueba de completar un nivel'}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('video',type=pathlib.Path)
    ap.add_argument('--segundos',type=float,default=30)
    ap.add_argument('--salida',type=pathlib.Path)
    args = ap.parse_args()
    if not 0 < args.segundos <= 3600:
        ap.error('usar de 0 a 3600 segundos')
    result = json.dumps(evaluar(args.video,args.segundos),indent=2)
    if args.salida:
        args.salida.write_text(result+'\n')
    print(result)


if __name__ == '__main__':
    main()
