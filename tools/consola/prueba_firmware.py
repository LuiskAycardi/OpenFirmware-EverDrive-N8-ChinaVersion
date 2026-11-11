#!/usr/bin/env python3
"""prueba_firmware.py — pruebas de la lógica del firmware del Nano (firmware/nucleo.c compilado para el PC),
con tiempo simulado: LATCH a 60,0988 Hz, lecturas dobles, fotogramas sin lectura, armado, pulsos y reset.

  python3 -I prueba_firmware.py
"""
import ctypes
import pathlib
import sys

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
from simulador import lib_firmware  # noqa: E402
from mando import botones_en, leer_guion  # noqa: E402

TICKS = 250000
PER = TICKS / 60.0988


class Nano:
    def __init__(self):
        self.l = lib_firmware()
        self.t = 1000
        self.salida = b""
        self.l.nucleo_inicio(self.t)

    def avanzar(self, segundos):
        fin = self.t + int(segundos * TICKS)
        while self.t < fin:
            self.t = min(fin, self.t + 250)          # un tick cada ms
            self.l.nucleo_tick(self.t & 0xFFFFFFFF)

    def orden(self, texto):
        for c in (texto + "\n").encode():
            self.l.nucleo_rx(c, self.t)
        self.l.nucleo_tick(self.t)
        return self.leer()

    def leer(self):
        buf = ctypes.create_string_buffer(65536)
        n = self.l.sim_tx(buf, 65536)
        self.salida += buf.raw[:n]
        return buf.raw[:n].decode()

    def latch(self):
        b = self.l.sim_latch(self.t & 0xFFFFFFFF)
        self.l.nucleo_tick(self.t)
        return (~b) & 0xFF


def comprobar(cond, texto):
    print(("ok    " if cond else "FALLO ") + texto)
    return cond


def main():
    bien = True
    guion = "10-12:a;20-20:b;15-25:start;40-45:up+left"
    tramos = leer_guion(guion)

    # 1. armado tras silencio, lecturas dobles y fotogramas sin lectura
    n = Nano()
    n.orden("GB")
    r = n.orden("GA " + guion)
    bien &= comprobar("ok n=4" in r, f"guion cargado ({r.strip()})")
    n.orden("L 1")
    n.orden("A 5 250")
    n.avanzar(1.0)                                   # el OS carga: silencio
    vistos = {}
    t0 = n.t
    sin_lectura = {16, 17, 30, 31, 32}
    for f in range(5, 50):
        n.t = t0 + int((f - 5) * PER)
        n.l.nucleo_tick(n.t)
        if f in sin_lectura:
            continue
        vistos[f] = n.latch()
        if f % 7 == 0:                               # el juego lee dos veces en este fotograma
            n.t += 250
            n.l.nucleo_tick(n.t)
            segunda = n.latch()
            bien &= comprobar(segunda == vistos[f], f"fotograma {f}: la segunda lectura da lo mismo")
        n.avanzar(0.004)
    salida = n.leer() + n.salida.decode()
    bien &= comprobar("!INICIO fc=5" in salida, "aviso de inicio con fc=5")
    malos = [(f, v, botones_en(tramos, f)) for f, v in vistos.items() if v != botones_en(tramos, f)]
    bien &= comprobar(not malos, f"botones de cada fotograma iguales al guion ({len(vistos)} lecturas) {malos[:3]}")
    e = n.orden("E")
    bien &= comprobar("fc=49" in e, f"fotograma final 49 ({e.strip()})")
    bien &= comprobar("!FIN" in n.salida.decode(), "aviso de fin de guion")

    # 2. pulso T y botones a mano
    n = Nano()
    n.orden("P a+select")
    bien &= comprobar(n.latch() == 0x05, "P a+select")
    n.orden("S a")
    bien &= comprobar(n.latch() == 0x04, "S a")
    n.orden("S")
    n.orden("T down 100")
    bien &= comprobar(n.latch() == 0x20, "T down: pulsado")
    n.avanzar(0.12)
    n.leer()
    bien &= comprobar(n.latch() == 0 and "!T" in n.salida.decode(), "T down: suelto a los 100 ms y aviso !T")

    # 3. reset con Select+B: el juego lee hasta que el kit resetea a los 3,5 s
    n = Nano()
    n.orden("R 5000")
    t0 = n.t
    leidos = []
    while n.t - t0 < 3.5 * TICKS:
        n.t += int(PER)
        n.l.nucleo_tick(n.t)
        leidos.append(n.latch())
    n.avanzar(0.5)
    s = n.salida.decode() + n.leer()
    bien &= comprobar(all(x == 0x06 for x in leidos), "Select+B durante el reset")
    bien &= comprobar("!R reset=1" in s, f"reset detectado por el silencio ({s.strip().splitlines()[-1]})")

    # 4. reset con el juego colgado (no lee): lat=0
    n = Nano()
    n.orden("R 1000")
    n.avanzar(1.2)
    s = n.salida.decode() + n.leer()
    bien &= comprobar("!R reset=0 lat=0" in s, "juego colgado: el reset no puede llegar (lat=0)")

    # 5. errores de formato
    n = Nano()
    bien &= comprobar("error" in n.orden("GA 10-5:a"), "tramo al revés rechazado")
    bien &= comprobar("error" in n.orden("P jump"), "botón desconocido rechazado")
    print("TODO BIEN" if bien else "HAY FALLOS")
    sys.exit(0 if bien else 1)


if __name__ == "__main__":
    main()
