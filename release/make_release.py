#!/usr/bin/env python3
"""Empaqueta una compilación completa y propia para la microSD del EverDrive N8 China Version: todo lo que la
BIOS del cartucho lee de la tarjeta sale de este repositorio (nada de Krikzz).

  SD/EDFC/OS.BIN              el OS propio (os/build/OS.BIN)
  SD/EDFC/MAPS/255.RBF        el RBF del modo OS (hdl/out/255.RBF), el que la BIOS carga al encender
  SD/EDFC/MAPS/100-106.RBF    los mappers (hdl/out)
  SD/EDFC/MAPROUT.BIN         mapper -> RBF, generado desde n8_top.v (sin FDS: no hay 254.RBF propio)
  SD/EDFC/SAVE/               carpeta vacía para las partidas (el OS la crea si falta)
  LEEME.md, MAPPERS.txt, LICENSE, SHA256SUMS.txt

  make -C hdl build
  make -C os
  python3 -I release/make_release.py v0.4.0-beta   -> release/out/OpenFirmware-N8-v0.4.0-beta.zip

Exige un árbol git limpio: el LEEME del paquete cita el commit del que sale todo (GPL: fuente correspondiente).
"""
import hashlib
import pathlib
import shutil
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
RBFS = [100, 101, 102, 103, 104, 105, 106, 255]


def git(*a):
    return subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True, check=True).stdout.strip()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    ver = sys.argv[1]
    if git("status", "--porcelain"):
        sys.exit("el árbol git tiene cambios sin confirmar: haz commit antes de empaquetar")
    commit = git("rev-parse", "--short", "HEAD")
    out = ROOT / "release/out"
    name = f"OpenFirmware-N8-{ver}"
    stage = out / name
    if stage.exists():
        shutil.rmtree(stage)
    maps = stage / "SD/EDFC/MAPS"
    maps.mkdir(parents=True)
    (stage / "SD/EDFC/SAVE").mkdir()

    top = (ROOT / "hdl/rtl/n8_top.v").stat().st_mtime
    for n in RBFS:
        src = ROOT / f"hdl/out/{n}.RBF"
        if not src.exists():
            sys.exit(f"falta {src}: make -C hdl build")
        if src.stat().st_mtime < top:
            sys.exit(f"{src} es más antiguo que hdl/rtl/n8_top.v: recompila")
        (maps / f"{n}.RBF").write_bytes(src.read_bytes())

    os_bin = ROOT / "os/build/OS.BIN"
    fuentes = list((ROOT / "os/src").iterdir()) + [ROOT / "os/n8os.cfg", ROOT / "os/Makefile",
                                                    ROOT / "os/herramientas/fuente.py"]
    if not os_bin.exists() or os_bin.stat().st_mtime < max(p.stat().st_mtime for p in fuentes):
        sys.exit(f"{os_bin} falta o es más antiguo que sus fuentes: make -C os")
    (stage / "SD/EDFC/OS.BIN").write_bytes(os_bin.read_bytes())

    lista = subprocess.run([sys.executable, "-I", str(ROOT / "hdl/tools/gen_maprout.py"),
                            str(stage / "SD/EDFC/MAPROUT.BIN"), "--lista"],
                           capture_output=True, text=True, check=True).stdout
    (stage / "MAPPERS.txt").write_text(
        f"OpenFirmware-EverDrive-N8-ChinaVersion {ver} (commit {commit})\n"
        "Mapper -> RBF. Sin FDS (254): no hay 254.RBF propio / No FDS (254): there is no own 254.RBF.\n\n"
        + "\n".join(l.strip() for l in lista.splitlines()[1:]) + "\n")
    leeme = (ROOT / "release/LEEME.md").read_text().replace("{VERSION}", ver).replace("{COMMIT}", commit)
    (stage / "LEEME.md").write_text(leeme)
    (stage / "LICENSE").write_text((ROOT / "LICENSE").read_text())

    files = sorted(p for p in stage.rglob("*") if p.is_file() and p.name != "SHA256SUMS.txt")
    sums = "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(stage)}\n" for p in files)
    (stage / "SHA256SUMS.txt").write_text(sums)
    zpath = out / f"{name}.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(stage.rglob("*")):
            if p.is_file():
                z.write(p, f"{name}/{p.relative_to(stage)}")
            elif p.is_dir() and not any(p.iterdir()):          # carpetas vacías (EDFC/SAVE)
                z.write(p, f"{name}/{p.relative_to(stage)}/")
    print(f"{zpath} ({zpath.stat().st_size} bytes), commit {commit}")
    print(sums, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
