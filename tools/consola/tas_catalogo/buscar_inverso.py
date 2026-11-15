"""Búsqueda inversa: qué ROMs de todo el romset tienen una película FM2 de TASVideos con su checksum exacto.

La validación de validar_peliculas.py parte de las ROMs seleccionadas por cobertura y busca películas para ellas;
aquí se recorre todo el romset y, por cada mapper que implementa el RTL, se listan las ROMs para las que existe una
película reproducible por el banco (mismos criterios que validar_peliculas.py, salvo que se admite una orden de
encendido o de reset en el fotograma 0: la película de SMB 1715 empieza con un reset y sincroniza en la NES).

  python3 -I tools/consola/tas_catalogo/buscar_inverso.py        -> busqueda_inversa.json y reporte_inverso.md
"""
import base64
import collections
import hashlib
import json
import os
import pathlib
import re
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools/n8sim"))
import cobertura  # noqa: E402
import difftest  # noqa: E402
import simtop  # noqa: E402

PAL = re.compile(r"\((Europe|Australia|Germany|France|Spain|Italy|Sweden|Netherlands|UK)[^)]*\)", re.I)


def indice_romset():
    """{checksum FM2: [(ruta, info iNES)]} de todas las ROMs del romset."""
    idx = collections.defaultdict(list)
    for dp, _, files in os.walk(cobertura.ROMSET):
        for f in files:
            if not f.lower().endswith(".nes"):
                continue
            p = os.path.join(dp, f)
            b = pathlib.Path(p).read_bytes()
            info = difftest.ines(p)
            if not info:
                continue
            idx["base64:" + base64.b64encode(hashlib.md5(b[16:]).digest()).decode()].append((p, info))
    return idx


def leer_fm2(z, nombre):
    cab, entradas = {}, []
    for linea in z.read(nombre).decode("utf-8", errors="replace").splitlines():
        if linea.startswith("|"):
            entradas.append(linea.split("|"))
        elif " " in linea:
            k, v = linea.split(" ", 1)
            cab[k] = v.strip()
    return cab, entradas


def problemas(cab, entradas):
    e = []
    if not entradas:
        e.append("sin entradas")
    if cab.get("palFlag", "0") != "0":
        e.append("película PAL")
    if cab.get("fourscore", "0") != "0":
        e.append("Four Score")
    if cab.get("microphone", "0") != "0":
        e.append("micrófono")
    if cab.get("port0", "1") != "1":
        e.append("puerto 1 no es un mando estándar")
    if cab.get("port1", "0") not in ("0", "1") or cab.get("port2", "0") != "0":
        e.append("periférico adicional")
    if cab.get("binary", "0") != "0":
        e.append("FM2 binario")
    if cab.get("savestate") or cab.get("startsFromSavestate", "0") != "0":
        e.append("arranca desde savestate")
    if cab.get("saveram") or cab.get("startsFromSaveRam", "0") != "0":
        e.append("SRAM inicial")
    if any(int(c[1] or 0) for c in entradas[1:]):
        e.append("resets u órdenes durante la película")
    if any(len(c) > 3 and any(x not in ". " for x in c[3]) for c in entradas):
        e.append("segundo mando")
    return e


def main():
    tabla = simtop.mapper_table((ROOT / "hdl/rtl/n8_top.v").read_text())
    soportados = set(tabla) | {0}
    pubs = {p["id"]: p for p in json.loads((HERE / "publications.json").read_text())}
    idx = indice_romset()
    print(f"romset: {sum(len(v) for v in idx.values())} ROMs indexadas", flush=True)
    hallazgos = []
    for zp in sorted((HERE / "peliculas").glob("*.zip"), key=lambda p: int(p.stem) if p.stem.isdigit() else 0):
        pid = int(zp.stem) if zp.stem.isdigit() else None
        try:
            with zipfile.ZipFile(zp) as z:
                for nombre in [n for n in z.namelist() if n.lower().endswith(".fm2")]:
                    cab, entradas = leer_fm2(z, nombre)
                    for ruta, info in idx.get(cab.get("romChecksum", ""), []):
                        pub = pubs.get(pid, {})
                        hallazgos.append({
                            "mapper": info["mapper"], "rom": os.path.basename(ruta), "ruta": ruta,
                            "pal_rom": bool(PAL.search(os.path.basename(ruta))), "soportado": info["mapper"] in soportados,
                            "publicacion": pid, "titulo": pub.get("title"), "pelicula": nombre,
                            "verificado": "Verified" in (pub.get("flags") or []), "obsoleta": pub.get("obsoletedById") is not None,
                            "fotogramas": len(entradas), "problemas": problemas(cab, entradas)})
        except zipfile.BadZipFile:
            continue
    utiles = [h for h in hallazgos if h["soportado"] and not h["problemas"] and not h["pal_rom"]]
    por_mapper = collections.defaultdict(list)
    for h in utiles:
        por_mapper[h["mapper"]].append(h)
    # Orden: juegos licenciados primero (las demos aftermarket de pocos segundos apenas ejercitan el mapper),
    # luego verificados en consola, y entre ellos el recorrido más largo (más del juego y del mapper).
    raro = re.compile(r"Aftermarket|Demo|\(Unl\)|Beta|Proto|Hack|Pirate", re.I)
    for v in por_mapper.values():
        v.sort(key=lambda h: (bool(raro.search(h["rom"])), not h["verificado"], -h["fotogramas"]))
    sel = json.loads((ROOT / "tools/n8sim/cobertura/completa/seleccion_juegos.json").read_text())["seleccion"]
    sel_m = collections.defaultdict(set)
    for s in sel:
        sel_m[s["mapper"]].add(s["juego"])
    (HERE / "busqueda_inversa.json").write_text(json.dumps(
        {"hallazgos": hallazgos, "por_mapper": {str(m): v for m, v in sorted(por_mapper.items())}}, ensure_ascii=False, indent=1))
    md = ["# Búsqueda inversa de TAS: todo el romset frente a las películas FM2 de TASVideos\n",
          "Checksum exacto (MD5 de la ROM sin cabecera = `romChecksum`), ROM no PAL, mapper implementado y película "
          "reproducible por el banco (mando 1, sin periféricos, sin savestate ni SRAM, sin resets después del fotograma 0). "
          "Que coincida el checksum no prueba que sincronice desde el menú del N8: falta pasarla por Mesen2.\n",
          f"**{len(por_mapper)} mappers** con al menos una ROM con TAS reproducible "
          f"({sum(1 for v in por_mapper.values() if any(h['verificado'] for h in v))} con alguno verificado en consola); "
          f"{len(utiles)} combinaciones ROM-película.\n",
          "| Mapper | ROM | TAS | Duración | Verificado | Histórico | ¿En la selección por cobertura? |",
          "| --- | --- | --- | --- | --- | --- | --- |"]
    for m in sorted(por_mapper):
        vistos = set()
        for h in por_mapper[m]:
            if h["rom"] in vistos:
                continue
            vistos.add(h["rom"])
            s = int(h["fotogramas"] / 60.0988)
            md.append(f"| {m} | {h['rom']} | [{h['publicacion']}](https://tasvideos.org/{h['publicacion']}M) | "
                      f"{s // 60}:{s % 60:02d} | {'Sí' if h['verificado'] else 'No'} | {'Sí' if h['obsoleta'] else 'No'} | "
                      f"{'sí' if h['rom'] in sel_m[m] else 'no'} |")
    descartes = collections.Counter(p for h in hallazgos if h["soportado"] and not h["pal_rom"] for p in h["problemas"])
    md += ["", "## Coincidencias descartadas por el banco", ""] + [f"- {k}: {n}" for k, n in descartes.most_common()]
    (HERE / "reporte_inverso.md").write_text("\n".join(md) + "\n")
    print("\n".join(md[:3]), flush=True)
    print(f"mappers con TAS reproducible: {sorted(por_mapper)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
