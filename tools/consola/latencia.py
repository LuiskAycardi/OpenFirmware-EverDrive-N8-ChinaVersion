#!/usr/bin/env python3
"""Mide orden USB -> botón visible en la ROM de calibración (pulsación y liberación).

Incluye sondeo de la NES y actualización de la ROM; NO es latencia pura del vídeo.
Guarda las muestras crudas, los intervalos de envío y percentiles en datos/latencia_input.json.
"""
import argparse
import datetime
import json
import pathlib
import random
import sys
import time

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import prueba
from mando import nombres


def resumen(muestras):
    vals = np.array([m['desde_envio_s'] for m in muestras])
    return {k: round(float(np.percentile(vals, q)), 6)
            for k, q in [('p10_s',10), ('mediana_s',50), ('p90_s',90), ('p95_s',95)]}


def medir(b, mask, samples, anterior=0, timeout=1.5):
    esperado = [(mask >> k) & 1 for k in range(8)]
    antes, _ = b.cap.estable(2)
    t0 = time.monotonic()
    # Misma vía T que el controlador. Para soltar, sustituir el pulso por
    # uno de 1 ms del mismo botón; B 0 no cancelaría un T pendiente.
    b.mando.orden(f'T {nombres(mask or anterior)} {250 if mask else 1}')
    ack = time.monotonic()
    fin = ack + timeout
    # La transición podría llegar durante el intercambio USB: conservar el buffer.
    procesado = t0
    while time.monotonic() < fin:
        for t, img in b.cap.ventana(procesado, time.monotonic()):
            if t <= procesado:
                continue
            procesado = t
            if prueba.leer_botones(img) == esperado:
                m = {'mascara':mask, 'envio_t':t0, 'ack_t':ack, 'visible_t':t,
                     'desde_envio_s':t-t0, 'desde_ack_s':t-ack,
                     'envio_duracion_s':ack-t0}
                samples.append(m)
                return m, img
        b.cap.esperar_nuevo(.1)
    raise RuntimeError(f'no se vio la máscara {mask:02x} en {timeout} s')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repeticiones', type=int, default=32, help='número de pulsaciones; también mide cada liberación')
    ap.add_argument('--en-rom', action='store_true', help='la ROM de calibración ya está cargada')
    a = ap.parse_args()
    if not 8 <= a.repeticiones <= 200:
        ap.error('usar de 8 a 200 repeticiones')
    out = ROOT/'informes'/('latencia-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    out.mkdir(parents=True)
    b = prueba.Banco(prueba.cargar_config(None), salida=out)
    samples = []
    try:
        b.cap.iniciar(b.cal)
        if not a.en_rom:
            prueba.lanzar(b, b.cfg['rom_calibracion'], 0, '')
        time.sleep(4)
        b.mando.desarmar()
        b.mando.guion('')
        b.mando.fijar(0)
        time.sleep(.3)
        _, img = b.cap.estable(3)
        esperado, _, mascara = prueba.hacer_rom.imagen_esperada()
        mascara[96:112] = False
        mascara[136:152] = False
        # Verificación de estructura, insensible a la paleta del kit RGB.
        corr = prueba.calibrar.ncc(prueba.calibrar.luminancia(img),
                                   prueba.calibrar.luminancia(esperado), mascara)
        if corr < .8:
            Image.fromarray(img).save(out/'no_calibracion.png')
            raise RuntimeError(f'no es la ROM de calibración (correlación {corr:.3f})')
        if prueba.leer_botones(img) != [0]*8:
            raise RuntimeError('los botones no están sueltos al comenzar')
        b.cap.grabar_clip(out/'video.mp4')
        rng = random.Random(126)
        for i in range(a.repeticiones):
            mask = 1 << (i % 8)
            time.sleep(rng.uniform(.07,.11))
            on, img = medir(b, mask, samples)
            time.sleep(rng.uniform(.07,.11))
            off, _ = medir(b, 0, samples, anterior=mask)
            print(f'{i+1}/{a.repeticiones}: ON {on["desde_envio_s"]*1000:.1f} ms; '
                  f'OFF {off["desde_envio_s"]*1000:.1f} ms', flush=True)
            if i == 0:
                Image.fromarray(img).save(out/'boton-visible.png')
        result = {'tipo':'orden_host_a_indicador_rom', 'fecha':datetime.datetime.now().isoformat(),
                  'protocolo':'T boton 250 / T mismo_boton 1; mismo envío byte a byte que el controlador',
                  'incluye':'USB, sondeo del mando, actualización de la ROM, GBS y capturadora',
                  'n':len(samples), 'todas':resumen(samples),
                  'pulsar':resumen([s for s in samples if s['mascara']]),
                  'soltar':resumen([s for s in samples if not s['mascara']]),
                  'incertidumbre_envio_mediana_s':float(np.median([s['envio_duracion_s'] for s in samples])),
                  'muestras':samples}
        text = json.dumps(result, indent=2)
        (out/'resultado.json').write_text(text)
        # Escribir solamente al terminar todas las muestras con éxito.
        (ROOT/'datos/latencia_input.json').write_text(text)
        print(json.dumps({k:v for k,v in result.items() if k != 'muestras'},indent=2), flush=True)
    finally:
        b.mando.fijar(0)
        b.cap.parar_clip()
        (out/'muestras.json').write_text(json.dumps(samples,indent=2))
        try:
            if not prueba.reset_boton(b):
                print('D2 no devolvió el menú; no enviar navegación', flush=True)
        finally:
            b.cerrar()


if __name__ == '__main__':
    main()
