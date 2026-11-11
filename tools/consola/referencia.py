"""referencia.py — capturas de referencia de Mesen2 con el mismo guion que se ejecuta en la consola.

Dos fuentes:
  - generar(): Mesen2 con su propio mapper y mesen_ref.lua (segundos por juego). Además de las capturas deja
    polls.txt (fotogramas en que el juego lee el mando): su primer fotograma, p0, es el que el Nano asigna a la
    primera lectura del juego en la consola.
    El ejecutable es el del banco (tools/n8sim/run/Mesen), enlazado en una carpeta propia (.mesen/) con su
    settings.json, sin escribir nada en tools/n8sim.
  - del_banco(): las capturas ref/ (Mesen2) y n8/ (nuestro Verilog) de un informe de tools/n8sim/difftest.py
    lanzado con el mismo --script y --shots (lanzar_banco() hace esa llamada).
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

AQUI = pathlib.Path(__file__).resolve().parent
N8SIM = AQUI.parent / "n8sim"
MESEN = N8SIM / "run" / "Mesen"
AJUSTES = N8SIM / "run" / "settings.json"
LUA = AQUI / "mesen_ref.lua"
CASA = AQUI / ".mesen"


def clave(rom):
    """Mismo nombre de carpeta que usa difftest.py para cada juego."""
    return re.sub(r"[^A-Za-z0-9]+", "_", os.path.splitext(os.path.basename(rom))[0])[:60]


def disponible():
    return MESEN.exists() and AJUSTES.exists()


def preparar_casa():
    CASA.mkdir(parents=True, exist_ok=True)
    exe = CASA / "Mesen"
    if not exe.exists() or exe.stat().st_ino != MESEN.stat().st_ino:
        if exe.exists():
            exe.unlink()
        try:
            os.link(MESEN, exe)
        except OSError:
            shutil.copy2(MESEN, exe)
    shutil.copyfile(AJUSTES, CASA / "settings.json")
    for sub in ("Saves", "SaveStates"):
        d = CASA / sub
        if d.is_dir():
            shutil.rmtree(d)
    return exe


def generar(rom, guion, shots, fotogramas, destino, log=None):
    """Ejecuta Mesen2 (mapper de Mesen) y deja en 'destino': f%05d.png, polls.txt y ref.json."""
    log = log or (lambda *_: None)
    rom = pathlib.Path(rom).resolve()
    destino = pathlib.Path(destino).resolve()
    meta_ruta = destino / "ref.json"
    meta = {"rom": str(rom), "guion": guion, "shots": sorted(shots), "fotogramas": fotogramas}
    if meta_ruta.exists():
        viejo = json.loads(meta_ruta.read_text())
        if all(viejo.get(k) == v for k, v in meta.items()) and (destino / "polls.txt").exists():
            return cargar(destino)
    if not disponible():
        raise RuntimeError(f"no está Mesen2 del banco ({MESEN}); compílalo con make -C tools/n8sim mesen")
    destino.mkdir(parents=True, exist_ok=True)
    for p in destino.glob("f*.p*m"):
        p.unlink()
    exe = preparar_casa()
    env = dict(os.environ)
    for k in ("N8_FPGA", "N8_MODEL"):
        env.pop(k, None)
    env.update({"N8_FRAMES": str(fotogramas), "N8_SCRIPT": guion or "", "N8_SHOT_DIR": str(destino),
                "N8_SHOTS": ",".join(str(s) for s in sorted(shots))})
    timeout = int(fotogramas / 60 * 4) + 60
    with open(destino / "mesen.log", "w") as salida:
        r = subprocess.run([str(exe), "--testrunner", f"--timeout={timeout}", str(LUA), str(rom)], cwd=CASA,
                           env=env, stdout=salida, stderr=subprocess.STDOUT, timeout=timeout + 30)
    from PIL import Image
    for ppm in destino.glob("f*.ppm"):
        Image.open(ppm).save(ppm.with_suffix(".png"))
        ppm.unlink()
    if not (destino / "polls.txt").exists():
        raise RuntimeError(f"Mesen2 no terminó ({r.returncode}); mira {destino / 'mesen.log'}")
    meta_ruta.write_text(json.dumps(meta, indent=1, ensure_ascii=False))
    log(f"referencia de {os.path.basename(str(rom))}: {len(list(destino.glob('f*.png')))} capturas")
    return cargar(destino)


def cargar(destino):
    destino = pathlib.Path(destino)
    polls = []
    p = destino / "polls.txt"
    if p.exists():
        polls = [tuple(int(x) for x in l.split()) for l in p.read_text().splitlines() if l.strip()]
    shots = {int(q.stem[1:]): q for q in sorted(destino.glob("f*.png"))}
    return {"dir": destino, "polls": polls, "p0": polls[0][0] if polls else None, "shots": shots}


def del_banco(carpeta, rom):
    """Capturas de un informe de difftest.py: {'ref': {f: png}, 'n8': {f: png}} (las que haya)."""
    d = pathlib.Path(carpeta) / clave(rom)
    out = {}
    for lado in ("ref", "n8"):
        out[lado] = {int(q.stem[1:]): q for q in sorted((d / lado).glob("f*.png"))}
    return out


def lanzar_banco(roms, guion, shots, fotogramas, salida, jobs=2, log=None):
    """difftest.py con el mismo guion y capturas (lento: el Verilog va ~8x más despacio que la consola).
    Usa homes/w40… del banco para no pisar las tandas de otras sesiones."""
    lista = pathlib.Path(salida) / "roms.txt"
    lista.parent.mkdir(parents=True, exist_ok=True)
    lista.write_text("\n".join(str(r) for r in roms) + "\n")
    cmd = [sys.executable, "-I", str(N8SIM / "difftest.py"), "--rom-list", str(lista), "--frames", str(fotogramas),
           "--script", guion, "--shots", ",".join(str(s) for s in sorted(shots)), "--out", str(salida),
           "--slot-base", "40", "--jobs", str(jobs), "--instancias", "--clk-auto"]
    (log or print)("banco: " + " ".join(cmd))
    return subprocess.run(cmd, cwd=N8SIM).returncode
