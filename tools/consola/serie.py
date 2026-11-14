"""serie.py — puerto serie con la biblioteca estándar (termios), sin pyserial.

Sirve para /dev/ttyUSB* (Nano con CH340/FTDI), /dev/ttyACM* (Uno) y los pty del simulador.
"""
import errno
import fcntl
import glob
import os
import pathlib
import select
import struct
import termios
import time

BAUDS = {9600: termios.B9600, 19200: termios.B19200, 38400: termios.B38400, 57600: termios.B57600,
         115200: termios.B115200, 230400: termios.B230400}

USB_CONOCIDOS = {"1a86:7523": "CH340 (Nano clon)", "1a86:5523": "CH341", "0403:6001": "FTDI (Nano original)",
                 "2341:0043": "Arduino Uno", "2341:0001": "Arduino Uno", "2a03:0043": "Arduino Uno",
                 "2341:0243": "Arduino Uno"}


def buscar_puertos():
    """Puertos candidatos, primero los que parecen un Arduino."""
    ps = sorted(glob.glob("/dev/ttyUSB*")) + sorted(glob.glob("/dev/ttyACM*"))
    return sorted(ps, key=lambda p: describir(p) is None)


def describir(puerto):
    """'CH340 (Nano clon)' o None, según el idVendor:idProduct del USB."""
    try:
        d = pathlib.Path("/sys/class/tty") / pathlib.Path(puerto).name / "device"
        d = d.resolve()
        for _ in range(4):
            v, p = d / "idVendor", d / "idProduct"
            if v.exists():
                return USB_CONOCIDOS.get(f"{v.read_text().strip()}:{p.read_text().strip()}")
            d = d.parent
    except OSError:
        pass
    return None


class Serie:
    def __init__(self, ruta, baud=115200):
        try:
            self.fd = os.open(ruta, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        except PermissionError:
            raise PermissionError(f"sin permiso para {ruta}: hace falta el grupo uucp "
                                  f"(sudo usermod -aG uucp $USER y volver a entrar en la sesión)") from None
        self.ruta = ruta
        a = termios.tcgetattr(self.fd)
        a[0] = 0                                                     # iflag: crudo
        a[1] = 0                                                     # oflag
        # Sin HUPCL: al cerrar no se baja DTR, así que al volver a abrir el puerto el Arduino no se reinicia. Con el
        # LGT8F, ese reinicio movía las líneas del mando y el menú del N8 dejaba de leerlo (2026-11-11). Para grabar,
        # flashear.py lo reinicia a propósito con reiniciar_dtr().
        a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        a[3] = 0                                                     # lflag: sin eco ni líneas
        a[4] = a[5] = BAUDS[baud]
        a[6][termios.VMIN] = 0
        a[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, a)
        self.buf = bytearray()

    # ------------------------------------------------------------ líneas de control
    def _modem(self, bits, activar):
        try:
            fcntl.ioctl(self.fd, termios.TIOCMBIS if activar else termios.TIOCMBIC, struct.pack("I", bits))
        except OSError:
            pass                                                     # un pty no tiene DTR

    def reiniciar_dtr(self):
        """Reinicia el Arduino como avrdude: DTR/RTS a 0, 250 ms, a 1 (el condensador da el pulso a RESET)."""
        self._modem(termios.TIOCM_DTR | termios.TIOCM_RTS, False)
        time.sleep(0.25)
        self.vaciar()
        self._modem(termios.TIOCM_DTR | termios.TIOCM_RTS, True)
        time.sleep(0.05)

    # ------------------------------------------------------------ E/S
    def escribir(self, datos):
        vista = memoryview(bytes(datos))
        while vista:
            _, w, _ = select.select([], [self.fd], [], 1.0)
            if not w:
                raise TimeoutError("el puerto serie no acepta datos")
            n = os.write(self.fd, vista)
            vista = vista[n:]

    def _llenar(self, espera):
        r, _, _ = select.select([self.fd], [], [], max(0.0, espera))
        if not r:
            return False
        try:
            d = os.read(self.fd, 4096)
        except OSError as e:
            if e.errno in (errno.EAGAIN, errno.EIO):                 # EIO: el otro lado del pty se cerró
                return False
            raise
        if not d:
            return False
        self.buf += d
        return True

    def leer_exacto(self, n, espera):
        fin = time.monotonic() + espera
        while len(self.buf) < n and time.monotonic() < fin:
            self._llenar(fin - time.monotonic())
        r = bytes(self.buf[:n])
        del self.buf[:n]
        return r

    def leer_linea(self, espera):
        """Una línea sin el salto, o None si no llega en 'espera' segundos."""
        fin = time.monotonic() + espera
        while True:
            i = self.buf.find(b"\n")
            if i >= 0:
                linea = bytes(self.buf[:i]).decode("ascii", "replace").rstrip("\r")
                del self.buf[:i + 1]
                return linea
            quedan = fin - time.monotonic()
            if quedan <= 0:
                return None
            self._llenar(min(quedan, 0.05))

    def vaciar(self):
        try:
            termios.tcflush(self.fd, termios.TCIFLUSH)
        except termios.error:
            pass
        while self._llenar(0):
            pass
        self.buf.clear()

    def cerrar(self):
        try:
            os.close(self.fd)
        except OSError:
            pass
