"""Reproduce en la NES real, una tras otra, las películas TAS de tanda_consola.json (las que sincronizan en Mesen2
según preflight_fceux.py), de la más corta a la más larga, con prueba.py tas en modo por lecturas.

  python3 -I tanda_consola.py [--max-fotogramas 70000] [--mappers 0,79] [--solo-pendientes] [--solo-verificadas]
  -> resultados_consola.json (un registro por película) y un informe de prueba.py por película
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
CONSOLA = HERE.parent
RES = HERE / "resultados_consola.json"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--max-fotogramas", type=int, default=0, help="saltar las películas más largas que esto")
    ap.add_argument("--mappers", default="")
    ap.add_argument("--solo-pendientes", action="store_true", help="saltar las que ya tienen resultado")
    ap.add_argument("--solo-verificadas", action="store_true",
                    help="solo películas verificadas en consola por TASVideos (las demás pueden apoyarse en la emulación)")
    a = ap.parse_args()
    mappers = {int(x) for x in a.mappers.split(",") if x.strip()}
    tanda = sorted(json.loads((HERE / "tanda_consola.json").read_text()), key=lambda t: t["fotogramas"])
    res = json.loads(RES.read_text()) if RES.exists() else {}
    for t in tanda:
        clave = str(t["publicacion"])
        if mappers and t["mapper"] not in mappers:
            continue
        if a.max_fotogramas and t["fotogramas"] > a.max_fotogramas:
            continue
        if a.solo_pendientes and clave in res:
            continue
        if a.solo_verificadas and not t.get("verificado"):
            continue
        d = HERE / "referencias_fceux" / clave
        fm2 = d / "pelicula.fm2"
        if not fm2.exists():
            d.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(HERE / "peliculas" / f"{clave}.zip") as z:
                fm2.write_bytes(z.read(t["pelicula"]))
        cada = max(600, t["fotogramas"] // 40 // 60 * 60)          # unas 40 escenas por película
        print(f"== mapper {t['mapper']}: {t['rom_sd']} (TAS {clave}, {t['fotogramas']} fotogramas, escena cada {cada})",
              flush=True)
        p = subprocess.run([sys.executable, "-I", "prueba.py", "tas", "--pelicula", str(fm2), "--rom", t["rom_sd"],
                            "--cada", str(cada)], cwd=CONSOLA, capture_output=True, text=True)
        salida = p.stdout + p.stderr
        m = re.search(r"Informe: (\S+)index\.html", salida)
        r = {**t, "codigo": p.returncode, "informe": m.group(1) if m else None}
        if m and (pathlib.Path(m.group(1)) / "results.json").exists():
            x = json.loads((pathlib.Path(m.group(1)) / "results.json").read_text())
            x = x[0] if isinstance(x, list) else x
            esc = x.get("escenas", [])
            r.update(veredicto=x.get("veredicto"), huecos_cola=x.get("huecos_cola"), notas=x.get("notas"),
                     escenas_ok=sum(1 for e in esc if e.get("veredicto") == "ok"), escenas=len(esc),
                     primera_mala=next((e["f"] for e in esc if e.get("veredicto") != "ok"), None))
        else:
            r["error"] = salida[-1500:]
        res[clave] = r
        RES.write_text(json.dumps(res, ensure_ascii=False, indent=1))
        print("   ", json.dumps({k: r.get(k) for k in ("veredicto", "escenas_ok", "escenas", "primera_mala",
                                                       "huecos_cola", "codigo")}, ensure_ascii=False), flush=True)
        if p.returncode != 0 and not m:
            print("   prueba.py falló sin informe: paro la tanda", flush=True)
            print(salida[-1500:], flush=True)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
