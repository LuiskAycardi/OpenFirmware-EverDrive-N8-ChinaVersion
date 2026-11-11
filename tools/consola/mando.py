#!/usr/bin/env python3
"""mando.py — cliente del mando emulado (Arduino Nano con firmware/mando.hex).

Uso desde otros módulos:  m = Mando("/dev/ttyUSB0"); m.tocar("down", 80); m.guion("120-126:start"); ...
Uso a mano (primera prueba con hardware):
  python3 -I mando.py estado                 # ¿responde? ¿ve los LATCH de la consola? (lat=, per16=)
  python3 -I mando.py monitor                # número de fotograma en directo
  python3 -I mando.py toca start 100         # pulsar Start 100 ms
  python3 -I mando.py pulsa right+b | suelta
  python3 -I mando.py reset                  # Select+B hasta que el kit Lava resetee (máx. 5 s)
  python3 -I mando.py guion "120-126:start;300-306:a" --desde 0
Formato del guion: el de N8_SCRIPT de tools/n8sim/run_test.lua ("ini-fin:boton+boton;...", fotogramas
completos desde el arranque del juego; el primer tramo que contiene el fotograma manda).
"""
import argparse
import collections
import pathlib
import re
import sys
import threading
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from serie import Serie, buscar_puertos, describir  # noqa: E402

BOTONES = ["a", "b", "select", "start", "up", "down", "left", "right"]
TRAMO = re.compile(r"^\s*(\d+)-(\d+):([A-Za-z+]+)\s*$")


class ErrorMando(Exception):
    pass


def mascara(botones):
    """"a+start" -> 0x09"""
    m = 0
    for n in str(botones).lower().split("+"):
        n = n.strip()
        if not n:
            continue
        if n not in BOTONES:
            raise ValueError(f"botón desconocido: {n!r} (válidos: {', '.join(BOTONES)})")
        m |= 1 << BOTONES.index(n)
    return m


def nombres(m):
    return "+".join(b for i, b in enumerate(BOTONES) if m >> i & 1) or "-"


def leer_guion(texto):
    """'120-126:start;300-306:a' -> [(120, 126, 0x08), (300, 306, 0x01)] (valida como el firmware)."""
    tramos = []
    for parte in (texto or "").split(";"):
        if not parte.strip():
            continue
        g = TRAMO.match(parte)
        if not g:
            raise ValueError(f"tramo mal escrito: {parte!r} (formato ini-fin:boton+boton)")
        a, b = int(g.group(1)), int(g.group(2))
        if b < a:
            raise ValueError(f"tramo al revés: {parte!r}")
        tramos.append((a, b, mascara(g.group(3))))
    if len(tramos) > 64:
        raise ValueError(f"el guion tiene {len(tramos)} tramos; el Nano admite 64")
    return tramos


def botones_en(tramos, f):
    for a, b, m in tramos:
        if a <= f <= b:
            return m
    return 0


class Mando:
    """Habla con el firmware. Un hilo lee las líneas: las respuestas van a una cola y los avisos "!…" a otra,
    con la hora de llegada (time.monotonic)."""

    def __init__(self, puerto=None, log=None, esperar_hola=3.0):
        if not puerto:
            ps = buscar_puertos()
            if not ps:
                raise ErrorMando("no encuentro el Nano (/dev/ttyUSB* o /dev/ttyACM*)")
            puerto = ps[0]
        self.puerto = puerto
        self.log = log or (lambda *_: None)
        self.s = Serie(puerto, 115200)
        self.resp = collections.deque()
        self.avisos = collections.deque(maxlen=20000)
        self.fotos = collections.deque(maxlen=200000)      # (hora, fc) de cada "!L"
        self.cv = threading.Condition()
        self.vivo = True
        self.hola = False
        self.hilo = threading.Thread(target=self._lector, daemon=True)
        self.hilo.start()
        # El Nano se reinicia al abrir el puerto (DTR): esperar su saludo; si no llega, preguntar.
        fin = time.monotonic() + esperar_hola
        with self.cv:
            while not self.hola and time.monotonic() < fin:
                self.cv.wait(0.05)
        r = self.orden("?", 1.5)
        if "N8MANDO" not in r:
            raise ErrorMando(f"{puerto} no es el mando N8 (respuesta {r!r}). ¿Está flasheado?")
        self.log(f"mando en {puerto} ({describir(puerto) or 'USB'}): {r}")

    def _lector(self):
        while self.vivo:
            linea = self.s.leer_linea(0.2)
            if linea is None:
                continue
            ahora = time.monotonic()
            with self.cv:
                if linea.startswith("!"):
                    if linea.startswith("!HOLA"):
                        self.hola = True
                    elif linea.startswith("!L "):
                        try:
                            self.fotos.append((ahora, int(linea[3:])))
                        except ValueError:
                            pass
                    self.avisos.append((ahora, linea))
                elif linea:
                    self.resp.append(linea)
                self.cv.notify_all()

    def cerrar(self):
        self.vivo = False
        self.hilo.join(1)
        self.s.cerrar()

    # ------------------------------------------------------------ órdenes
    def orden(self, texto, espera=1.0):
        with self.cv:
            self.resp.clear()
        self.s.escribir((texto + "\n").encode("ascii"))
        fin = time.monotonic() + espera
        with self.cv:
            while not self.resp:
                quedan = fin - time.monotonic()
                if quedan <= 0:
                    raise ErrorMando(f"el mando no responde a {texto!r}")
                self.cv.wait(quedan)
            r = self.resp.popleft()
        if r.startswith("error"):
            raise ErrorMando(f"{texto!r}: {r}")
        return r

    def estado(self):
        r = self.orden("E")
        return {k: (int(v) if k != "man" else int(v, 16)) for k, v in re.findall(r"(\w+)=(\w+)", r)}

    def fotograma(self):
        return self.estado()["fc"]

    def fijar_fotograma(self, n):
        self.orden(f"Z {int(n)}")

    def pulsar(self, botones):
        self.orden(f"P {botones}")

    def soltar(self, botones=""):
        self.orden(f"S {botones}".strip())

    def fijar(self, m):
        self.orden(f"B {m:02x}")

    def eventos(self, activar=True):
        self.orden(f"L {1 if activar else 0}")

    def esperar_aviso(self, prefijo, espera, desde=None):
        """Primer aviso que empieza por 'prefijo' llegado después de 'desde' (hora monotonic)."""
        desde = time.monotonic() - 0.001 if desde is None else desde
        fin = time.monotonic() + espera
        with self.cv:
            while True:
                for t, a in self.avisos:
                    if t >= desde and a.startswith(prefijo):
                        return a
                quedan = fin - time.monotonic()
                if quedan <= 0:
                    return None
                self.cv.wait(quedan)

    def tocar(self, botones, ms=80, pausa_ms=80):
        """Pulsa 'ms' milisegundos, espera a que suelte y deja 'pausa_ms' sin nada (navegar por el menú)."""
        t0 = time.monotonic()
        self.orden(f"T {botones} {int(ms)}")
        if not self.esperar_aviso("!T", ms / 1000 + 1.0, t0):
            raise ErrorMando("el pulso no terminó")
        time.sleep(pausa_ms / 1000)

    def reset(self, ms=5000):
        """Select+B para el kit Lava. Devuelve {'reset': 0/1, 'lat': lecturas durante la pulsación}.
        lat=0: el juego no leía el mando, el kit no lo ha visto -> hay que apagar a mano."""
        t0 = time.monotonic()
        self.orden(f"R {int(ms)}")
        a = self.esperar_aviso("!R", ms / 1000 + 2.0, t0)
        if not a:
            raise ErrorMando("el reset no terminó")
        return {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", a)}

    def guion(self, texto):
        """Carga el guion (se valida antes; va en trozos para no pasar de una línea de 120 caracteres)."""
        leer_guion(texto)
        self.orden("GB")
        partes = [p.strip() for p in (texto or "").split(";") if p.strip()]
        linea = []
        for p in partes:
            if len("GA " + ";".join(linea + [p])) > 110:
                self.orden("GA " + ";".join(linea))
                linea = []
            linea.append(p)
        if linea:
            self.orden("GA " + ";".join(linea))

    def armar(self, p0, silencio_ms=250):
        """El primer LATCH tras 'silencio_ms' sin lecturas será el fotograma p0 y empieza el guion."""
        self.orden(f"A {int(p0)} {int(silencio_ms)}")

    def desarmar(self):
        self.orden("X")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--puerto")
    ap.add_argument("accion", choices=["estado", "monitor", "toca", "pulsa", "suelta", "reset", "guion"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--desde", type=int, default=0, help="guion: fotograma actual (Z)")
    a = ap.parse_args()
    m = Mando(a.puerto, log=print)
    try:
        if a.accion == "estado":
            e = m.estado()
            print(e)
            print("lee LATCH de la consola" if e.get("lat") else "sin LATCH: ¿consola encendida? ¿cable LATCH en D10?")
        elif a.accion == "monitor":
            m.eventos(True)
            ult = None
            while True:
                time.sleep(0.5)
                e = m.estado()
                fps = None
                if m.fotos and len(m.fotos) > 30:
                    (t0, f0), (t1, f1) = m.fotos[-30], m.fotos[-1]
                    fps = (f1 - f0) / max(1e-6, t1 - t0)
                print(f"fc={e['fc']} lat={e['lat']} per={e['per16'] * 4 / 16 / 1000:.3f} ms "
                      f"silencio={e['sil']} ms v5={e['v5']}" + (f" ~{fps:.2f} fps" if fps else ""), flush=True)
                ult = e
        elif a.accion == "toca":
            m.tocar(a.args[0], int(a.args[1]) if len(a.args) > 1 else 100)
        elif a.accion == "pulsa":
            m.pulsar(a.args[0])
        elif a.accion == "suelta":
            m.soltar(a.args[0] if a.args else "")
        elif a.accion == "reset":
            print(m.reset(int(a.args[0]) if a.args else 5000))
        elif a.accion == "guion":
            m.guion(a.args[0])
            m.fijar_fotograma(a.desde)
            print("cargado:", m.estado())
    except KeyboardInterrupt:
        pass
    finally:
        m.cerrar()


if __name__ == "__main__":
    main()
