#!/usr/bin/env python3
"""flashear.py — graba firmware/mando.hex en el Arduino Nano/Uno por su cargador de arranque (protocolo
STK500 v1 de Optiboot y del cargador antiguo del Nano). Solo biblioteca estándar: no hace falta avrdude.

  python3 -I flashear.py                      # busca el puerto (/dev/ttyUSB* o /dev/ttyACM*)
  python3 -I flashear.py --puerto /dev/ttyUSB0 firmware/mando.hex

Prueba 115200 baudios (Optiboot: Nano nuevo y Uno) y después 57600 (Nano con el cargador antiguo).
Escribe por páginas de 128 bytes, lee todo otra vez y lo compara.
Alternativa con avrdude: make -C firmware flash-avrdude PUERTO=/dev/ttyUSB0 BAUD=57600
"""
import argparse
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from serie import Serie, buscar_puertos  # noqa: E402

PAGINA = 128
OK, INSYNC, EOP = 0x10, 0x14, 0x20


def leer_hex(ruta):
    """Intel HEX -> bytes desde la dirección 0 (huecos a 0xFF)."""
    datos = {}
    base = 0
    for n, linea in enumerate(pathlib.Path(ruta).read_text().splitlines(), 1):
        linea = linea.strip()
        if not linea:
            continue
        if linea[0] != ":":
            raise ValueError(f"línea {n}: no es Intel HEX")
        b = bytes.fromhex(linea[1:])
        if sum(b) & 0xFF:
            raise ValueError(f"línea {n}: suma de control mal")
        cnt, dir_, tipo = b[0], (b[1] << 8) | b[2], b[3]
        carga = b[4:4 + cnt]
        if tipo == 0:
            for i, x in enumerate(carga):
                datos[base + dir_ + i] = x
        elif tipo == 1:
            break
        elif tipo == 2:
            base = ((carga[0] << 8) | carga[1]) << 4
        elif tipo == 4:
            base = ((carga[0] << 8) | carga[1]) << 16
        # 3 y 5 (dirección de arranque): no aplican al AVR
    if not datos:
        raise ValueError("HEX vacío")
    fin = max(datos) + 1
    if fin > 30 * 1024:
        raise ValueError(f"el programa ocupa {fin} bytes: pisaría el cargador")
    return bytes(datos.get(i, 0xFF) for i in range(fin))


class Stk500:
    def __init__(self, s):
        self.s = s

    def orden(self, datos, n_resp=0, espera=0.5):
        self.s.escribir(bytes(datos) + bytes([EOP]))
        r = self.s.leer_exacto(n_resp + 2, espera)
        if len(r) != n_resp + 2 or r[0] != INSYNC or r[-1] != OK:
            raise IOError(f"respuesta inesperada {r.hex()} a {bytes(datos[:1]).hex()}")
        return r[1:-1]

    def sincronizar(self, intentos=12):
        for _ in range(intentos):
            self.s.vaciar()
            self.s.escribir(bytes([0x30, EOP]))
            r = self.s.leer_exacto(2, 0.25)
            if r == bytes([INSYNC, OK]):
                return True
        return False

    def firma(self):
        return self.orden([0x75], 3)

    def direccion(self, byte_dir):
        palabra = byte_dir >> 1
        self.orden([0x55, palabra & 0xFF, palabra >> 8])

    def escribir_pagina(self, byte_dir, datos):
        self.direccion(byte_dir)
        n = len(datos)
        self.orden([0x64, n >> 8, n & 0xFF, ord("F")] + list(datos), 0, 2.0)

    def leer_pagina(self, byte_dir, n):
        self.direccion(byte_dir)
        return self.orden([0x74, n >> 8, n & 0xFF, ord("F")], n, 2.0)

    def salir(self):
        try:
            self.orden([0x51])
        except IOError:
            pass


def flashear(puerto, imagen, bauds=(115200, 57600), log=print):
    for baud in bauds:
        s = Serie(puerto, baud)
        try:
            s.reiniciar_dtr()           # el cargador solo escucha unos instantes tras el reinicio
            st = Stk500(s)
            if not st.sincronizar():
                log(f"{baud} baudios: sin respuesta del cargador")
                continue
            st.orden([0x50])            # entrar en modo de programación (Optiboot lo ignora)
            sig = st.firma()
            log(f"{baud} baudios: cargador encontrado, firma {sig.hex()}")
            if sig != bytes([0x1E, 0x95, 0x0F]):
                raise IOError(f"la firma {sig.hex()} no es la del ATmega328P (1e950f)")
            for a in range(0, len(imagen), PAGINA):
                pag = imagen[a:a + PAGINA].ljust(PAGINA, b"\xff")
                st.escribir_pagina(a, pag)
            log(f"escritos {len(imagen)} bytes; verificando…")
            leido = b"".join(st.leer_pagina(a, PAGINA) for a in range(0, len(imagen), PAGINA))[:len(imagen)]
            if leido != imagen:
                mal = next(i for i in range(len(imagen)) if leido[i] != imagen[i])
                raise IOError(f"la verificación falla en el byte 0x{mal:04x}")
            st.salir()
            log("grabado y verificado")
            return True
        finally:
            s.cerrar()
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hex", nargs="?", default=str(pathlib.Path(__file__).resolve().parent / "firmware" / "mando.hex"))
    ap.add_argument("--puerto")
    ap.add_argument("--baud", type=int, help="solo esta velocidad (115200 Optiboot, 57600 cargador antiguo)")
    a = ap.parse_args()
    imagen = leer_hex(a.hex)
    puerto = a.puerto
    if not puerto:
        ps = buscar_puertos()
        if not ps:
            sys.exit("no hay /dev/ttyUSB* ni /dev/ttyACM*: ¿está el Nano enchufado? (y el usuario en el grupo uucp)")
        puerto = ps[0]
    print(f"{a.hex}: {len(imagen)} bytes -> {puerto}")
    t0 = time.time()
    if not flashear(puerto, imagen, (a.baud,) if a.baud else (115200, 57600)):
        sys.exit("no se pudo hablar con el cargador. Prueba a pulsar RESET en el Nano justo al lanzar la orden, "
                 "o usa avrdude (README).")
    print(f"listo en {time.time() - t0:.1f} s. Comprueba con: python3 -I mando.py --puerto {puerto} estado")


if __name__ == "__main__":
    main()
