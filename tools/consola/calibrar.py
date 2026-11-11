"""calibrar.py — dónde está la imagen de 256x240 del NES dentro de los 1280x720 de la capturadora.

Se busca la escala y el desplazamiento (x = ox + sx·u, y = oy + sy·v) que mejor llevan una imagen esperada de
256x240 sobre una captura completa:
  1. a lo grueso, con los perfiles de columnas y de filas (correlación 1D para cada escala);
  2. afinando en 2D: correlación normalizada de la captura reducida a 256x240 con la esperada.
La imagen esperada sale de la ROM de calibración (rom/hacer_rom.py: marco, códigos de barras) o de una captura de
Mesen2 de un juego. El GBS-Control puede recortar líneas (sobrebarrido): se anota la zona del NES que se ve y el
resto queda fuera de las comparaciones.

Resultado (calibracion.json): ox, oy, sx, sy, visible = [u0, v0, u1, v1] y el filtro de ffmpeg
"format=rgb24,crop=...,scale=...:flags=area,pad=256:240:...".
"""
import json
import math

import numpy as np

NES_W, NES_H = 256, 240


def luminancia(img):
    img = np.asarray(img, np.float32)
    return img[..., 0] * 0.299 + img[..., 1] * 0.587 + img[..., 2] * 0.114


def integral(lum):
    s = np.zeros((lum.shape[0] + 1, lum.shape[1] + 1), np.float64)
    s[1:, 1:] = lum.cumsum(0).cumsum(1)
    return s


def reducir(s, geo, ancho, alto):
    """Media de la caja de cada píxel del NES (como scale=flags=area). NaN fuera de la captura."""
    ox, oy, sx, sy = geo
    xs = np.round(ox + sx * np.arange(NES_W + 1)).astype(int)
    ys = np.round(oy + sy * np.arange(NES_H + 1)).astype(int)
    fuera_x = (xs[:-1] < 0) | (xs[1:] > ancho) | (xs[1:] <= xs[:-1])
    fuera_y = (ys[:-1] < 0) | (ys[1:] > alto) | (ys[1:] <= ys[:-1])
    xs, ys = np.clip(xs, 0, ancho), np.clip(ys, 0, alto)
    x0, x1 = xs[:-1][None, :], xs[1:][None, :]
    y0, y1 = ys[:-1][:, None], ys[1:][:, None]
    area = np.maximum((x1 - x0) * (y1 - y0), 1)
    r = (s[y1, x1] - s[y0, x1] - s[y1, x0] + s[y0, x0]) / area
    r[fuera_y, :] = np.nan
    r[:, fuera_x] = np.nan
    return r


def ncc(a, b, m):
    m = m & ~np.isnan(a) & ~np.isnan(b)
    if m.sum() < 1000:
        return -1.0
    x, y = a[m] - a[m].mean(), b[m] - b[m].mean()
    d = math.sqrt(float((x * x).sum() * (y * y).sum()))
    return float((x * y).sum() / d) if d else -1.0


def _perfil(cap_perfil, esp_perfil, escalas):
    """Mejor (escala, desplazamiento, puntuación) correlando el perfil esperado escalado con el capturado."""
    c = cap_perfil - cap_perfil.mean()
    mejor = (None, None, -2.0)
    for s in escalas:
        n = int(round(len(esp_perfil) * s))
        t = esp_perfil[np.minimum((np.arange(n) / s).astype(int), len(esp_perfil) - 1)]
        t = t - t.mean()
        nt = np.linalg.norm(t)
        if nt == 0:
            continue
        corr = np.correlate(c, t, "full")          # índice k: desplazamiento k - (n - 1)
        # normalizar por la energía de la captura en la zona solapada
        e = np.concatenate([[0], np.cumsum(c * c)])
        k = np.arange(len(corr))
        ini = np.clip(k - (n - 1), 0, len(c))
        fin = np.clip(k + 1, 0, len(c))
        energia = np.sqrt(np.maximum(e[fin] - e[ini], 1e-6))
        sol = (fin - ini) / n                       # fracción del NES que cae dentro
        punt = corr / (energia * nt) * np.minimum(1.0, sol / 0.85)
        i = int(np.argmax(punt))
        if punt[i] > mejor[2]:
            mejor = (s, float(i - (n - 1)), float(punt[i]))
    return mejor


def estimar(captura, esperada, mascara=None, log=None):
    """captura: HxWx3 (1280x720); esperada: 240x256x3. Devuelve el diccionario de calibración."""
    log = log or (lambda *_: None)
    cap = luminancia(captura)
    esp = luminancia(esperada)
    alto, ancho = cap.shape
    m = np.ones(esp.shape, bool) if mascara is None else np.asarray(mascara, bool)
    esp_rellena = np.where(m, esp, esp[m].mean())
    sx, ox, px = _perfil(cap.mean(0), esp_rellena.mean(0), np.arange(2.0, 5.6, 0.005))
    sy, oy, py = _perfil(cap.mean(1), esp_rellena.mean(1), np.arange(1.8, 3.3, 0.005))
    log(f"perfiles: sx={sx:.3f} ox={ox:.1f} ({px:.2f})  sy={sy:.3f} oy={oy:.1f} ({py:.2f})")
    s = integral(cap)
    geo = [ox, oy, sx, sy]
    mejor = ncc(reducir(s, geo, ancho, alto), esp, m)
    for paso_o, paso_s in ((4, 0.04), (2, 0.02), (1, 0.01), (0.5, 0.005), (0.25, 0.0025)):
        mejora = True
        while mejora:
            mejora = False
            for i, paso in ((0, paso_o), (1, paso_o), (2, paso_s), (3, paso_s)):
                for signo in (-1, 1):
                    g = list(geo)
                    g[i] += signo * paso
                    p = ncc(reducir(s, g, ancho, alto), esp, m)
                    if p > mejor + 1e-5:
                        geo, mejor, mejora = g, p, True
    ox, oy, sx, sy = geo
    u0 = max(0, math.ceil(-ox / sx - 1e-6))
    v0 = max(0, math.ceil(-oy / sy - 1e-6))
    u1 = min(NES_W, math.floor((ancho - ox) / sx + 1e-6))
    v1 = min(NES_H, math.floor((alto - oy) / sy + 1e-6))
    cal = {"ox": round(ox, 3), "oy": round(oy, 3), "sx": round(sx, 5), "sy": round(sy, 5),
           "visible": [u0, v0, u1, v1], "puntuacion": round(mejor, 4), "captura": [ancho, alto]}
    cal["ffmpeg"] = filtro_ffmpeg(cal)
    log(f"calibración: {cal}")
    return cal


def filtro_ffmpeg(cal):
    u0, v0, u1, v1 = cal["visible"]
    x = int(round(cal["ox"] + cal["sx"] * u0))
    y = int(round(cal["oy"] + cal["sy"] * v0))
    w = int(round(cal["sx"] * (u1 - u0)))
    h = int(round(cal["sy"] * (v1 - v0)))
    ancho, alto = cal.get("captura", [1280, 720])
    w, h = min(w, ancho - x), min(h, alto - y)
    return (f"format=rgb24,crop={w}:{h}:{x}:{y},scale={u1 - u0}:{v1 - v0}:flags=area,"
            f"pad={NES_W}:{NES_H}:{u0}:{v0}:black")


def aplicar(captura, cal):
    """Lo mismo que el filtro de ffmpeg (recorte + media por cajas + relleno), en numpy (prueba en seco y
    comprobaciones)."""
    alto, ancho = captura.shape[:2]
    u0, v0, u1, v1 = cal["visible"]
    xs = np.clip(np.round(cal["ox"] + cal["sx"] * np.arange(u0, u1 + 1)).astype(int), 0, ancho)
    ys = np.clip(np.round(cal["oy"] + cal["sy"] * np.arange(v0, v1 + 1)).astype(int), 0, alto)
    out = np.zeros((NES_H, NES_W, 3), np.uint8)
    if len(xs) < 2 or len(ys) < 2:
        return out
    x = captura[ys[0]:ys[-1], xs[0]:xs[-1]].astype(np.float32)
    filas = np.add.reduceat(x, ys[:-1] - ys[0], axis=0)
    cajas = np.add.reduceat(filas, xs[:-1] - xs[0], axis=1)
    area = np.maximum(np.diff(ys), 1)[:, None, None] * np.maximum(np.diff(xs), 1)[None, :, None]
    out[v0:v1, u0:u1] = (cajas / area).clip(0, 255).round().astype(np.uint8)
    return out


def mascara_visible(cal, margen=1):
    u0, v0, u1, v1 = cal["visible"]
    m = np.zeros((NES_H, NES_W), bool)
    m[v0 + margen:v1 - margen, u0 + margen:u1 - margen] = True
    return m


def mapa_color(nes, indices, mascara):
    """Color medio de la captura (ya en 256x240) para cada índice de color NES de la imagen esperada, lejos de
    los bordes. {índice: [r, g, b]}"""
    from numpy.lib.stride_tricks import sliding_window_view
    pad = np.pad(indices, 1, mode="edge")
    v = sliding_window_view(pad, (3, 3))
    uniforme = (v == indices[..., None, None]).all(axis=(-1, -2))
    out = {}
    for i in np.unique(indices):
        sel = (indices == i) & uniforme & mascara
        if sel.sum() >= 20:
            out[int(i)] = [int(round(float(x))) for x in np.median(nes[sel], axis=0)]
    return out


def guardar(cal, ruta):
    with open(ruta, "w") as f:
        json.dump(cal, f, indent=1)


def cargar(ruta):
    with open(ruta) as f:
        cal = json.load(f)
    cal["ffmpeg"] = filtro_ffmpeg(cal)
    return cal


# ---------------------------------------------------------------- calibración provisional con el menú del OS
def _periodo(perfil, lo, hi):
    """Periodo (en píxeles de la captura) del perfil entre lo y hi, con interpolación parabólica."""
    p = perfil - perfil.mean()
    ac = np.correlate(p, p, "full")[len(p) - 1:]
    lags = np.arange(lo, hi + 1)
    i = int(np.argmax(ac[lags]))
    k = lags[i]
    if 0 < i < len(lags) - 1:
        a, b, c = ac[k - 1], ac[k], ac[k + 1]
        den = a - 2 * b + c
        if den:
            return k + 0.5 * (a - c) / den
    return float(k)


def provisional_menu(captura, log=None):
    """Escala y fase de la rejilla de texto del menú (8x8) a partir de una captura completa del menú. El
    desplazamiento absoluto puede ir mal por múltiplos de 8 píxeles del NES: para leer el menú da igual, y la
    calibración buena se hace después con la ROM de calibración."""
    log = log or (lambda *_: None)
    lu = luminancia(captura)
    alto, ancho = lu.shape
    gx = np.abs(np.diff(lu, axis=1))
    gy = np.abs(np.diff(lu, axis=0))
    sy = _periodo(gx.sum(1), 20, 28) / 8           # filas de texto cada 8 líneas del NES
    sx = _periodo(gy.sum(0), 22, 40) / 8           # columnas de letras cada 8 píxeles
    s = integral(lu)

    def vacias(ox, oy, sx, sy):
        r = np.nan_to_num(reducir(s, (ox, oy, sx, sy), ancho, alto))
        sub = r[:(r.shape[0] // 8) * 8, :(r.shape[1] // 8) * 8]
        c = sub.reshape(sub.shape[0] // 8, 8, sub.shape[1] // 8, 8)
        return float(((c.max((1, 3)) - c.min((1, 3))) < 40).mean())

    # fase con la escala de los periodos y, después, escala y fase finas por separado (vertical y horizontal):
    # con la escala algo mal, las filas lejanas se parten y salen menos celdas vacías
    mejor = max((vacias(ox, oy, sx, sy), ox, oy) for oy in np.arange(0, 8 * sy, 1.0)
                for ox in np.arange(0, 8 * sx, 1.0))
    _, fx, fy = mejor
    for _ in range(2):
        mejor = max((vacias(fx, oy, sx, syy), syy, oy) for syy in np.arange(sy - 0.04, sy + 0.041, 0.004)
                    for oy in np.arange(fy - 3, fy + 3.1, 0.5))
        _, sy, fy = mejor
        mejor = max((vacias(ox, fy, sxx, sy), sxx, ox) for sxx in np.arange(sx - 0.04, sx + 0.041, 0.004)
                    for ox in np.arange(fx - 3, fx + 3.1, 0.5))
        _, sx, fx = mejor
    mejor = (mejor[0], fx, fy)
    _, fx, fy = mejor
    cx = (ancho - NES_W * sx) / 2
    cy = (alto - NES_H * sy) / 2
    ox = fx + round((cx - fx) / (8 * sx)) * 8 * sx
    oy = fy + round((cy - fy) / (8 * sy)) * 8 * sy
    u0 = max(0, math.ceil(-ox / sx - 1e-6))
    v0 = max(0, math.ceil(-oy / sy - 1e-6))
    u1 = min(NES_W, math.floor((ancho - ox) / sx + 1e-6))
    v1 = min(NES_H, math.floor((alto - oy) / sy + 1e-6))
    cal = {"ox": round(float(ox), 3), "oy": round(float(oy), 3), "sx": round(float(sx), 5), "sy": round(float(sy), 5),
           "visible": [u0, v0, u1, v1], "provisional": True, "captura": [ancho, alto]}
    cal["ffmpeg"] = filtro_ffmpeg(cal)
    log(f"calibración provisional con el menú: sx={sx:.3f} sy={sy:.3f} ox={ox:.1f} oy={oy:.1f}")
    return cal
