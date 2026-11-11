#!/usr/bin/env python3
"""Empaqueta un release para la microSD: los RBF compilados (hdl/out), un MAPROUT.BIN generado desde
n8_top.v, las instrucciones (release/LEEME.md), la lista de mappers, la licencia y las sumas SHA-256.

  make -C hdl build
  python3 -I release/make_release.py v0.1.0      -> release/out/OpenFirmware-N8-v0.1.0.zip

Exige un árbol git limpio: el LEEME del paquete cita el commit del que salen los RBF (GPL: fuente
correspondiente).
"""
import hashlib
import pathlib
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
RBFS = [100, 101, 102, 103, 104, 105, 106]


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
    (stage / "EDFC/MAPS").mkdir(parents=True, exist_ok=True)
    for n in RBFS:
        src = ROOT / f"hdl/out/{n}.RBF"
        if not src.exists():
            sys.exit(f"falta {src}: make -C hdl build")
        if src.stat().st_mtime < (ROOT / "hdl/rtl/n8_top.v").stat().st_mtime:
            sys.exit(f"{src} es más antiguo que hdl/rtl/n8_top.v: recompila")
        (stage / f"EDFC/MAPS/{n}.RBF").write_bytes(src.read_bytes())
    lista = subprocess.run([sys.executable, "-I", str(ROOT / "hdl/tools/gen_maprout.py"),
                            str(stage / "EDFC/MAPROUT.BIN"), "--fds", "--lista"],
                           capture_output=True, text=True, check=True).stdout
    (stage / "MAPPERS.txt").write_text(
        f"OpenFirmware-EverDrive-N8-ChinaVersion {ver} (commit {commit})\n"
        "Mapper -> RBF. 254 = FDS: usa el 254.RBF que ya tiene tu SD / uses the 254.RBF already on your SD.\n\n"
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
    print(f"{zpath} ({zpath.stat().st_size} bytes), commit {commit}")
    print(sums, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
