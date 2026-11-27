#!/usr/bin/env python3
"""medir.py — mide en una grabación de la consola la proporción entre el chip de sonido y el APU (GPL-3.0-or-later).

  python3 -I tools/calibracion/medir.py CHIP GRABACION.wav [--paso N]
  python3 -I tools/calibracion/medir.py CHIP --grabar SEGUNDOS GRABACION.wav [--dispositivo hw:3,0] [--paso N]

CHIP: FDS, VRC6, 5B, N163, VRC7, MMC5 o PCM. La consola tiene que estar corriendo la ROM de calibración del chip (cal.s):
1 s de pulso del APU, 0,5 s de silencio, 2 s del chip y 0,5 s de silencio, en bucle, todo a ~440 Hz.

Se separan los tramos por energía (ventanas de 10 ms) y se reconocen por su duración; en cada uno se mide la amplitud
de la componente de ~440 Hz (FFT con ventana de Hann sobre el 60 % central del tramo). Los filtros analógicos de la
consola, del GBS-Control y de la capturadora afectan igual a las dos notas, porque tienen la misma frecuencia.

Referencia (Mesen2, NesSoundMixer::GetOutputVolume): pulso del APU a volumen 15 = 95,88 x 5000 / (8128/15 + 100)
= 746,6 unidades; cada chip, su nivel por su peso (docs/sonido-volumen.md). Para ondas cuadradas del 50 % la
fundamental es 4/pi x (pico a pico / 2); el VRC7 da un seno (amplitud medida en Mesen2 con N8_AUDIO).

PCM (CAL PCM.nes) es otra medida: el tramo de 1 s es una cuadrada en el DMC del APU ($4011) y el de 2 s, la misma en
el PCM del MMC5 ($5011), las dos entre los niveles 1 y 65. Da la proporción PCM / DMC medida, la de Mesen2
(NesSoundMixer: DMC no lineal, 159,79 / (100 + 22638 / n), y el PCM sumado a los pulsos con el mismo peso) y la de
NESdev («equivalent in volume to the APU with equivalent input»: 1), y el peso del PCM frente a los pulsos que haría
falta en hdl/rtl/snd_mmc5.v para que salga 1.

Salida: la proporción medida, la de Mesen2, la corrección (Mesen2 / medida) y la ganancia base que habría que poner
en hdl/tools/gen_ganancia.py, teniendo en cuenta el paso de volumen con el que se grabó (--paso, -4..+4; 0 por
defecto).
"""
import argparse
import math
import pathlib
import subprocess
import sys
import wave

import numpy as np

APU = 95.88 * 5000 / (8128 / 15 + 100)                  # pulso 1 a volumen 15
FUND_CUAD = 4 / math.pi / 2                             # fundamental de una cuadrada del 50 % por unidad de pico a pico
# chip: (pico a pico en Mesen2, forma, nivel pico a pico en el DAC con la ganancia de hoy (paso 0), ganancia base hoy, hdl/tools/gen_ganancia.py)
VRC7_AMP = None                                         # amplitud del seno en unidades de Mesen2 (ver vrc7_amp)
CHIPS = {
    'VRC6': (15 * 75, 'cuadrada', 15 * 8, 339),
    '5B':   (177 * 15, 'cuadrada', 177, 537),
    'N163': (225 * 20, 'cuadrada', 450, 341),
    'MMC5': (15 * 43, 'cuadrada', 30, 760),
    'FDS':  (63 * 20, 'cuadrada', 63 * 16, 43),
    'VRC7': (None, 'seno', None, 547),
    'PCM':  (64 * 43, 'cuadrada', 66, None),
}
PCM_PESO = 33 / 64                                      # peso del PCM frente a un paso de pulso en snd_mmc5.v hoy (pcm + pcm>>5 contra 2 por paso)


def dmc(n):
    """Salida del DMC en unidades de Mesen2 (NesSoundMixer, sin triángulo ni ruido)."""
    return 0.0 if n == 0 else 5000 * 159.79 / (100 + 22638 / n)


def leer_wav(ruta):
    with wave.open(str(ruta), 'rb') as w:
        n, canales, ancho, fs = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        datos = np.frombuffer(w.readframes(n), dtype={2: np.int16, 4: np.int32}[ancho])
    x = datos.reshape(-1, canales).astype(np.float64).mean(axis=1)
    return x / (2 ** (8 * ancho - 1)), fs


def tramos(x, fs):
    """[(inicio, fin)] de los tramos con sonido (ventanas de 10 ms por encima de un umbral)."""
    v = int(fs * 0.01)
    n = len(x) // v
    e = np.sqrt((x[:n * v].reshape(n, v) - x[:n * v].reshape(n, v).mean(axis=1, keepdims=True)) ** 2).mean(axis=1)
    piso = np.percentile(e, 10)
    techo = np.percentile(e, 99)
    umbral = piso + 0.1 * (techo - piso)
    activo = e > umbral
    out, i = [], 0
    while i < n:
        if activo[i]:
            j = i
            while j < n and (activo[j] or (j + 5 < n and activo[j:j + 5].any())):
                j += 1
            out.append((i * v, j * v))
            i = j
        else:
            i += 1
    return out


def amplitud(seg, fs):
    # fundamental por correlación con un seno y un coseno a la frecuencia del pico (más simple y exacto que la banda)
    s = seg - seg.mean()
    w = np.hanning(len(s))
    spec = np.abs(np.fft.rfft(s * w))
    f = np.fft.rfftfreq(len(s), 1 / fs)
    banda = (f > 400) & (f < 480)
    fp = f[banda][np.argmax(spec[banda])]
    # afinar la frecuencia con un barrido fino alrededor del pico
    t = np.arange(len(s)) / fs
    mejor = 0.0
    for df in np.linspace(-2, 2, 81):
        c = np.exp(-2j * np.pi * (fp + df) * t)
        a = abs((s * w * c).sum()) * 2 / w.sum()
        mejor = max(mejor, a)
    return mejor


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('chip', choices=CHIPS)
    ap.add_argument('wav')
    ap.add_argument('--grabar', type=float, help='grabar estos segundos antes de medir')
    ap.add_argument('--dispositivo', default='hw:3,0')
    ap.add_argument('--paso', type=int, default=0, help='paso de volumen del OS con el que se grabó (-4..+4)')
    ap.add_argument('--vrc7-amp', type=float, help='amplitud del seno del VRC7 en unidades de Mesen2')
    a = ap.parse_args()
    if a.grabar:
        subprocess.run(['arecord', '-q', '-D', a.dispositivo, '-f', 'S16_LE', '-r', '48000', '-c', '2', '-d',
                        str(int(math.ceil(a.grabar))), a.wav], check=True)
    x, fs = leer_wav(a.wav)
    pico = np.abs(x).max()
    tr = tramos(x, fs)
    apu, chip = [], []
    cortados = 0
    for i0, i1 in tr:
        dur = (i1 - i0) / fs
        if i0 < fs * 0.02 or i1 > len(x) - fs * 0.02:    # cortado por el principio o el final de la grabación: su
            cortados += 1                                 # duración no dice qué es (un trozo de 2 s puede durar 1)
            continue
        m = int((i1 - i0) * 0.2)
        seg = x[i0 + m:i1 - m]
        if 0.7 < dur < 1.3:
            apu.append(amplitud(seg, fs))
        elif 1.6 < dur < 2.4:
            chip.append(amplitud(seg, fs))
    print(f'{a.wav}: {len(x) / fs:.1f} s a {fs} Hz, pico {pico:.3f} de la escala; tramos: {len(apu)} del APU, '
          f'{len(chip)} del chip ({len(tr)} en total, {cortados} cortados por los bordes)')
    if pico > 0.98:
        print('AVISO: la grabación satura; baja el volumen de entrada o el paso del OS')
    if not apu or not chip:
        sys.exit('no encuentro tramos de 1 s (APU) y de 2 s (chip): ¿está corriendo la ROM de calibración?')
    fa, fc = float(np.median(apu)), float(np.median(chip))
    medida = fc / fa
    pp, forma, nivel, base = CHIPS[a.chip]
    if a.chip == 'PCM':
        ref = pp / (dmc(65) - dmc(1))
        print(f'  DMC {fa:.5f} (dispersión {np.std(apu) / fa * 100:.1f} %), PCM {fc:.5f} '
              f'(dispersión {np.std(chip) / fc * 100:.1f} %)')
        print(f'  PCM / DMC: medido {medida:.3f}, Mesen2 {ref:.3f}, NESdev 1')
        print(f'  peso del PCM frente a un paso de pulso: hoy {PCM_PESO:.3f}, para que salga 1: {PCM_PESO / medida:.3f}')
        return
    f_apu = APU * FUND_CUAD
    if forma == 'seno':
        if not a.vrc7_amp:
            sys.exit('VRC7: hace falta --vrc7-amp (amplitud del seno en Mesen2)')
        f_chip = a.vrc7_amp
    else:
        f_chip = pp * FUND_CUAD
    ref = f_chip / f_apu
    paso = 2 ** (a.paso / 2)
    corr = ref / (medida / paso)
    print(f'  APU {fa:.5f} (dispersión {np.std(apu) / fa * 100:.1f} %), chip {fc:.5f} '
          f'(dispersión {np.std(chip) / fc * 100:.1f} %)')
    print(f'  chip / APU: medido {medida:.3f} (paso {a.paso:+d}), Mesen2 {ref:.3f}; corrección x{corr:.3f}')
    print(f'  ganancia base: hoy {base}, calibrada {round(base * corr)}')


if __name__ == '__main__':
    main()
