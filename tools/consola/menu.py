"""menu.py — leer el menú del OS v13 del N8 en la captura y navegar hasta una ROM.

El OS escribe el texto con teselas de 8x8 alineadas a la rejilla del NES. No conocemos su fuente, así que se
aprende sola:
  - Cada celda de 8x8 con contraste se reduce a su forma (los píxeles del color minoritario: así da igual que
    la fila esté resaltada o invertida) y se agrupa con las formas parecidas (glifos).
  - Cada fila de glifos se compara con los nombres que DEBE haber en la carpeta (sabemos qué hay en la SD:
    ~/SD_Pruebas). Cuentan la posición de los espacios, qué letras se repiten y la correspondencia
    glifo -> letra ya aprendida.
  - Al acertar, cada glifo queda asociado a su letra (fuente.json); con el uso la lectura es cada vez más segura.
La entrada elegida se reconoce de cuatro formas:
  1. una fila de estado (fuera de la lista) que repite el nombre de una entrada;
  2. una flecha o un icono delante del nombre, solo en esa fila;
  3. el modelo aprendido al pulsar Abajo una vez (detectar_cursor);
  4. una fila de la lista con otros colores (la barra del cursor).
Cada paso se comprueba con una captura nueva antes de seguir.
"""
import json
import os
import pathlib
import re
import time
import unicodedata

import numpy as np

COLS, FILAS = 32, 30
CONTRASTE = 40          # diferencia mínima de luminancia en una celda con texto
DIST_GLIFO = 1          # píxeles distintos (de 64) para considerar dos formas el mismo glifo


def lum(img):
    img = np.asarray(img, np.float32)
    return img[..., 0] * 0.299 + img[..., 1] * 0.587 + img[..., 2] * 0.114


# ---------------------------------------------------------------- celdas y glifos
def celdas(img, fase=(0, 0)):
    """Por celda de 8x8: (píxeles por encima del umbral (F, C, 64), hay texto (F, C), color medio de los
    píxeles claros y de los oscuros (F, C, 3), color medio (F, C, 3))."""
    dx, dy = fase
    img = np.asarray(img, np.float32)
    h, w = img.shape[:2]
    nf, nc = (h - dy) // 8, (w - dx) // 8
    sub = img[dy:dy + nf * 8, dx:dx + nc * 8].reshape(nf, 8, nc, 8, 3).transpose(0, 2, 1, 3, 4)
    sub = sub.reshape(nf, nc, 64, 3)
    lu = sub[..., 0] * 0.299 + sub[..., 1] * 0.587 + sub[..., 2] * 0.114
    mx, mn = lu.max(-1), lu.min(-1)
    texto = (mx - mn) >= CONTRASTE
    alto = lu > ((mx + mn) / 2)[..., None]
    wa = alto[..., None].astype(np.float32)
    c_alto = (sub * wa).sum(2) / np.maximum(wa.sum(2), 1)
    c_bajo = (sub * (1 - wa)).sum(2) / np.maximum((1 - wa).sum(2), 1)
    return alto, texto, c_alto, c_bajo, sub.mean(2)


def fase_rejilla(img):
    """Desplazamiento de la rejilla de texto: el que deja más celdas vacías (un glifo partido ocupa hasta 4)."""
    mejor, fase = -1, (0, 0)
    for dy in range(8):
        for dx in range(8):
            _, texto, _, _, _ = celdas(img, (dx, dy))
            vacias = (~texto).sum() * 1.0 / texto.size
            if vacias > mejor + 1e-9:
                mejor, fase = vacias, (dx, dy)
    return fase


class Fuente:
    """Glifos aprendidos: formas prototipo (64 bits) y, cuando se sabe, su letra."""

    def __init__(self, ruta=None):
        self.ruta = pathlib.Path(ruta) if ruta else None
        self.formas = []           # np.bool_ (64,)
        self.letra = {}            # id -> carácter
        self.votos = {}            # id -> {carácter: n}
        if self.ruta and self.ruta.exists():
            d = json.loads(self.ruta.read_text())
            for h in d.get("formas", []):
                self.formas.append(np.array([int(c) for c in bin(int(h, 16))[2:].zfill(64)], bool))
            self.letra = {int(k): v for k, v in d.get("letra", {}).items()}
            self.votos = {int(k): v for k, v in d.get("votos", {}).items()}

    def guardar(self):
        if not self.ruta:
            return
        d = {"formas": [format(int("".join("1" if b else "0" for b in f), 2), "016x") for f in self.formas],
             "letra": {str(k): v for k, v in self.letra.items()},
             "votos": {str(k): v for k, v in self.votos.items()}}
        self.ruta.write_text(json.dumps(d, ensure_ascii=False, indent=0))

    def ident(self, forma):
        if self.formas:
            if getattr(self, "_m", None) is None or len(self._m) != len(self.formas):
                self._m = np.array(self.formas)
            d = (self._m != forma).sum(1)
            i = int(np.argmin(d))
            if d[i] <= DIST_GLIFO:
                return i
        self.formas.append(forma.copy())
        self._m = None
        return len(self.formas) - 1

    def aprender(self, gid, c):
        v = self.votos.setdefault(gid, {})
        v[c] = v.get(c, 0) + 1
        self.letra[gid] = max(v, key=v.get)

    def texto(self, ids):
        return "".join(" " if g is None else self.letra.get(g, "?") for g in ids)


# ---------------------------------------------------------------- filas
class Fila:
    def __init__(self, y, ids, fg, bg, ini, fin):
        self.y, self.ids, self.fg, self.bg, self.ini, self.fin = y, ids, fg, bg, ini, fin

    def __repr__(self):
        return f"Fila({self.y}, col {self.ini}-{self.fin})"


def leer(img, fuente, fase=(0, 0)):
    """Segmentos de texto de la pantalla (separados por 2 o más celdas vacías). La polaridad (texto claro sobre
    oscuro o al revés) se decide por segmento, así una letra gruesa no sale invertida y una fila resaltada o
    invertida da las mismas formas."""
    alto, texto, c_alto, c_bajo, media = celdas(img, fase)
    filas = []
    for y in range(texto.shape[0]):
        cols = np.nonzero(texto[y])[0]
        if not len(cols):
            continue
        grupos, actual = [], [cols[0]]
        for c in cols[1:]:
            if c - actual[-1] > 2:
                grupos.append(actual)
                actual = [c]
            else:
                actual.append(c)
        grupos.append(actual)
        for g in grupos:
            ini, fin = int(g[0]), int(g[-1])
            sel = [c for c in range(ini, fin + 1) if texto[y, c]]
            claro = sum(1 for c in sel if alto[y, c].sum() <= 32) * 2 >= len(sel)
            ids = []
            for c in range(ini, fin + 1):
                if texto[y, c]:
                    ids.append(fuente.ident(alto[y, c] if claro else ~alto[y, c]))
                else:
                    ids.append(None)
            fg = (c_alto if claro else c_bajo)[y, sel].mean(0)
            fondos = [(c_bajo if claro else c_alto)[y, c] for c in sel]
            fondos += [media[y, c] for c in range(ini, fin + 1) if not texto[y, c]]
            filas.append(Fila(y, ids, fg, np.mean(fondos, axis=0), ini, fin))
    return filas


# ---------------------------------------------------------------- comparar una fila con un nombre
def normalizar(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "replace").decode()
    return s


def puntuar(fila, nombre, fuente, tentativa=None, ancho=COLS):
    """(puntuación, salto): > 0 si la fila puede mostrar 'nombre' (quizá recortado por la derecha o con 1-2
    iconos delante, 'salto'). Cuentan los espacios en su sitio, que una forma sea siempre la misma letra y las
    letras ya aprendidas."""
    tentativa = tentativa or {}
    mejor = (-1e9, 0)
    s0 = normalizar(nombre)
    for salto in (0, 1, 2):
        ids = fila.ids[salto:]
        n = len(ids)
        if n < 2 or len(s0) < n or (len(s0) > n and fila.fin < ancho - 4):
            continue
        s = s0[:n]
        g2c, c2g = {}, {}
        p = 0.0
        ok = True
        for g, c in zip(ids, s):
            if c == " ":
                if g is not None:
                    ok = False
                    break
                continue
            if g is None:
                if c.isalnum():
                    ok = False
                    break
                p -= 0.5                        # signo que el OS quizá no dibuja (p. ej. '_')
                continue
            if c == "?":                        # carácter fuera de ASCII: cualquier forma
                continue
            conocida = fuente.letra.get(g, tentativa.get(g))
            if conocida is not None:
                if conocida == c:
                    p += 2
                elif conocida.lower() == c.lower():
                    p += 0.5
                else:
                    p -= 3
            if g in g2c and g2c[g] != c:
                ok = False
                break
            if c in c2g and c2g[c] != g:
                p -= 0.2                        # la misma letra con dos formas (ruido): se tolera
            g2c[g] = c
            c2g.setdefault(c, g)
            p += 0.3
        if ok and p - salto * 0.5 > mejor[0]:
            mejor = (p - salto * 0.5, salto)
    return mejor


def alinear(fila, nombre, salto):
    s = normalizar(nombre)
    return [(g, c) for g, c in zip(fila.ids[salto:], s) if g is not None and c not in " ?"]


def mismo_texto(a, b):
    """Misma fila de texto (la barra de estado repite el nombre): mismas formas en el 85 % de las posiciones."""
    if len(a.ids) != len(b.ids):
        return False
    return sum(x == y for x, y in zip(a.ids, b.ids)) >= 0.85 * len(a.ids)


def candidatos(filas, nombres, fuente, umbral, penal=None):
    penal = penal or {}
    cand = {}
    for i, f in enumerate(filas):
        for n in nombres:
            if puntuar(f, n, fuente)[0] - penal.get(n, 0) >= umbral:
                cand.setdefault(i, []).append(n)
    return cand


def identificar(filas, nombres, fuente, umbral=1.15, cand=None, penal=None):
    """({índice de fila: nombre}, {índice: salto}). Primero las filas que solo encajan con un nombre: fijan
    letras que deciden las dudosas (Super Mario Bros. 2 y 3 solo se distinguen por un glifo). Un nombre puede
    salir en una segunda fila solo si es idéntica (la barra de estado)."""
    penal = penal or {}
    cand = candidatos(filas, nombres, fuente, umbral, penal) if cand is None else cand
    asign, salto_de, usos, tentativa = {}, {}, {}, {}
    while True:
        mejor = None
        for i, ns in cand.items():
            if i in asign:
                continue
            opciones = []
            for n in ns:
                if n in usos and (len(usos[n]) >= 2 or not mismo_texto(filas[i], filas[usos[n][0]])):
                    continue
                p, sal = puntuar(filas[i], n, fuente, tentativa)
                p -= penal.get(n, 0)
                if p >= umbral:
                    opciones.append((p, n, sal))
            if not opciones:
                continue
            opciones.sort(reverse=True)
            unica = len(opciones) == 1 or opciones[0][0] - opciones[1][0] >= 1.5
            clave = (unica, opciones[0][0])
            if mejor is None or clave > mejor[0]:
                mejor = (clave, i, opciones[0][1], opciones[0][2])
        if mejor is None:
            break
        _, i, n, sal = mejor
        asign[i], salto_de[i] = n, sal
        usos.setdefault(n, []).append(i)
        for g, c in alinear(filas[i], n, sal):
            tentativa.setdefault(g, c)
    return asign, salto_de


def aprender(filas, asign, salto_de, fuente):
    for i, n in asign.items():
        for g, c in alinear(filas[i], n, salto_de[i]):
            fuente.aprender(g, c)


# ---------------------------------------------------------------- carpetas de la SD
def entradas(carpeta):
    """Nombres que el OS puede mostrar en una carpeta de la copia de la SD, en el orden más probable
    (carpetas primero y por nombre sin distinguir mayúsculas). Se descartan los ocultos y los ._ de macOS."""
    p = pathlib.Path(carpeta)
    ds, fs = [], []
    for e in sorted(os.listdir(p), key=str.lower):
        if e.startswith(".") or e.startswith("._"):
            continue
        (ds if (p / e).is_dir() else fs).append(e)
    return ds + fs


def variantes(nombre, es_carpeta):
    """[(forma en que el OS podría escribir el nombre, penalización)]. Las decoradas pierden ante el nombre tal
    cual con una flecha delante."""
    v = [(nombre, 0.0)]
    base, ext = os.path.splitext(nombre)
    if ext and not es_carpeta:
        v.append((base, 0.2))
    if es_carpeta:
        v += [(f"[{nombre}]", 1.0), (f"/{nombre}", 1.0), (f"<{nombre}>", 1.0)]
    return v


# ---------------------------------------------------------------- estado de la pantalla
class Lectura:
    def __init__(self, filas, carpeta, asign, puntos, seleccion, orden, por_fila):
        self.filas, self.carpeta, self.asign, self.puntos = filas, carpeta, asign, puntos
        self.seleccion, self.orden, self.por_fila = seleccion, orden, por_fila

    def __repr__(self):
        return f"Lectura({self.carpeta!r}, {len(self.asign)} filas, elegida={self.seleccion!r})"


class Menu:
    def __init__(self, raiz_sd, fuente, cursor=None, teclas=None, log=None):
        self.raiz = pathlib.Path(raiz_sd)
        self.fuente = fuente
        self.cursor = cursor          # modelo aprendido: {"sel": {...}, "nosel": {...}}
        self.teclas = {"abajo": "down", "arriba": "up", "entrar": "a", "volver": "b", "lanzar": ["a"],
                       "pulso_ms": 60, "pausa_ms": 120, **(teclas or {})}
        self.log = log or (lambda *_: None)
        self.fase = (0, 0)
        self._carpetas = None

    # ------------------------------------------------------------ carpetas conocidas
    def carpetas(self):
        """{ruta relativa ('' = raíz): [(nombre visible, nombre real, penalización)]}"""
        if self._carpetas is None:
            c = {}
            for rel in [""] + [str(p.relative_to(self.raiz)) for p in sorted(self.raiz.rglob("*"))
                               if p.is_dir() and not p.name.startswith(".")]:
                d = self.raiz / rel
                lst = []
                for e in entradas(d):
                    for v, pen in variantes(e, (d / e).is_dir()):
                        lst.append((v, e, pen))
                if rel:
                    lst.append(("..", "..", 0.0))
                c[rel] = lst
            self._carpetas = c
        return self._carpetas

    # ------------------------------------------------------------ lectura
    def leer(self, img, solo=None):
        filas = leer(img, self.fuente, self.fase)
        # a lo rápido, cuántas filas encajan con cada carpeta; la identificación completa, en las dos mejores
        previas = []
        for rel, lst in self.carpetas().items():
            if solo is not None and rel not in solo:
                continue
            vis = list(dict.fromkeys(v for v, _, _ in lst))
            penal = {v: p for v, _, p in lst}
            cand = candidatos(filas, vis, self.fuente, 1.15, penal)
            previas.append((len(cand), rel, vis, cand, penal))
        previas.sort(key=lambda x: -x[0])
        mejor, segundo = None, 0
        for _, rel, vis, cand, penal in previas[:2]:
            asign, saltos = identificar(filas, vis, self.fuente, cand=cand, penal=penal)
            lst = self.carpetas()[rel]
            reales = {i: next(r for vv, r, _ in lst if vv == v) for i, v in asign.items()}
            puntos = len(set(reales.values()))
            if mejor is None or puntos > mejor[2]:
                segundo = mejor[2] if mejor else 0
                mejor = (rel, reales, puntos, asign, saltos)
            elif puntos > segundo:
                segundo = puntos
        if not mejor or mejor[2] == 0:
            return Lectura(filas, None, {}, 0, None, [], {})
        rel, reales, puntos, asign, saltos = mejor
        if puntos >= 2 and puntos >= segundo + 1:          # solo se aprende si la carpeta está clara
            aprender(filas, asign, saltos, self.fuente)
        por_nombre = {}
        for i, r in reales.items():
            por_nombre.setdefault(r, []).append(i)
        lista = {r: min(ix, key=lambda i: filas[i].y) for r, ix in por_nombre.items()}
        orden = sorted(lista, key=lambda r: filas[lista[r]].y)
        fondo = np.median(np.asarray(img, np.float32).reshape(-1, 3), axis=0)
        unicas = {r for _, r, _ in self.carpetas()[rel] if r != ".."}
        if len(unicas) == 1 and len(lista) == 1:
            sel = next(iter(lista))                       # carpeta de una sola entrada
        else:
            sel = self._seleccion(filas, reales, por_nombre, lista, saltos, fondo)
        return Lectura(filas, rel, reales, puntos, sel, orden, lista)

    def _rasgos(self, f):
        return np.concatenate([f.fg, f.bg])

    def _seleccion(self, filas, reales, por_nombre, lista, saltos=None, fondo=None):
        # 1. barra de estado: un nombre que sale dos veces; la segunda fila, lejos de la lista
        for r, ix in por_nombre.items():
            if len(ix) == 2:
                a, b = sorted(ix, key=lambda i: filas[i].y)
                if filas[b].y - filas[a].y >= 2:
                    return r
        if not lista:
            return None
        # 2. una flecha o icono delante del nombre solo en una fila
        if saltos and len(lista) >= 2:
            con = [r for r, i in lista.items() if saltos.get(i, 0) > 0]
            if len(con) == 1:
                return con[0]
        rs = {r: self._rasgos(filas[i]) for r, i in lista.items()}
        # 3. modelo aprendido
        if self.cursor:
            sel = np.array(self.cursor["sel"])
            nosel = np.array(self.cursor["nosel"])
            dist = {r: np.linalg.norm(v - sel) - np.linalg.norm(v - nosel) for r, v in rs.items()}
            r = min(dist, key=dist.get)
            if dist[r] < -20:
                return r
        # 4. la barra del cursor: la única fila con un fondo distinto al de la pantalla
        if fondo is not None:
            d = {r: float(np.linalg.norm(filas[i].bg - fondo)) for r, i in lista.items()}
            orden_d = sorted(d.values(), reverse=True)
            if orden_d[0] > 50 and (len(orden_d) == 1 or orden_d[0] > 3 * orden_d[1] + 5):
                return max(d, key=d.get)
        # 5. el único texto de otro color (si todas las demás entradas se ven igual)
        if len(rs) >= 3:
            fg = {r: filas[i].fg for r, i in lista.items()}
            for r in fg:
                otras = [v for k, v in fg.items() if k != r]
                med = np.median(np.array(otras), axis=0)
                if np.linalg.norm(fg[r] - med) > 60 and max(np.linalg.norm(v - med) for v in otras) < 20:
                    return r
        return None

    # ------------------------------------------------------------ acciones
    def _tocar(self, mando, boton):
        mando.tocar(boton, self.teclas["pulso_ms"], self.teclas["pausa_ms"])

    def ver(self, captura, solo=None, intentos=3):
        """Lee la pantalla con fotogramas nuevos (deja pasar la animación del cursor)."""
        lec = None
        for _ in range(intentos):
            t, img = captura.estable(3)
            if img is None:
                continue
            lec = self.leer(img, solo)
            if lec.carpeta is not None and lec.seleccion is not None:
                return lec, img
        return lec, img

    def detectar_cursor(self, mando, captura):
        """Pulsa Abajo y Arriba y aprende cómo se ve la fila elegida (cambio de colores)."""
        a, _ = self.ver(captura)
        if not a or a.carpeta is None or len(a.orden) < 2:
            return False
        self._tocar(mando, self.teclas["abajo"])
        b, _ = self.ver(captura, solo=[a.carpeta])
        self._tocar(mando, self.teclas["arriba"])
        if not b:
            return False
        cambios = []
        for r in set(a.por_fila) & set(b.por_fila):
            fa, fb = a.filas[a.por_fila[r]], b.filas[b.por_fila[r]]
            if fa.y == fb.y:
                d = np.linalg.norm(self._rasgos(fa) - self._rasgos(fb))
                if d > 25:
                    cambios.append((r, fa, fb))
        if len(cambios) != 2:
            self.log(f"cursor: no se ve un cambio claro ({len(cambios)} filas cambian)")
            return False
        (r1, a1, b1), (r2, a2, b2) = sorted(cambios, key=lambda c: c[1].y)
        # bajando, la fila de arriba deja de estar elegida y la de abajo pasa a estarlo
        self.cursor = {"sel": self._rasgos(a1).tolist(), "nosel": self._rasgos(b1).tolist()}
        self.log(f"cursor aprendido: elegida {np.round(self.cursor['sel']).tolist()}")
        return True

    def ir_a_carpeta(self, mando, captura, destino, max_pasos=40):
        """Navega hasta la carpeta 'destino' (ruta relativa a la raíz de la SD)."""
        for _ in range(max_pasos):
            lec, _ = self.ver(captura)
            if lec is None or lec.carpeta is None:
                raise ErrorMenu("no reconozco el menú del N8 en la pantalla")
            if lec.carpeta == destino:
                return lec
            actual = lec.carpeta
            if destino.startswith(actual + "/") or (actual == "" and destino):
                siguiente = destino[len(actual):].lstrip("/").split("/")[0]
                self.elegir(mando, captura, siguiente, lec)
                self._tocar(mando, self.teclas["entrar"])
            else:
                self._tocar(mando, self.teclas["volver"])
            time.sleep(0.3)
        raise ErrorMenu(f"no llego a la carpeta {destino!r}")

    def elegir(self, mando, captura, nombre, lec=None, max_pasos=80):
        """Mueve el cursor hasta 'nombre' en la carpeta actual."""
        carpeta = lec.carpeta if lec else None
        todos = [r for _, r, _ in self.carpetas()[carpeta]] if carpeta is not None else []
        esperado = list(dict.fromkeys(todos))
        pasos = 0
        while pasos < max_pasos:
            if lec is None or lec.carpeta is None:
                lec, _ = self.ver(captura, solo=[carpeta] if carpeta is not None else None)
                if lec is None or lec.carpeta is None:
                    raise ErrorMenu("perdí el menú")
                carpeta = lec.carpeta
                esperado = list(dict.fromkeys(r for _, r, _ in self.carpetas()[carpeta]))
            if lec.seleccion == nombre:
                return lec
            if lec.seleccion is None:
                if self.cursor is None and self.detectar_cursor(mando, captura):
                    lec = None
                    continue
                raise ErrorMenu("no sé qué entrada está elegida")
            orden = self._orden(lec, esperado)
            if nombre not in orden:
                raise ErrorMenu(f"{nombre!r} no está en la carpeta {carpeta!r}")
            delta = orden.index(nombre) - orden.index(lec.seleccion)
            n = min(abs(delta), 8)
            for _ in range(n):
                self._tocar(mando, self.teclas["abajo"] if delta > 0 else self.teclas["arriba"])
            pasos += max(n, 1)
            lec = None
        raise ErrorMenu(f"no consigo elegir {nombre!r}")

    def _orden(self, lec, esperado):
        """Orden de la lista: el visto en pantalla para lo visible; lo demás, el esperado alrededor."""
        visto = lec.orden
        if not visto:
            return esperado
        resto = [e for e in esperado if e not in visto]
        primero = esperado.index(visto[0]) if visto[0] in esperado else 0
        antes = [e for e in resto if esperado.index(e) < primero]
        despues = [e for e in resto if esperado.index(e) >= primero]
        return antes + visto + despues

    def lanzar(self, mando, captura, rom_rel):
        """Desde cualquier carpeta: ir a la de la ROM, elegirla y pulsar A. rom_rel relativo a la raíz de la SD."""
        carpeta, nombre = os.path.split(rom_rel)
        lec = self.ir_a_carpeta(mando, captura, carpeta)
        self.elegir(mando, captura, nombre, lec)
        for b in self.teclas["lanzar"]:
            self._tocar(mando, b)

    def es_menu(self, img):
        lec = self.leer(img)
        return lec.carpeta is not None and lec.puntos >= 2, lec

    def describir(self, lec):
        """Texto leído (para el informe cuando algo falla)."""
        return "\n".join(f"{f.y:2d} {' ' * f.ini}{self.fuente.texto(f.ids)}" for f in lec.filas)


class ErrorMenu(Exception):
    pass


def ordenar_natural(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]
