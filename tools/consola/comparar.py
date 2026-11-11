"""comparar.py — ¿la escena de la consola es la misma que la de Mesen2?

La consola no da la misma imagen exacta:
  - la paleta del kit RGB no es la de Mesen2;
  - la cadena de vídeo desenfoca y mete ruido;
  - la RAM arranca con valores aleatorios (enemigos, demos, semillas distintas);
  - el fotograma exacto puede ir uno o dos por delante o por detrás.
Por eso no se comparan colores sino **clases de color**: para cada color de la referencia se toma el color
mediano que tienen esos píxeles en la captura (así se aprende la paleta en cada escena). Luego se cuentan los
píxeles que no encajan con el color de su clase, lejos de los bordes entre colores. Además:
  - se prueba con desplazamientos de ±2 píxeles;
  - se escoge el mejor fotograma de una ventana de la grabación alrededor del momento esperado;
  - se mide el parecido de estructura (correlación de luminancia).

Veredictos por escena: ok, parecido (diferencias pequeñas, típicas de la RAM aleatoria), distinto, negra
(la consola da negro y la referencia no), basura (estructura que no se parece a nada de la referencia).
Y por juego, con la secuencia: cuelgue (la imagen se congela mientras la referencia cambia, o el juego deja de
leer el mando).
"""
import numpy as np

UMBRAL_PIXEL = 60        # distancia RGB a la clase para contar un píxel como distinto
OK_FRAC = 0.03           # hasta 3 % de píxeles distintos: ok
PARECIDO_FRAC = 0.12     # hasta 12 %: parecido (aviso)
NEGRA_LUM = 20


def lum(img):
    img = np.asarray(img, np.float32)
    return img[..., 0] * 0.299 + img[..., 1] * 0.587 + img[..., 2] * 0.114


def es_negra(img, mascara=None):
    """Sin contraste y oscura (el negro de la capturadora puede no ser 0)."""
    l = lum(img)
    if mascara is not None:
        l = l[mascara]
    p1, p99 = np.percentile(l, (1, 99))
    return float(p99 - p1) < NEGRA_LUM and float(l.mean()) < 45


def _interior(ref):
    """Píxeles cuyo vecindario 3x3 tiene el mismo color en la referencia (lejos de los bordes)."""
    r = ref.astype(np.int32)
    clave = (r[..., 0] << 16) | (r[..., 1] << 8) | r[..., 2]
    p = np.pad(clave, 1, mode="edge")
    igual = np.ones(clave.shape, bool)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            igual &= p[dy:dy + clave.shape[0], dx:dx + clave.shape[1]] == clave
    return clave, igual


def _corr(la, lb):
    sa, sb = la.std(), lb.std()
    if sa < 1 or sb < 1:
        return 0.0
    return float(((la - la.mean()) * (lb - lb.mean())).mean() / (sa * sb))


def puntuar(cap, ref, mascara=None):
    """{'frac': fracción de píxeles que no encajan con su clase de color, 'corr': correlación de luminancia,
    'dx', 'dy': desplazamiento (±2 píxeles) con mejor correlación}."""
    ref = np.asarray(ref, np.uint8)
    cap = np.asarray(cap, np.float32)
    clave, interior = _interior(ref)
    m = interior & (np.ones(clave.shape, bool) if mascara is None else np.asarray(mascara, bool))
    m[:2], m[-2:], m[:, :2], m[:, -2:] = False, False, False, False
    if m.sum() < 500:
        return {"frac": 1.0, "corr": 0.0, "dx": 0, "dy": 0}
    lr = lum(ref)[m]
    lc_total = lum(cap)
    mejor = None
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            c = _corr(lr, np.roll(np.roll(lc_total, dy, 0), dx, 1)[m])
            if mejor is None or c > mejor[0]:
                mejor = (c, dx, dy)
    corr, dx, dy = mejor
    pix = np.roll(np.roll(cap, dy, 0), dx, 1)[m]
    _, inv = np.unique(clave[m], return_inverse=True)
    orden = np.argsort(inv, kind="stable")
    limites = np.flatnonzero(np.diff(inv[orden])) + 1
    pred = np.empty_like(pix)
    for g in np.split(orden, limites):
        pred[g] = np.median(pix[g], axis=0)
    frac = float((np.linalg.norm(pix - pred, axis=1) > UMBRAL_PIXEL).mean())
    return {"frac": round(frac, 4), "corr": round(corr, 3), "dx": dx, "dy": dy}


def veredicto_escena(cap, ref, mascara=None):
    if es_negra(cap, mascara) and not es_negra(ref, mascara):
        return "negra", {"frac": 1.0, "corr": 0.0}
    p = puntuar(cap, ref, mascara)
    if es_negra(ref, mascara):
        # referencia sin nada (fundido, carga): basta con que la consola tampoco muestre nada
        return ("ok" if es_negra(cap, mascara) or p["frac"] <= OK_FRAC else "distinto"), p
    if p["frac"] <= OK_FRAC:
        return "ok", p
    if p["frac"] <= PARECIDO_FRAC and p["corr"] >= 0.6:
        return "parecido", p
    if p["corr"] < 0.25 and p["frac"] > 0.35:
        return "basura", p
    return "distinto", p


def mejor_de_ventana(cuadros, ref, mascara=None, n_finos=3):
    """De [(t, img)] el que mejor encaja: primero una criba barata (correlación de luminancia a media
    resolución) y la comparación completa solo en los n_finos mejores. -> (veredicto, puntos, índice, t)"""
    if not cuadros:
        return "sin_imagen", {}, None, None
    m = np.ones(np.asarray(ref).shape[:2], bool) if mascara is None else np.asarray(mascara, bool)
    lr = lum(ref)[::2, ::2][m[::2, ::2]]
    criba = sorted(((-_corr(lr, lum(img)[::2, ::2][m[::2, ::2]]), i) for i, (_, img) in enumerate(cuadros)))
    orden = {"ok": 0, "parecido": 1, "distinto": 2, "basura": 3, "negra": 4}
    mejor = None
    for _, i in criba[:n_finos]:
        t, img = cuadros[i]
        v, p = veredicto_escena(img, ref, mascara)
        clave = (orden[v], p["frac"])
        if mejor is None or clave < mejor[0]:
            mejor = (clave, v, p, i, t)
    return mejor[1], mejor[2], mejor[3], mejor[4]


def congelada(cuadros, mascara=None, umbral=2.0):
    """True si todos los cuadros son prácticamente iguales (diferencia media de luminancia < umbral)."""
    if len(cuadros) < 10:
        return False
    a = lum(cuadros[0][1])
    for _, img in cuadros[1:]:
        d = np.abs(lum(img) - a)
        if mascara is not None:
            d = d[mascara]
        if float(d.mean()) > umbral:
            return False
    return True


def resumen(escenas, cuelgue=False):
    """Veredicto del juego a partir de los de sus escenas."""
    vs = [e["veredicto"] for e in escenas]
    if cuelgue:
        return "cuelgue"
    if not vs:
        return "sin_datos"
    for malo in ("negra", "basura"):
        if vs.count(malo) >= max(1, len(vs) // 3):
            return malo
    if all(v == "ok" for v in vs):
        return "ok"
    if all(v in ("ok", "parecido") for v in vs):
        return "parecido"
    if sum(v in ("ok", "parecido") for v in vs) >= len(vs) - 1 and len(vs) >= 3:
        return "parecido"
    return "distinto"
