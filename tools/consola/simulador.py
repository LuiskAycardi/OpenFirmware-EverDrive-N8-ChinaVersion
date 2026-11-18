"""simulador.py — consola, Nano y capturadora de mentira para la prueba en seco (sin hardware).

- El Nano: la lógica real del firmware (firmware/nucleo.c compilado para el PC, build/libmando_sim.so) detrás de
  un pty. mando.py le habla por el pty igual que a /dev/ttyUSB0.
- La consola: 60,0988 fotogramas por segundo. Cada fotograma en que el programa lee el mando, el simulador pide
  el byte al núcleo como haría el SPI y se lo pasa al "programa":
    * un menú parecido al del OS v13 (texto de 8x8, barra del cursor y barra de estado con el nombre), que navega
      con Arriba/Abajo/A/B por la copia de la SD;
    * los juegos: al lanzar una ROM, 0,8 s sin lecturas (el OS carga) y después las imágenes de referencia de
      Mesen2 (si las hay) o un patrón animado. Empieza a leer el mando en el fotograma p0 de su referencia;
    * la ROM de calibración (con sus botones y su contador);
    * el kit Lava: Select solo unos 2 s y luego Select+A unos 3 s en un juego que lee el mando -> vuelve al menú
      (en la NES el kit repite el reset mientras sigue Select+A; con uno solo el juego vuelve a arrancar).
  Fallos inyectables por ROM: negra, cuelgue (deja de leer el mando y la imagen se congela) o basura.
- La capturadora: la imagen del NES pasada a 1280x720 como un GBS-Control (escala 3,75 x 3, bordes negros,
  desenfoque, ruido, paleta algo distinta) con 3 fotogramas de retraso; el flujo de 256x240 se saca con la
  calibración, como haría ffmpeg.
"""
import collections
import ctypes
import os
import pathlib
import subprocess
import sys
import threading
import time
import wave

import numpy as np

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(AQUI / "rom"))
import banco as banco_mod  # noqa: E402
import calibrar  # noqa: E402
import hacer_rom  # noqa: E402
import menu as menu_mod  # noqa: E402

FPS_NES = 60.0988
TICKS = 250000                      # ticks del núcleo por segundo (4 µs)
LIB = AQUI / "firmware" / "build" / "libmando_sim.so"
GEO_REAL = (160.0, -6.0, 3.75, 3.025)   # ox, oy, sx, sy del "GBS" simulado (recorta 2 líneas arriba y abajo)
RETRASO = 3                         # fotogramas de retraso de la cadena de vídeo


def lib_firmware():
    if not LIB.exists():
        subprocess.run(["make", "-s", "-C", str(AQUI / "firmware"), "sim"], check=True)
    lib = ctypes.CDLL(str(LIB))
    lib.sim_latch.restype = ctypes.c_uint8
    lib.sim_latch.argtypes = [ctypes.c_uint32]
    lib.nucleo_tick.argtypes = [ctypes.c_uint32]
    lib.nucleo_inicio.argtypes = [ctypes.c_uint32]
    lib.nucleo_rx.argtypes = [ctypes.c_uint8, ctypes.c_uint32]
    lib.sim_tx.restype = ctypes.c_uint32
    lib.sim_tx.argtypes = [ctypes.c_char_p, ctypes.c_uint32]
    lib.sim_v5.argtypes = [ctypes.c_uint8]
    lib.sim_boton_reset.restype = ctypes.c_uint8
    return lib


# ---------------------------------------------------------------- fuente de 8x8 para el menú simulado
def fuente_8x8():
    """Fuente de 8x8 nítida: Liberation Mono Bold dibujada a 4x y reducida (parecida a una fuente de NES)."""
    from PIL import Image, ImageDraw, ImageFont
    try:
        f = ImageFont.truetype("LiberationMono-Bold.ttf", 44)
        escala = 4
    except OSError:
        f, escala = ImageFont.load_default(), 1
    glifos = {}
    for c in (chr(i) for i in range(32, 127)):
        im = Image.new("L", (8 * escala, 8 * escala), 0)
        ImageDraw.Draw(im).text((0, -2 * escala), c, fill=255, font=f)
        a = np.asarray(im, np.float32).reshape(8, escala, 8, escala).mean((1, 3))
        glifos[c] = a > 90
    return glifos


class OsSimulado:
    """Menú tipo OS v13: lista de la carpeta, barra del cursor azul y nombre completo abajo en gris."""
    FILAS_LISTA = 21          # entradas por página en el OS v13 (Derecha/Izquierda cambian de página)

    def __init__(self, raiz, estilo="barra+estado"):
        self.raiz = pathlib.Path(raiz)
        self.estilo = estilo              # "barra+estado", "barra" o "flecha"
        self.ruta = ""
        self.cursor = 0
        self.arriba = 0
        self.glifos = fuente_8x8()
        self.anterior = 0
        self.repite = 0

    def lista(self):
        d = self.raiz / self.ruta
        es = menu_mod.entradas(d)
        return es

    def pulsar(self, m):
        nuevos = m & ~self.anterior
        if m and m == self.anterior:
            self.repite += 1
            if self.repite > 20 and self.repite % 4 == 0:
                nuevos |= m & 0x30
        else:
            self.repite = 0
        self.anterior = m
        es = self.lista()
        # Como el OS v13: páginas de FILAS_LISTA entradas; Abajo/Arriba no salen de la página y Derecha/Izquierda
        # pasan a la página siguiente/anterior (cursor en su primera entrada).
        pag = self.cursor // self.FILAS_LISTA
        fin_pag = min(len(es), (pag + 1) * self.FILAS_LISTA) - 1
        if nuevos & 0x20 and self.cursor < fin_pag:
            self.cursor += 1
        if nuevos & 0x10 and self.cursor > pag * self.FILAS_LISTA:
            self.cursor -= 1
        if nuevos & 0x80 and (pag + 1) * self.FILAS_LISTA < len(es):
            self.cursor = (pag + 1) * self.FILAS_LISTA
        if nuevos & 0x40 and pag > 0:
            self.cursor = (pag - 1) * self.FILAS_LISTA
        self.arriba = (self.cursor // self.FILAS_LISTA) * self.FILAS_LISTA
        # Como el OS v13 real (comprobado en la consola el 2026-11-11): B entra en una carpeta o, sobre una ROM, abre el
        # "File Menu"; B otra vez la lanza ("Sel. And Start"); A cierra ese menú o vuelve a la carpeta de arriba.
        archivo = getattr(self, "menu_archivo", None)
        if archivo:
            if nuevos & 0x02:
                self.menu_archivo = None
                return archivo
            if nuevos & 0x01:
                self.menu_archivo = None
            return None
        if nuevos & 0x01 and self.ruta:                 # A: volver
            antes = os.path.basename(self.ruta)
            self.ruta = os.path.dirname(self.ruta)
            es = self.lista()
            self.cursor = es.index(antes) if antes in es else 0
            self.arriba = (self.cursor // self.FILAS_LISTA) * self.FILAS_LISTA
        if nuevos & 0x02 and es:                        # B: entrar, o abrir el File Menu de la ROM
            e = es[self.cursor]
            p = self.raiz / self.ruta / e
            if p.is_dir():
                self.ruta = os.path.join(self.ruta, e) if self.ruta else e
                self.cursor = self.arriba = 0
            elif e.lower().endswith(".nes"):
                self.menu_archivo = os.path.join(self.ruta, e) if self.ruta else e
        return None

    def texto(self, img, fila, col, s, color, fondo=None):
        for i, c in enumerate(s):
            x = (col + i) * 8
            if x >= 256:
                break
            g = self.glifos.get(c, self.glifos["?"])
            bloque = img[fila * 8:fila * 8 + 8, x:x + 8]
            if fondo is not None:
                bloque[:] = fondo
            bloque[g] = color

    def imagen(self):
        img = np.zeros((240, 256, 3), np.uint8)
        self.texto(img, 1, 2, "N8 OS v13  /" + self.ruta, (160, 162, 160))
        es = self.lista()
        for k in range(self.FILAS_LISTA):
            i = self.arriba + k
            if i >= len(es):
                break
            es_dir = (self.raiz / self.ruta / es[i]).is_dir()
            color = (236, 196, 0) if es_dir else (236, 238, 236)
            elegida = i == self.cursor
            fondo = (40, 60, 200) if elegida and self.estilo.startswith("barra") else None
            if elegida and self.estilo == "flecha":
                self.texto(img, 3 + k, 0, ">", (236, 106, 100))
            self.texto(img, 3 + k, 1, es[i][:30], color, fondo)
        if self.estilo == "barra+estado":
            img[28 * 8:30 * 8] = (152, 150, 152)
            if es:
                self.texto(img, 28, 1, es[self.cursor][:30], (236, 238, 236), (152, 150, 152))
        return img


class OsPropioSimulado(OsSimulado):
    """Menú del OS propio (os/src/principal.s, etapa 6): orden alfabético con las carpetas primero, 16 por página, ▶
    y la fila elegida en rojo, nombres sin «.nes» y las carpetas con «/». Arriba/Abajo paran en el borde de la página;
    Derecha/Izquierda pasan de página dando la vuelta; A abre la carpeta o lanza; B vuelve a la de arriba."""
    FILAS_LISTA = 16

    def __init__(self, raiz):
        super().__init__(raiz, estilo="propio")
        self.glifos = fuente_os_propio()

    def lista(self):
        return menu_mod.entradas(self.raiz / self.ruta, os_propio=True)

    def pulsar(self, m):
        nuevos = m & ~self.anterior
        if m and m == self.anterior:
            self.repite += 1
            if self.repite >= 20 and (self.repite - 20) % 4 == 0:
                nuevos |= m & 0xF0
        else:
            self.repite = 0
        self.anterior = m
        es = self.lista()
        if m & 0x04:                                     # con Select: saltos de letra (aquí no hacen falta)
            return None
        n = len(es)
        paginas = max(1, (n + 15) // 16)
        pag, fila = divmod(self.cursor, 16)
        en_pag = min(16, n - pag * 16) if n else 0
        if nuevos & 0x20 and fila + 1 < en_pag:
            self.cursor += 1
        if nuevos & 0x10 and fila > 0:
            self.cursor -= 1
        if nuevos & 0xC0 and paginas > 1:
            pag = (pag + (1 if nuevos & 0x80 else -1)) % paginas
            self.cursor = min(pag * 16 + fila, n - 1)
        self.arriba = (self.cursor // 16) * 16
        if nuevos & 0x02 and m == 0x02 and self.ruta:   # B: volver
            antes = os.path.basename(self.ruta)
            self.ruta = os.path.dirname(self.ruta)
            es = self.lista()
            self.cursor = es.index(antes) if antes in es else 0
            self.arriba = (self.cursor // 16) * 16
        elif nuevos & 0x01 and m == 0x01 and es:        # A: abrir o lanzar
            e = es[self.cursor]
            p = self.raiz / self.ruta / e
            if p.is_dir():
                self.ruta = os.path.join(self.ruta, e) if self.ruta else e
                self.cursor = self.arriba = 0
            elif e.lower().endswith(".nes"):
                return os.path.join(self.ruta, e) if self.ruta else e
        return None

    def imagen(self):
        img = np.zeros((240, 256, 3), np.uint8)
        blanco, rojo = (236, 238, 236), (216, 40, 0)
        es = self.lista()
        n = len(es)
        self.texto(img, 7, 2, (os.path.basename(self.ruta) or "Raiz")[:20], blanco)
        if n:
            pag = f"{self.cursor // 16 + 1}/{(n + 15) // 16}"
            self.texto(img, 7, 30 - len(pag), pag, blanco)
        for k in range(16):
            i = self.arriba + k
            if i >= n:
                break
            p = self.raiz / self.ruta / es[i]
            nombre = es[i] + "/" if p.is_dir() else (es[i][:-4] if es[i].lower().endswith(".nes") else es[i])
            if len(nombre) > 28:
                nombre = nombre[:27] + "…"
            color = rojo if i == self.cursor else blanco
            if i == self.cursor:
                self.texto(img, 9 + k, 1, "▶", rojo)
            self.texto(img, 9 + k, 2, nombre, color)
        return img


def fuente_os_propio():
    """Los glifos de os/herramientas/fuente.py como máscaras de 8x8."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("fuente_os", menu_mod.RAIZ / "os" / "herramientas" / "fuente.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return {c: np.array([[p == "#" for p in fila] + [False] for fila in filas], bool) for c, filas in m.G.items()}


class BancoSimulado:
    """Pantalla del modo banco del OS propio (os/src/banco.s): con EDFC/BANCO.TXT en la SD, una entrada de la lista
    con su número en bloques. Start la lanza (y deja guardada la siguiente); derecha/izquierda cambian de entrada; B
    sale al menú hasta apagar. El número sobrevive a los resets y al apagado (PRG-RAM con pila)."""

    def __init__(self, raiz, glifos):
        self.raiz = pathlib.Path(raiz)
        self.glifos = glifos
        self.i = 0
        self.salir = False
        self.anterior = 0xFF
        self.firma = None

    def activo(self):
        return not self.salir and (self.raiz / banco_mod.LISTA).exists()

    def lista(self):
        texto = (self.raiz / banco_mod.LISTA).read_text(encoding="utf-8")
        if texto != self.firma:                     # otra lista: a la primera, como el OS
            self.firma, self.i = texto, 0
        return banco_mod.lineas(texto)

    def pulsar(self, m):
        nuevos = m & ~self.anterior
        self.anterior = m
        es = self.lista()
        if m == 0x08 and nuevos & 0x08 and self.i < len(es):     # Start solo
            rom = es[self.i]
            self.i += 1
            return rom
        if m == 0x02 and nuevos & 0x02:                          # B solo
            self.salir = True
            return None
        if m & 0x04:                                             # con Select, nada
            return None
        if nuevos & 0x80:
            self.i = 0 if self.i >= len(es) else self.i + 1
        if nuevos & 0x40:
            self.i = len(es) if self.i == 0 else self.i - 1
        return None

    def imagen(self):
        img = np.zeros((240, 256, 3), np.uint8)
        es = self.lista()
        blanco = (236, 238, 236)
        ram = next((l[5:7].upper() for l in (self.firma or "").split("\n") if l.startswith("!ram=")), None)
        OsSimulado.texto(self, img, 7, 2, f"Modo banco  {self.i + 1}/{len(es)}" + (f"  RAM={ram}" if ram else ""), blanco)
        OsSimulado.texto(self, img, 9, 2, es[self.i][:28] if self.i < len(es) else "Lista terminada", blanco)
        banco_mod.pintar_codigo(img, self.i, blanco)
        return img


# ---------------------------------------------------------------- la consola
class ConsolaSimulada:
    def __init__(self, raiz_sd, refs=None, fallos=None, log=None, os_propio=False):
        self.lib = lib_firmware()
        self.os = OsPropioSimulado(raiz_sd) if os_propio else OsSimulado(raiz_sd)
        self.banco = BancoSimulado(raiz_sd, self.os.glifos)
        self.raiz = pathlib.Path(raiz_sd)
        self.refs = refs or {}           # ruta relativa de la ROM -> carpeta de referencia (f*.png, polls.txt)
        self.fallos = fallos or {}       # nombre de archivo -> "negra" | "cuelgue:FOT" | "basura:FOT"
        self.log = log or (lambda *_: None)
        self.estado = "menu"             # menu | carga | juego | apagada
        self.juego = None
        self.f_juego = 0
        self.lee_desde = 5
        self.espera_hasta = 0.0
        self.selb = 0
        self.sel_solo = 0
        self.imagen_actual = self.os.imagen()
        self.cache = {}
        self.cuadros = collections.deque(maxlen=RETRASO + 1)
        self.vivo = True
        self.cola_rx = collections.deque()
        self.lock = threading.Lock()
        self.t0 = time.monotonic()
        maestro, esclavo = os.openpty()
        import tty
        tty.setraw(esclavo)               # sin eco: si no, el saludo del Nano vuelve como si fuera una orden
        self.maestro, self.esclavo = maestro, esclavo
        self.puerto = os.ttyname(esclavo)
        os.set_blocking(maestro, False)
        self.lib.nucleo_inicio(self._ticks())
        self.botones_vistos = collections.deque(maxlen=400)
        self.hilos = [threading.Thread(target=self._bucle_consola, daemon=True),
                      threading.Thread(target=self._bucle_serie, daemon=True)]
        for h in self.hilos:
            h.start()

    def _ticks(self):
        return int((time.monotonic() - self.t0) * TICKS) & 0xFFFFFFFF

    def cerrar(self):
        self.vivo = False
        for h in self.hilos:
            h.join(1)
        for fd in (self.maestro, self.esclavo):
            try:
                os.close(fd)
            except OSError:
                pass

    # ------------------------------------------------------------ serie
    def _bucle_serie(self):
        buf = ctypes.create_string_buffer(4096)
        while self.vivo:
            try:
                d = os.read(self.maestro, 4096)
            except BlockingIOError:
                d = b""
            except OSError:
                d = b""
            with self.lock:
                for c in d:
                    self.lib.nucleo_rx(c, self._ticks())
                self.lib.nucleo_tick(self._ticks())
                n = self.lib.sim_tx(buf, 4096)
            if n:
                try:
                    os.write(self.maestro, buf.raw[:n])
                except OSError:
                    pass
            time.sleep(0.0005)

    # ------------------------------------------------------------ fotogramas
    def _bucle_consola(self):
        """Tiempo real estricto, como la consola: si el PC se retrasa, los fotogramas que faltan se ejecutan
        (lecturas del mando incluidas) sin dibujarlos."""
        periodo = 1.0 / FPS_NES
        t0 = time.monotonic()
        hechos = 0
        while self.vivo:
            debidos = int((time.monotonic() - t0) / periodo) + 1
            if debidos <= hechos:
                time.sleep(max(0.0, t0 + hechos * periodo - time.monotonic()))
                continue
            while hechos < debidos - 1:
                self._fotograma(dibujar=False)
                hechos += 1
            self._fotograma()
            hechos += 1

    def _leer_mando(self):
        with self.lock:
            b = self.lib.sim_latch(self._ticks())
        m = (~b) & 0xFF
        self.botones_vistos.append(m)
        return m

    def _fotograma(self, dibujar=True):
        ahora = time.monotonic()
        self.dibujar = dibujar
        if self.lib.sim_boton_reset():                 # botón RESET pulsado (PC817): la consola espera
            if self.estado != "apagada":
                if self.estado != "reset":
                    self.log("[sim] botón RESET")
                self.estado = "reset"
        elif self.estado == "reset":                  # al soltarlo, el N8 vuelve a su menú
            self.estado, self.espera_hasta = "carga_os", ahora + 0.6
        if self.estado == "reset":
            img = np.zeros((240, 256, 3), np.uint8)
        elif self.estado == "apagada":
            if ahora >= self.espera_hasta:
                self.estado, self.espera_hasta = "carga_os", ahora + 0.8
                self.lib.sim_v5(1)
            img = np.zeros((240, 256, 3), np.uint8)
        elif self.estado == "carga_os":
            img = np.zeros((240, 256, 3), np.uint8)
            if ahora >= self.espera_hasta:
                self.estado = "menu"
        elif self.estado == "menu":
            m = self._leer_mando()
            pantalla = self.banco if self.banco.activo() else self.os
            rom = pantalla.pulsar(m)
            if rom:
                self._lanzar(rom)
            img = pantalla.imagen() if dibujar else self.imagen_actual
        elif self.estado == "carga":
            img = np.zeros((240, 256, 3), np.uint8)
            if ahora >= self.espera_hasta:
                self.estado, self.f_juego, self.selb, self.sel_solo = "juego", 0, 0, 0
        else:
            img = self._juego()
        if dibujar:
            self.cuadros.append((ahora, img))
        self.imagen_actual = img

    def _lanzar(self, rom):
        self.log(f"[sim] el OS lanza {rom}")
        self.juego = rom
        self.estado, self.espera_hasta = "carga", time.monotonic() + 0.8
        self.lee_desde = 5
        ref = self.refs.get(rom)
        if ref and (pathlib.Path(ref) / "polls.txt").exists():
            fs = [int(l.split()[0]) for l in (pathlib.Path(ref) / "polls.txt").read_text().split("\n") if l.strip()]
            if fs:
                self.lee_desde = fs[0]

    def _fallo(self):
        f = self.fallos.get(os.path.basename(self.juego or ""), "")
        tipo, _, desde = f.partition(":")
        return tipo, int(desde or 0)

    def _ref_img(self, f):
        ref = self.refs.get(self.juego)
        if not ref:
            return None
        if ref not in self.cache:
            imgs = {}
            from PIL import Image
            for p in sorted(pathlib.Path(ref).glob("f*.png")):
                imgs[int(p.stem[1:])] = np.asarray(Image.open(p).convert("RGB"))
            self.cache[ref] = imgs
        imgs = self.cache[ref]
        claves = [k for k in imgs if k <= f + 1]
        return imgs[max(claves)] if claves else None

    def _juego(self):
        f = self.f_juego
        tipo, desde = self._fallo()
        colgado = tipo == "cuelgue" and f >= desde
        if not colgado:
            self.f_juego += 1
            if f >= self.lee_desde:
                m = self._leer_mando()
                if m == 0x04:                           # Select solo: el kit Lava se prepara
                    self.sel_solo += 1
                elif m == 0x05 and self.sel_solo >= int(2 * FPS_NES):
                    self.selb += 1                      # luego Select+A: cuenta mientras se mantenga
                else:
                    self.sel_solo, self.selb = 0, 0
                if self.selb >= int(3 * FPS_NES):       # el kit Lava ha repetido el reset: vuelve al menú
                    self.log("[sim] kit Lava: reset")
                    self.estado, self.espera_hasta = "carga_os", time.monotonic() + 0.6
                    return np.zeros((240, 256, 3), np.uint8)
        else:
            return self.imagen_actual
        if not self.dibujar:
            return self.imagen_actual
        if tipo == "negra":
            return np.zeros((240, 256, 3), np.uint8)
        if self.juego and self.juego.endswith("calibracion.nes"):
            m = self.botones_vistos[-1] if self.botones_vistos else 0
            rgb, _, _ = hacer_rom.imagen_esperada(botones=m, contador=(f - 4) & 0xFFF)   # como la ROM: NMI - 4
            return rgb
        img = self._ref_img(f)
        if img is None:
            img = np.zeros((240, 256, 3), np.uint8)
            img[(f // 4) % 240, :] = 200
            img[:, (f * 3) % 256] = (40, 200, 80)
        if tipo == "basura" and f >= desde:
            rng = np.random.default_rng(f)
            img = img.copy()
            img[rng.random((240, 256)) < 0.35] = rng.integers(0, 255, 3, dtype=np.uint8)
        return img

    def apagar_encender(self, segundos=2.0):
        """Lo que haría el usuario: apagar y encender. Vuelve al menú en la raíz."""
        self.log("[sim] apagado y encendido")
        self.estado, self.espera_hasta = "apagada", time.monotonic() + segundos
        self.lib.sim_v5(0)
        self.os.ruta, self.os.cursor, self.os.arriba = "", 0, 0
        self.banco.salir = False                # B del modo banco: hasta apagar

    # ------------------------------------------------------------ la cadena de vídeo
    def cuadro_retrasado(self):
        with self.lock:
            pass
        if not self.cuadros:
            return time.monotonic(), self.imagen_actual
        return self.cuadros[0]


_RUIDO = {}


def gbs(nes, geo=GEO_REAL, rng=None):
    """Imagen del NES (240x256x3) en un cuadro de 1280x720 como la daría el GBS-Control: escalado, bordes
    negros, algo de desenfoque horizontal, paleta un poco distinta y ruido."""
    ox, oy, sx, sy = geo
    clave = geo
    if clave not in _RUIDO:
        ys = np.floor((np.arange(720) + 0.5 - oy) / sy).astype(int)
        xs = np.floor((np.arange(1280) + 0.5 - ox) / sx).astype(int)
        oky, okx = (ys >= 0) & (ys < 240), (xs >= 0) & (xs < 256)
        g = np.random.default_rng(7)
        ruidos = [g.normal(0, 3, (720, 1280, 3)).astype(np.float32) for _ in range(4)]
        _RUIDO[clave] = (np.nonzero(oky)[0], ys[oky], np.nonzero(okx)[0], xs[okx], ruidos, [0])
    fy, iy, fx, ix, ruidos, k = _RUIDO[clave]
    k[0] = (k[0] + 1) % len(ruidos)
    x = nes.astype(np.float32)
    x = x * 0.8 + 0.1 * (np.roll(x, 1, 1) + np.roll(x, -1, 1))
    x = x * np.array([0.94, 1.0, 1.05], np.float32) + 5
    out = np.zeros((720, 1280, 3), np.float32)
    out[fy[0]:fy[-1] + 1, fx[0]:fx[-1] + 1] = x[iy][:, ix]
    out += ruidos[k[0]]
    return out.clip(0, 255).astype(np.uint8)


def degradar(nes, rng):
    """Lo que le pasa a la imagen tras pasar por el GBS, la capturadora y la reducción a 256x240."""
    x = nes.astype(np.float32)
    x = x * 0.8 + 0.1 * (np.roll(x, 1, 1) + np.roll(x, -1, 1))
    x = x * np.array([0.94, 1.0, 1.05], np.float32) + 5 + rng.normal(0, 2.5, x.shape).astype(np.float32)
    return x.clip(0, 255).astype(np.uint8)


class CapturaSimulada:
    """Misma interfaz que captura.Captura."""

    def __init__(self, consola, segundos=6, log=None):
        self.c = consola
        self.buf = collections.deque(maxlen=60 * segundos)
        self.cv = threading.Condition()
        self.n = 0
        self.vivo = False
        self.cal = None
        self.rng = np.random.default_rng(5)
        self.clip = None
        self.audio_ruta = None
        self.audio = "sim"
        self.log = log or (lambda *_: None)

    def foto_completa(self, n=8):
        _, img = self.c.cuadro_retrasado()
        return gbs(img, rng=self.rng)

    def iniciar(self, geometria):
        self.parar()
        self.cal = geometria
        self.vivo = True
        self.hilo = threading.Thread(target=self._bucle, daemon=True)
        self.hilo.start()

    def _bucle(self):
        """Como ffmpeg: cuadro de 1280x720 del "GBS" -> recorte y reducción con la calibración actual. Así una
        calibración mala se nota igual que en la consola de verdad. Va a ~25-30 fps (se saltan cuadros)."""
        ult = None
        while self.vivo:
            t, img = self.c.cuadro_retrasado()
            if t is ult:
                time.sleep(0.003)
                continue
            ult = t
            out = calibrar.aplicar(gbs(img, rng=self.rng), self.cal)
            ahora = time.monotonic()
            with self.cv:
                self.buf.append((ahora, out))
                self.n += 1
                self.cv.notify_all()
                if self.clip is not None:
                    self.clip.append(out[::2, ::2].copy())

    def parar(self):
        self.vivo = False
        h = getattr(self, "hilo", None)
        if h:
            h.join(1)

    def ultimo(self):
        with self.cv:
            return self.buf[-1] if self.buf else (None, None)

    def esperar_nuevo(self, espera=1.0):
        with self.cv:
            n0, fin = self.n, time.monotonic() + espera
            while self.n == n0:
                q = fin - time.monotonic()
                if q <= 0:
                    return None
                self.cv.wait(q)
            return self.buf[-1]

    def estable(self, n=3, espera=2.0):
        r = None
        for _ in range(n):
            r = self.esperar_nuevo(espera) or r
        return r

    def ventana(self, t0, t1):
        with self.cv:
            return [(t, f) for t, f in self.buf if t0 <= t <= t1]

    def grabar_clip(self, ruta):
        self.clip_ruta = ruta
        with self.cv:
            self.clip = []

    def parar_clip(self):
        with self.cv:
            cuadros, self.clip = self.clip, None
        if cuadros:
            from PIL import Image
            ims = [Image.fromarray(c) for c in cuadros[::6][:200]]
            if ims:
                ims[0].save(str(self.clip_ruta).rsplit(".", 1)[0] + ".gif", save_all=True,
                            append_images=ims[1:], duration=100, loop=0)

    def grabar_audio(self, ruta):
        self.audio_ruta = ruta
        self.audio_t0 = time.monotonic()
        return True

    def parar_audio(self):
        if not self.audio_ruta:
            return
        dur = max(0.1, time.monotonic() - self.audio_t0)
        n = int(dur * 48000)
        t = np.arange(n) / 48000
        x = 0.02 * np.random.default_rng(1).normal(size=n)
        if self.c.juego and "Tono" in self.c.juego:
            x += 0.3 * np.sin(2 * np.pi * 1000 * t) * ((t % 1.0) < 0.5)
        pcm = (x.clip(-1, 1) * 32767).astype("<i2")
        with wave.open(str(self.audio_ruta), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(48000)
            w.writeframes(pcm.tobytes())
        self.audio_ruta = None

    def cerrar(self):
        self.parar_clip()
        self.parar_audio()
        self.parar()


def sd_simulada(destino, raiz_real, rom_calibracion):
    """Copia ligera de la SD para la prueba en seco: enlaces a las ROMs de verdad y la ROM de calibración en
    PRUEBAS/0 Calibracion (así la prueba en seco no depende de que esté ya en la SD)."""
    destino = pathlib.Path(destino)
    raiz_real = pathlib.Path(raiz_real)
    for p in sorted(raiz_real.rglob("*")):
        rel = p.relative_to(raiz_real)
        if rel.parts and rel.parts[0] == "EDFC" and len(rel.parts) > 1:
            continue
        q = destino / rel
        if p.is_dir():
            q.mkdir(parents=True, exist_ok=True)
        elif p.suffix.lower() == ".nes" and not q.exists():
            q.parent.mkdir(parents=True, exist_ok=True)
            q.symlink_to(p)
    cal = destino / "PRUEBAS" / "0 Calibracion" / "calibracion.nes"
    cal.parent.mkdir(parents=True, exist_ok=True)
    if not cal.exists():
        cal.symlink_to(rom_calibracion)
    return destino
