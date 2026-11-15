"""Preflight de películas TAS con FCEUX como juez: ¿sincroniza la película en Mesen2 (la referencia del banco)?

Para cada candidato de la búsqueda inversa (busqueda_inversa.json):
  1. FCEUX (su emulador de origen) reproduce la película: lag de cada fotograma y 12 capturas repartidas. FCEUX abre
     una ventana mientras dura (unos segundos por película).
  2. Mesen2 la reproduce por lecturas del mando (tas.por_lecturas con el lag de FCEUX) con capturas alrededor de los
     mismos puntos (±6 fotogramas: cada emulador tarda distinto en arrancar).
  3. Se compara cada punto con la captura de Mesen2 más parecida. Con diferencia media de color por debajo del
     umbral en todos los puntos (la paleta de cada emulador da ~20), la película sincroniza en Mesen2 y sirve para la
     consola tal cual; si no, se anota en qué punto se separa.

  python3 -I preflight_fceux.py [--por-mapper 2] [--mappers 0,4] [--jobs 4]
  -> referencias_fceux/<publicación>/ (fceux/, mesen/, comparacion.png) y preflight_fceux.json
"""
import argparse
import concurrent.futures as cf
import json
import pathlib
import sys
import zipfile

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))
import referencia  # noqa: E402
import tas  # noqa: E402
from preflight_inverso import candidatos  # noqa: E402

SALIDA = HERE / "referencias_fceux"
UMBRAL = 30          # diferencia media por píxel (0-255) por debajo de la cual dos capturas son la misma escena
VENTANA = 6


def puntos(n):
    return sorted({max(30, n * k // 12) for k in range(1, 13)})


def preparar(h):
    """FCEUX (en serie: abre ventana): película, lag, capturas y entrada por lecturas."""
    d = SALIDA / str(h["publicacion"])
    d.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(HERE / "peliculas" / f"{h['publicacion']}.zip") as z:
        (d / "pelicula.fm2").write_bytes(z.read(h["pelicula"]))
    _, mandos, _ = tas.leer_fm2(d / "pelicula.fm2")
    ps = puntos(len(mandos))
    lag = tas.lag_fceux(d / "pelicula.fm2", h["ruta"], d / "fceux", shots=ps, timeout=3600)
    (d / "lecturas.bin").write_bytes(tas.por_lecturas(mandos, lag))
    return {"fotogramas": len(mandos), "lag": sum(lag), "puntos": ps}


def mesen_y_comparar(trabajo):
    h, prep = trabajo
    d = SALIDA / str(h["publicacion"])
    ps = prep["puntos"]
    shots = sorted({g for f in ps for g in range(max(1, f - VENTANA), f + VENTANA + 1)})
    referencia.CASA = d / "casa"
    r = {"mapper": h["mapper"], "rom": h["rom"], "publicacion": h["publicacion"], "verificado": h["verificado"],
         "fotogramas": prep["fotogramas"], "lag_fceux": prep["lag"]}
    try:
        ref = referencia.generar(h["ruta"], "", shots, max(shots), d / "mesen", entrada=d / "lecturas.bin", desfase=0,
                                 modo="lecturas")
        from PIL import Image
        difs = []
        for f in ps:
            pf = d / "fceux" / f"f{f:05d}.png"
            if not pf.exists():
                difs.append(None)
                continue
            a = np.asarray(Image.open(pf).convert("RGB")).astype(int)
            mejor = None
            for g in range(f - VENTANA, f + VENTANA + 1):
                if g in ref["shots"]:
                    b = np.asarray(Image.open(ref["shots"][g]).convert("RGB"))[8:8 + a.shape[0]].astype(int)
                    v = float(np.abs(a - b).mean())
                    mejor = v if mejor is None else min(mejor, v)
            difs.append(None if mejor is None else round(mejor, 1))
        r["diferencias"] = difs
        malos = [f for f, v in zip(ps, difs) if v is None or v > UMBRAL]
        r["sincroniza"] = not malos
        r["primer_punto_distinto"] = malos[0] if malos else None
        hoja(d, ps, ref["shots"], difs)
    except Exception as e:  # noqa: BLE001
        r["error"] = str(e)
    (d / "preflight.json").write_text(json.dumps(r, ensure_ascii=False, indent=1))
    return r


def hoja(d, ps, mshots, difs):
    from PIL import Image, ImageDraw
    out = Image.new("RGB", (12 * 132, 2 * 138 + 4), (30, 30, 30))
    dr = ImageDraw.Draw(out)
    for i, f in enumerate(ps[:12]):
        pf = d / "fceux" / f"f{f:05d}.png"
        if pf.exists():
            out.paste(Image.open(pf).convert("RGB").resize((128, 120)), (i * 132, 16))
        if f in mshots:
            out.paste(Image.open(mshots[f]).convert("RGB").resize((128, 120)), (i * 132, 138 + 16))
        dr.text((i * 132 + 2, 2), f"FCEUX {f}", fill=(255, 255, 0))
        v = difs[i]
        dr.text((i * 132 + 2, 138 + 2), f"Mesen {v}", fill=(120, 255, 120) if v is not None and v <= UMBRAL else (255, 90, 90))
    out.save(d / "comparacion.png")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--por-mapper", type=int, default=2)
    ap.add_argument("--mappers", default="")
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    mappers = {int(x) for x in a.mappers.split(",") if x.strip()}
    cands = candidatos(a.por_mapper, mappers)
    print(f"{len(cands)} películas", flush=True)
    res = []
    with cf.ProcessPoolExecutor(max_workers=a.jobs) as ex:
        futuros = []
        for h in cands:                                  # FCEUX en serie (ventana); Mesen2 en paralelo detrás
            try:
                prep = preparar(h)
            except Exception as e:  # noqa: BLE001
                res.append({"mapper": h["mapper"], "rom": h["rom"], "publicacion": h["publicacion"], "error": f"FCEUX: {e}"})
                print(json.dumps(res[-1], ensure_ascii=False), flush=True)
                continue
            futuros.append(ex.submit(mesen_y_comparar, (h, prep)))
        for fu in cf.as_completed(futuros):
            r = fu.result()
            res.append(r)
            print(json.dumps({k: r.get(k) for k in ("mapper", "rom", "publicacion", "sincroniza", "primer_punto_distinto",
                                                     "error")}, ensure_ascii=False), flush=True)
    (HERE / "preflight_fceux.json").write_text(json.dumps(res, ensure_ascii=False, indent=1))
    ok = [r for r in res if r.get("sincroniza")]
    print(f"sincronizan en Mesen2: {len(ok)} de {len(res)}; mappers: {sorted({r['mapper'] for r in ok})}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
