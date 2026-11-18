"""banco.py — el modo banco del OS propio del N8 (os/src/banco.s), visto desde el PC.

Con EDFC/BANCO.TXT en la SD, el OS no enseña el menú: enseña una pantalla con una entrada de la lista y su número
en dos filas de bloques (filas 16 y 17, columnas 2-19: bloque de marca, 16 bits del número del más alto al más bajo
y bloque de marca; la fila 17 es el complemento). Start lanza la entrada; derecha/izquierda pasan a la siguiente o
la anterior; tras el juego, el botón RESET vuelve a la pantalla con la siguiente. Así prueba.py no navega por el
menú: escribe la lista, comprueba el número en la captura y pulsa Start.
"""
import json
import pathlib

import numpy as np

LISTA = "EDFC/BANCO.TXT"
FILA_A, FILA_B, COL0 = 16, 17, 2
UMBRAL = 90                 # luminancia de un bloque (blanco del OS: ~200; fondo negro: ~10)


def lineas(texto):
    """Las entradas de una BANCO.TXT, con las mismas reglas que el OS: sin líneas vacías, ni las que empiezan por #
    (comentarios) o por ! (directivas)."""
    return [l.rstrip("\r") for l in texto.split("\n") if l.rstrip("\r") and l[0] not in "#!"]


def ram_de_mesen(estado):
    """El byte con que Mesen2 llena la RAM al encender (RamPowerOnState), para la directiva !ram=: así los juegos con
    pila arrancan en la consola igual que en la referencia, sin su partida. None o "AllZeros" -> 0; "AllOnes" -> $FF."""
    return 0xFF if estado == "AllOnes" else 0x00


def escribir(raiz_sd, rutas, comentario="lista de prueba.py", ram=0x00):
    """Escribe EDFC/BANCO.TXT en la SD (o en una copia). Con ram (0-255), la directiva !ram=XX: antes de cada
    lanzamiento, la PRG-RAM de las partidas a ese valor y los juegos con pila sin su partida (no se carga ni se
    guarda: las pruebas no tocan las partidas de verdad). ram=None: con las partidas. Devuelve la ruta del archivo."""
    for r in rutas:
        if "\n" in r or r.startswith(("#", "!")) or not r:
            raise ValueError(f"ruta que el OS no puede leer en BANCO.TXT: {r!r}")
        if len(r.encode()) > 255:
            raise ValueError(f"ruta de más de 255 bytes (el OS la corta): {r!r}")
    p = pathlib.Path(raiz_sd) / LISTA
    p.parent.mkdir(parents=True, exist_ok=True)
    directiva = f"!ram={ram:02X}\n" if ram is not None else ""
    p.write_text(f"# {comentario}\n" + directiva + "".join(r + "\n" for r in rutas), encoding="utf-8")
    return p


def guardar_local(datos, rutas):
    (pathlib.Path(datos) / "banco_lista.json").write_text(json.dumps(rutas, ensure_ascii=False, indent=1))


def cargar_local(datos):
    p = pathlib.Path(datos) / "banco_lista.json"
    return json.loads(p.read_text()) if p.exists() else None


def _bits(img, fila):
    lu = np.asarray(img, np.float32)
    lu = lu[..., 0] * 0.299 + lu[..., 1] * 0.587 + lu[..., 2] * 0.114
    y = fila * 8
    return [lu[y + 2:y + 6, (COL0 + c) * 8 + 1:(COL0 + c) * 8 + 5].mean() > UMBRAL for c in range(18)]


def leer_codigo(img):
    """El número de la entrada de la pantalla de banco (imagen de 256x240), o None si no hay un código válido."""
    if img is None or np.asarray(img).shape[:2] != (240, 256):
        return None
    a, b = _bits(img, FILA_A), _bits(img, FILA_B)
    if not (a[0] and a[17] and b[0] and b[17]):
        return None
    va = int("".join("1" if x else "0" for x in a[1:17]), 2)
    vb = int("".join("1" if x else "0" for x in b[1:17]), 2)
    return va if va ^ vb == 0xFFFF else None


def pintar_codigo(img, n, color=(236, 238, 236)):
    """Lo que pinta el OS (para el simulador y las pruebas): los bloques de n y de su complemento."""
    for fila, v in ((FILA_A, n & 0xFFFF), (FILA_B, ~n & 0xFFFF)):
        bits = [1] + [(v >> (15 - i)) & 1 for i in range(16)] + [1]
        for c, bit in enumerate(bits):
            if bit:
                img[fila * 8:fila * 8 + 8, (COL0 + c) * 8:(COL0 + c) * 8 + 7] = color
    return img
