"""sonido.py — análisis sencillo del audio grabado de la capturadora.

- nivel(): RMS y pico (dBFS) para saber si hay sonido.
- tono_1khz(): la prueba de tono del mapper 250 (1 kHz medio segundo sí y medio no): energía a 1 kHz en
  ventanas de 50 ms frente a la de las frecuencias vecinas, y que se alterne con un periodo de ~1 s.
La música de los chips de expansión (VRC6, 5B, N163) no se puede juzgar sola: se guarda el WAV para escucharlo.
"""
import math
import wave

import numpy as np


def leer_wav(ruta):
    with wave.open(str(ruta), "rb") as w:
        n, canales, ancho, fs = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        d = w.readframes(n)
    if ancho != 2:
        raise ValueError("solo WAV de 16 bits")
    x = np.frombuffer(d, "<i2").astype(np.float32) / 32768
    if canales > 1:
        x = x.reshape(-1, canales).mean(1)
    return x, fs


def nivel(x):
    if len(x) == 0:
        return {"rms_db": -120.0, "pico_db": -120.0}
    rms = float(np.sqrt(np.mean(x * x)))
    pico = float(np.max(np.abs(x)))
    return {"rms_db": round(20 * math.log10(max(rms, 1e-6)), 1), "pico_db": round(20 * math.log10(max(pico, 1e-6)), 1)}


def goertzel(bloque, fs, f):
    k = 2 * math.cos(2 * math.pi * f / fs)
    s1 = s2 = 0.0
    for v in bloque:
        s1, s2 = v + k * s1 - s2, s1
    return s1 * s1 + s2 * s2 - k * s1 * s2


def energia(bloque, fs, f):
    t = np.arange(len(bloque)) / fs
    c = np.dot(bloque, np.cos(2 * np.pi * f * t))
    s = np.dot(bloque, np.sin(2 * np.pi * f * t))
    return float(c * c + s * s)


def tono_1khz(x, fs, f=1000.0, ventana=0.05):
    n = int(fs * ventana)
    on = []
    for i in range(0, len(x) - n, n):
        b = x[i:i + n] * np.hanning(n)
        e = energia(b, fs, f)
        vecinas = (energia(b, fs, f * 0.7) + energia(b, fs, f * 1.4)) / 2
        on.append(e > 20 * vecinas and e > 1e-3 * n)
    on = np.array(on, bool)
    if len(on) < 20:
        return {"tono": False, "fraccion": 0.0, "periodo_s": None}
    frac = float(on.mean())
    # periodo de la alternancia: autocorrelación de la secuencia encendido/apagado
    s = on.astype(np.float32) - on.mean()
    ac = np.correlate(s, s, "full")[len(s) - 1:]
    lags = np.arange(len(ac))
    rango = (lags >= int(0.6 / ventana)) & (lags <= int(1.6 / ventana))
    periodo = float(lags[rango][np.argmax(ac[rango])] * ventana) if rango.any() and ac[0] > 0 else None
    ok = 0.3 <= frac <= 0.7 and periodo is not None and 0.8 <= periodo <= 1.2
    return {"tono": bool(ok), "fraccion": round(frac, 2), "periodo_s": periodo}


def analizar(ruta, buscar_tono=False):
    x, fs = leer_wav(ruta)
    r = {"segundos": round(len(x) / fs, 1), **nivel(x)}
    if buscar_tono:
        r.update(tono_1khz(x, fs))
    return r
