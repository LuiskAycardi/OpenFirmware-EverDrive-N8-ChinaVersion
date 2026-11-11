"""captura.py — vídeo y audio de la capturadora HDMI-USB (UVC) con ffmpeg. No usa OpenCV.

La imagen llega a 1280x720 (GBS-Control a 720p60). Con la calibración (calibrar.py) ffmpeg recorta la zona del
NES y la reduce a 256x240, la resolución del banco. Un hilo lee los fotogramas, les pone la hora de llegada y
guarda los últimos segundos en memoria. Mientras dura una prueba, también los pasa a un clip MP4.

  python3 -I captura.py                  # lista las capturadoras y tarjetas de sonido
  python3 -I captura.py --foto foto.png  # una imagen completa de 1280x720
"""
import argparse
import collections
import glob
import pathlib
import re
import shutil
import signal
import subprocess
import threading
import time

import numpy as np

ANCHO, ALTO, FPS = 1280, 720, 60
NES_W, NES_H = 256, 240


# ---------------------------------------------------------------- dispositivos
def listar_video():
    """[(ruta, nombre)] de /dev/video* que capturan (los nodos de metadatos se descartan con v4l2-ctl)."""
    out = []
    for d in sorted(glob.glob("/sys/class/video4linux/video*"), key=lambda p: int(re.sub(r"\D", "", p) or 0)):
        ruta = "/dev/" + pathlib.Path(d).name
        nombre = (pathlib.Path(d) / "name").read_text().strip() if (pathlib.Path(d) / "name").exists() else "?"
        if shutil.which("v4l2-ctl"):
            r = subprocess.run(["v4l2-ctl", "-d", ruta, "--list-formats"], capture_output=True, text=True)
            if "[0]" not in r.stdout:
                continue
        out.append((ruta, nombre))
    return out


def formatos(ruta):
    """Texto de v4l2-ctl --list-formats-ext (para comprobar MJPG 1280x720 a 60 fps)."""
    if not shutil.which("v4l2-ctl"):
        return ""
    return subprocess.run(["v4l2-ctl", "-d", ruta, "--list-formats-ext"], capture_output=True, text=True).stdout


def admite_720p60(ruta):
    txt = formatos(ruta)
    bloques = re.split(r"\n\s*\[\d+\]", txt)
    for b in bloques:
        if "MJPG" in b and re.search(r"1280x720(?:(?!Size).)*?\(60\.0+ fps\)", b, re.S):
            return "mjpeg"
    return None


def listar_audio():
    """[(dispositivo ALSA, nombre)] de las tarjetas con captura."""
    out = []
    try:
        cards = pathlib.Path("/proc/asound/cards").read_text()
    except OSError:
        return out
    for m in re.finditer(r"^\s*(\d+)\s+\[(\S+)\s*\]:\s*(.+)$", cards, re.M):
        num, ident, desc = m.group(1), m.group(2), m.group(3).strip()
        if glob.glob(f"/dev/snd/pcmC{num}D*c"):
            out.append((f"hw:CARD={ident},DEV=0", desc))
    return out


def audio_de_capturadora():
    """La tarjeta USB de la capturadora: la primera con captura que no sea la placa base (HDA)."""
    for dev, desc in listar_audio():
        if "HDA" not in desc and "HDMI" not in desc:
            return dev
    return None


# ---------------------------------------------------------------- captura real
class Captura:
    """Interfaz común con CapturaSimulada (simulador.py)."""

    def __init__(self, dispositivo=None, audio="auto", segundos=6, log=None):
        self.log = log or (lambda *_: None)
        if not dispositivo:
            vs = listar_video()
            if not vs:
                raise RuntimeError("no hay ninguna capturadora (/dev/video*). ¿Está enchufada?")
            dispositivo = vs[0][0]
        self.dev = dispositivo
        self.formato = admite_720p60(dispositivo) or "mjpeg"
        self.audio = audio_de_capturadora() if audio == "auto" else audio
        self.buf = collections.deque(maxlen=FPS * segundos)
        self.cv = threading.Condition()
        self.proc = None
        self.hilo = None
        self.clip = None
        self.audio_proc = None
        self.n = 0
        self.log(f"vídeo {self.dev} ({self.formato}), audio {self.audio or 'ninguno'}")

    def _entrada(self):
        return ["-f", "v4l2", "-input_format", self.formato, "-video_size", f"{ANCHO}x{ALTO}",
                "-framerate", str(FPS), "-thread_queue_size", "64", "-i", self.dev]

    def foto_completa(self, n=8):
        """Media de n fotogramas completos (1280x720, RGB). Con el flujo parado: el dispositivo es de uno solo."""
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin"] + self._entrada() + [
            "-vf", "select=gte(n\\,10)", "-fps_mode", "passthrough", "-frames:v", str(n),
            "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
        r = subprocess.run(cmd, capture_output=True, timeout=30)
        tam = ANCHO * ALTO * 3
        if r.returncode or len(r.stdout) < tam:
            raise RuntimeError(f"ffmpeg no dio imagen: {r.stderr.decode(errors='replace')[-500:]}")
        k = len(r.stdout) // tam
        fr = np.frombuffer(r.stdout[:k * tam], np.uint8).reshape(k, ALTO, ANCHO, 3)
        return fr.astype(np.float32).mean(0).round().astype(np.uint8)

    def iniciar(self, geometria):
        """Flujo continuo a 256x240 con el filtro de la calibración (geometria["ffmpeg"])."""
        self.parar()
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin"] + self._entrada() + [
            "-vf", geometria["ffmpeg"], "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.hilo = threading.Thread(target=self._lector, daemon=True)
        self.hilo.start()
        if not self.esperar_nuevo(5.0):
            err = self.proc.stderr.read(2000).decode(errors="replace") if self.proc.poll() is not None else ""
            raise RuntimeError(f"la capturadora no da imagen. {err}")

    def _lector(self):
        tam = NES_W * NES_H * 3
        f = self.proc.stdout
        while True:
            d = f.read(tam)
            if not d or len(d) < tam:
                break
            t = time.monotonic()
            img = np.frombuffer(d, np.uint8).reshape(NES_H, NES_W, 3)
            with self.cv:
                self.buf.append((t, img))
                self.n += 1
                clip = self.clip
                self.cv.notify_all()
            if clip:
                try:
                    clip.stdin.write(d)
                except (BrokenPipeError, ValueError):
                    pass

    def parar(self):
        self.parar_clip()
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None

    # ------------------------------------------------------------ lectura
    def ultimo(self):
        with self.cv:
            return self.buf[-1] if self.buf else (None, None)

    def esperar_nuevo(self, espera=1.0):
        with self.cv:
            n0 = self.n
            fin = time.monotonic() + espera
            while self.n == n0:
                q = fin - time.monotonic()
                if q <= 0:
                    return None
                self.cv.wait(q)
            return self.buf[-1]

    def ventana(self, t0, t1):
        with self.cv:
            return [(t, f) for t, f in self.buf if t0 <= t <= t1]

    def estable(self, n=3, espera=2.0):
        """Imagen tras n fotogramas nuevos (para leer el menú cuando ya ha cambiado)."""
        r = None
        for _ in range(n):
            r = self.esperar_nuevo(espera) or r
        return r

    # ------------------------------------------------------------ grabación de cada prueba
    def grabar_clip(self, ruta):
        self.parar_clip()
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
               "-s", f"{NES_W}x{NES_H}", "-r", str(FPS), "-i", "pipe:0", "-c:v", "libx264", "-preset", "veryfast",
               "-crf", "18", "-pix_fmt", "yuv420p", str(ruta)]
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        with self.cv:
            self.clip = p

    def parar_clip(self):
        with self.cv:
            p, self.clip = self.clip, None
        if p:
            try:
                p.stdin.close()
                p.wait(10)
            except (OSError, subprocess.TimeoutExpired):
                p.kill()

    def grabar_audio(self, ruta):
        if not self.audio:
            return False
        self.parar_audio()
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-f", "alsa", "-ac", "2",
               "-ar", "48000", "-i", self.audio, str(ruta)]
        self.audio_proc = subprocess.Popen(cmd, stderr=subprocess.DEVNULL)
        return True

    def parar_audio(self):
        p, self.audio_proc = self.audio_proc, None
        if p:
            p.send_signal(signal.SIGINT)                  # ffmpeg cierra bien el WAV con SIGINT
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()

    def cerrar(self):
        self.parar_audio()
        self.parar()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dispositivo")
    ap.add_argument("--foto", help="guardar una imagen completa (PNG)")
    a = ap.parse_args()
    vs = listar_video()
    print("Capturadoras:", vs or "ninguna")
    for ruta, nombre in vs:
        print(f"  {ruta} {nombre}: MJPG 1280x720 a 60 fps: {'sí' if admite_720p60(ruta) else 'no encontrado'}")
    print("Audio con captura:", listar_audio() or "ninguno", "-> capturadora:", audio_de_capturadora())
    if a.foto:
        from PIL import Image
        c = Captura(a.dispositivo, audio=None, log=print)
        Image.fromarray(c.foto_completa()).save(a.foto)
        print("guardada", a.foto)


if __name__ == "__main__":
    main()
