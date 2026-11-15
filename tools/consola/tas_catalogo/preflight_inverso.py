"""Reproduce en Mesen2 (su propio mapper) los mejores TAS de cada mapper de la búsqueda inversa (busqueda_inversa.json)
y monta una hoja de contactos por película para comprobar a ojo si sincroniza: un TAS que sincroniza avanza por el
juego hasta su final; uno desfasado se queda muriendo en el primer nivel, en el título o en la demo.

  python3 -I preflight_inverso.py [--por-mapper 2] [--desfases 1] [--jobs 4] [--mappers 0,4]
  -> referencias_inverso/<publicación>_<desfase>/  (capturas, contacto.png, preflight.json) y preflight_inverso.json
"""
import argparse
import concurrent.futures as cf
import json
import pathlib
import sys
import time
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import referencia  # noqa: E402
import tas  # noqa: E402

SALIDA = HERE / "referencias_inverso"


def candidatos(por_mapper, mappers):
    d = json.loads((HERE / "busqueda_inversa.json").read_text())["por_mapper"]
    out = []
    for m, v in sorted(d.items(), key=lambda x: int(x[0])):
        if mappers and int(m) not in mappers:
            continue
        roms = []
        for h in v:                       # ya ordenadas: licenciado > verificado > recorrido largo
            if h["rom"] in roms:
                continue
            roms.append(h["rom"])
            out.append(h)
            if len(roms) == por_mapper:
                break
    return out


def reproducir(trabajo):
    h, desfase, ram = trabajo
    referencia.RAM_INICIAL = ram
    destino = SALIDA / (f"{h['publicacion']}_{desfase}" + (f"_{ram}" if ram else ""))
    destino.mkdir(parents=True, exist_ok=True)
    referencia.CASA = destino / "casa"          # cada proceso con su propia carpeta de Mesen2
    with zipfile.ZipFile(HERE / "peliculas" / f"{h['publicacion']}.zip") as z:
        fm2 = destino / "pelicula.fm2"
        fm2.write_bytes(z.read(h["pelicula"]))
    _, mandos, _ = tas.leer_fm2(fm2)
    entrada = destino / "entrada.bin"
    entrada.write_bytes(bytes(mandos))
    n = len(mandos)
    fin = n + 1800
    shots = sorted({max(1, n * k // 12) for k in range(1, 13)} | {fin})
    t = time.monotonic()
    r = {"mapper": h["mapper"], "rom": h["rom"], "publicacion": h["publicacion"], "verificado": h["verificado"],
         "desfase": desfase, "ram": ram, "fotogramas_pelicula": n, "directorio": str(destino)}
    try:
        ref = referencia.generar(h["ruta"], "", shots, fin, destino, entrada=entrada, desfase=desfase)
        r.update(segundos=round(time.monotonic() - t, 1), p0=ref["p0"], capturas=len(ref["shots"]))
        hoja_contactos(destino, h, ref["shots"], n)
    except Exception as e:  # noqa: BLE001
        r["error"] = str(e)
    (destino / "preflight.json").write_text(json.dumps(r, ensure_ascii=False, indent=1))
    return r


def hoja_contactos(destino, h, shots, n):
    from PIL import Image, ImageDraw
    fs = sorted(shots)
    w, alto = 192, 180
    out = Image.new("RGB", (7 * (w + 4), 2 * (alto + 18) + 22), (30, 30, 30))
    d = ImageDraw.Draw(out)
    d.text((4, 4), f"mapper {h['mapper']}  {h['rom'][:60]}  TAS {h['publicacion']}  ({n} fotogramas)", fill=(255, 255, 0))
    for i, f in enumerate(fs[:14]):
        x, y = (i % 7) * (w + 4), 22 + (i // 7) * (alto + 18)
        out.paste(Image.open(shots[f]).convert("RGB").resize((w, alto)), (x, y + 14))
        d.text((x + 2, y), f"{f}{' (fin+30 s)' if f > n else ''}", fill=(200, 200, 200))
    out.save(destino / "contacto.png")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--por-mapper", type=int, default=2)
    ap.add_argument("--desfases", default="1")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--mappers", default="")
    ap.add_argument("--ram", default=None, help="RAM al encender en Mesen2: AllZeros, AllOnes o Random (FCEUX: $FF)")
    a = ap.parse_args()
    mappers = {int(x) for x in a.mappers.split(",") if x.strip()}
    trabajos = [(h, int(dz), a.ram) for h in candidatos(a.por_mapper, mappers) for dz in a.desfases.split(",")]
    trabajos.sort(key=lambda t: -t[0]["fotogramas"])       # los largos primero: repartir mejor la carga
    print(f"{len(trabajos)} reproducciones", flush=True)
    res = []
    with cf.ProcessPoolExecutor(max_workers=a.jobs) as ex:
        for r in ex.map(reproducir, trabajos):
            res.append(r)
            print(json.dumps({k: r.get(k) for k in ("mapper", "rom", "publicacion", "desfase", "segundos", "p0", "error")},
                             ensure_ascii=False), flush=True)
    previo = json.loads((HERE / "preflight_inverso.json").read_text()) if (HERE / "preflight_inverso.json").exists() else []
    clave = {(r["publicacion"], r["desfase"], r.get("ram")) for r in res}
    todos = [r for r in previo if (r["publicacion"], r["desfase"], r.get("ram")) not in clave] + res
    (HERE / "preflight_inverso.json").write_text(json.dumps(todos, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
