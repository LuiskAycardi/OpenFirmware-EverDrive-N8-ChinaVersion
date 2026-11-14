#!/usr/bin/env python3
"""cobertura.py — qué partes de nuestro RTL recorre cada juego, y qué juegos bastan para probar cada mapper.

En vez de probar toda la biblioteca en la consola, se mide con Verilator la cobertura de líneas (cada rama de
if/case) de la instancia del mapper mientras el juego corre en Mesen2 con nuestro modelo, y por cada mapper se
eligen los juegos que, juntos, recorren todas las ramas que recorre alguno de los candidatos (selección voraz:
primero el que más aporta, después el que más añade a lo ya cubierto...).

  python3 -I cobertura.py --mappers 1,4 --por-mapper 6 --frames 1200        # piloto
  python3 -I cobertura.py --por-mapper 12                                    # todos los mappers del top
  python3 -I cobertura.py --informe cobertura/AAAAMMDD-HHMMSS                # rehacer el informe

Solo cuentan los puntos de la instancia que atiende al mapper del juego (dut.mNNN): las demás instancias también
ven el bus y ejecutan algo de lógica aunque el juego no las use. Una instancia sirve a varios números de mapper
(la del MMC3 atiende al 4, 118, 119...): las ramas de las variantes que ningún candidato usa quedan sin cubrir y
se listan aparte (ramas que solo se probarán con ROMs sintéticas o con un juego concreto).
"""
import argparse
import collections
import concurrent.futures as cf
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import types

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import difftest  # noqa: E402
import simtop  # noqa: E402

RTL_DIR = HERE.parents[1] / "hdl" / "rtl"
ROMSET = pathlib.Path.home() / "Documents" / "Nintendo - Nintendo Entertainment System (Headered)"
# Fuera de los candidatos: aftermarket, sin licencia, programas de prueba y homebrew (el piloto del 2026-11-12, por
# orden alfabético, eligió casi solo eso: "11 in 1 Musical Pack", "240p Test Suite"...).
EXCLUIR = re.compile(r"Aftermarket|Program\)|Test|Homebrew|Switch|Wii|Virtual Console", re.I)
SIN_LICENCIA = re.compile(r"\(Unl\)", re.I)   # van detrás de los licenciados (los mappers piratas solo tienen estos)
# Líneas (ramas if/case) y conmutación (qué bits de cada señal llegan a cambiar): con solo líneas, el MMC1 entero son 21
# puntos y cualquier juego los recorre; los modos y bancos que distinguen a un juego de otro son valores dentro de esos
# bloques, y eso lo ve la conmutación de los registros del mapper (piloto del 2026-11-12).
VFLAGS_COV = "--cc -O3 --top-module n8_sim_top -Wno-fatal -Wno-lint -Wno-style --coverage-line --coverage-toggle"
VDEFS_COV = ("-DVERILATOR=1 -DVM_COVERAGE=1 -DVM_SC=0 -DVM_TIMING=0 -DVM_TRACE=0 -DVM_TRACE_FST=0 "
             "-DVM_TRACE_VCD=0 -DVM_TRACE_SAIF=0 -DVM_VPI=0 -faligned-new")


# ---------------------------------------------------------------- modelos con cobertura, uno por instancia
def modelos_cov(buses, jobs):
    rtl = sorted(RTL_DIR.glob("*.v"))
    h = hashlib.md5(VFLAGS_COV.encode())
    for f in rtl + [HERE / "n8_sim_top.v", HERE / "n8model.cpp", HERE / "n8model.h", HERE / "simtop.py"]:
        h.update(f.name.encode())
        h.update(f.read_bytes())
    cache = HERE / "models" / ("cov_" + h.hexdigest()[:12])
    cache.mkdir(parents=True, exist_ok=True)
    texto = (RTL_DIR / "n8_top.v").read_text()

    def construir(bus):
        lib = cache / f"lib_{bus}.so"
        if lib.exists():
            return
        top = cache / f"top_{bus}.v"
        top.write_text(simtop.generate(texto, bus))
        files = " ".join(str(f) for f in rtl if f.name != "n8_top.v") + f" {top}"
        vinc = "/usr/share/verilator/include"
        r = subprocess.run(["make", "-s", str(lib), f"OBJ={cache}/obj_{bus}", f"LIB={lib}", f"RTL={files}",
                            f"VFLAGS={VFLAGS_COV}", f"VDEFS={VDEFS_COV}", f"COVLIB={vinc}/verilated_cov.cpp"],
                           cwd=HERE, capture_output=True, text=True)
        if r.returncode != 0 or not lib.exists():
            raise RuntimeError(f"modelo {bus}: {r.stderr[-2000:]}")
        shutil.rmtree(cache / f"obj_{bus}", ignore_errors=True)
    with cf.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
        list(ex.map(construir, sorted(set(buses))))
    return cache


# ---------------------------------------------------------------- candidatos
def config(info):
    """Lo que distingue placas del mismo mapper en la cabecera."""
    return (info["prg_kb"], info["chr_kb"], info["battery"], info["byte6"] & 0x09)


def _norm(t):
    t = re.sub(r"\s*[\(\[].*$", "", t).lower()
    t = re.sub(r"^(the|a)\s+", "", t)
    return re.sub(r"[^a-z0-9]+", "", t)


TAS_LISTA = HERE / "listas" / "tasvideos_nes.txt"


def con_tas():
    """Títulos normalizados de juegos con alguna publicación en TASVideos (listas/tasvideos_nes.txt)."""
    if not TAS_LISTA.exists():
        return set()
    return {_norm(l) for l in TAS_LISTA.read_text().splitlines() if l.strip() and not l.startswith("#")}


def compatible_ntsc(ruta):
    """Usa la temporización de la cabecera; no deduce compatibilidad por el idioma."""
    with open(ruta, 'rb') as f:
        h = f.read(16)
    if len(h) != 16 or h[:4] != b'NES\x1a':
        return False
    if h[7] & 0x0c == 0x08:
        return (h[12] & 3) in (0, 2)  # NTSC o multirregión; excluye PAL y Dendy
    return not h[9] & 1


def candidatos(raiz, mappers, por_mapper, ntsc=False):
    por = {m: [] for m in mappers}
    tas = con_tas()
    for dp, _, files in os.walk(raiz):
        for f in files:
            if not f.lower().endswith(".nes") or difftest.SKIP_NAME.search(f) or EXCLUIR.search(f):
                continue
            p = os.path.join(dp, f)
            if ntsc and not compatible_ntsc(p):
                continue
            info = difftest.ines(p)
            if info and info["mapper"] in por and not difftest.supported(info):
                por[info["mapper"]].append((p, info))
    elegidos = {}
    for m, lst in por.items():
        # primero los juegos con TAS publicado (suelen ser los conocidos y los que más exprimen el mapper)
        lst.sort(key=lambda x: (bool(SIN_LICENCIA.search(os.path.basename(x[0]))),
                                _norm(os.path.basename(x[0])) not in tas,
                                not any(t in os.path.basename(x[0]) for t in difftest.PREFER), os.path.basename(x[0])))
        grupos = collections.OrderedDict()
        vistos = set()
        for p, info in lst:
            base = re.sub(r"\s*\(.*$", "", os.path.basename(p)).lower()
            if base in vistos:
                continue
            vistos.add(base)
            grupos.setdefault(config(info), []).append(p)
        # reparto por turnos entre configuraciones de cabecera distintas
        out, colas = [], [list(v) for v in grupos.values()]
        while colas and len(out) < por_mapper:
            for c in list(colas):
                if c:
                    out.append(c.pop(0))
                    if len(out) >= por_mapper:
                        break
                if not c:
                    colas.remove(c)
        elegidos[m] = out
    return elegidos


# ---------------------------------------------------------------- una partida con cobertura
def jugar(slot, rom, mapper, lib, clk, frames, seed, salida):
    os.environ["N8_COV"] = str(salida / "cov.dat")          # proceso propio: su entorno no se mezcla con otros
    home = difftest.prepare_home(slot)
    args = types.SimpleNamespace(script="", clk=clk, model=str(lib), prgram_fill=None)
    r = difftest.run_one(home, rom, "n8", frames, seed, [], salida, args, lib, clk)
    return {"rom": rom, "mapper": mapper, "secs": r["secs"], "fotogramas": len(r["hashes"]),
            "cov": str(salida / "cov.dat") if (salida / "cov.dat").exists() else None}


def leer_cov(ruta, instancia):
    """{punto: veces} de los puntos de la instancia (por ejemplo 'm004') y sus submódulos."""
    marca = f".dut.{instancia}"
    out = {}
    for linea in open(ruta, encoding="latin-1"):
        if not linea.startswith("C '"):
            continue
        clave, n = linea.rsplit("' ", 1)
        kv = dict(x.split("\x02", 1) for x in clave[3:].split("\x01") if "\x02" in x)
        h = kv.get("h", "")
        if marca + "." not in h + "." and not h.endswith(marca):
            continue
        punto = (kv.get("f", "").split("/")[-1], int(kv.get("l", 0)), kv.get("n", ""), kv.get("page", ""),
                 h.split(marca, 1)[1])
        out[punto] = out.get(punto, 0) + int(n)
    return out


def voraz(cubre):
    """cubre: {juego: set(puntos)} -> [(juego, nuevos, acumulado)] hasta no añadir nada."""
    hecho, orden = set(), []
    resto = dict(cubre)
    while resto:
        j = max(resto, key=lambda k: (len(resto[k] - hecho), len(resto[k])))
        nuevos = resto.pop(j) - hecho
        if not nuevos:
            break
        hecho |= nuevos
        orden.append((j, len(nuevos), len(hecho)))
    return orden


# ---------------------------------------------------------------- informe
def informe(salida):
    res = json.loads((salida / "partidas.json").read_text())
    texto = (RTL_DIR / "n8_top.v").read_text()
    tabla = simtop.mapper_table(texto)
    inst_de_bus = {}
    for line in texto.splitlines():
        mm = simtop.INST.match(line)
        if mm:
            inst_de_bus[mm.group(5)] = mm.group(4)
    por_mapper = collections.defaultdict(dict)
    total_inst = {}
    for r in res:
        if not r.get("cov"):
            continue
        inst = inst_de_bus[tabla[r["mapper"]]]
        pts = leer_cov(r["cov"], inst)
        total_inst[inst] = max(total_inst.get(inst, 0), len(pts))
        por_mapper[r["mapper"]][os.path.basename(r["rom"])] = {p for p, n in pts.items() if n > 0}
    resumen, md = {}, ["# Cobertura del RTL por mapper\n",
                       "Juegos elegidos por selección voraz: cada uno añade las ramas (if/case) de la instancia del "
                       "mapper que los anteriores no recorrían. «Alcanzado» = ramas que recorre algún candidato.\n"]
    for m in sorted(por_mapper):
        cubre = por_mapper[m]
        inst = inst_de_bus[tabla[m]]
        union = set().union(*cubre.values()) if cubre else set()
        orden = voraz(cubre)
        resumen[m] = {"instancia": inst, "puntos_instancia": total_inst.get(inst, 0), "alcanzado": len(union),
                      "candidatos": len(cubre), "elegir": [{"juego": j, "nuevos": n, "acumulado": a} for j, n, a in orden],
                      "por_juego": {j: len(s) for j, s in cubre.items()}}
        lin = sum(1 for p in union if "line" in p[3])
        md.append(f"## Mapper {m} (instancia {inst}): {len(union)} de {total_inst.get(inst, 0)} puntos alcanzados "
                  f"({lin} de líneas, {len(union) - lin} de conmutación) con {len(cubre)} candidatos\n")
        for j, n, a in orden:
            md.append(f"- **{j}**: +{n} → {a} ({100 * a / max(1, len(union)):.0f} % de lo alcanzado)")
        md.append("")
    (salida / "cobertura.json").write_text(json.dumps(resumen, indent=1, ensure_ascii=False))
    (salida / "cobertura.md").write_text("\n".join(md))
    print("\n".join(md))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--coleccion", default=str(ROMSET))
    ap.add_argument("--mappers", default="", help="lista separada por comas (por defecto, todos los del top)")
    ap.add_argument("--por-mapper", type=int, default=12)
    ap.add_argument("--frames", type=int, default=1200)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2),
                    help="partidas a la vez (por defecto, una por núcleo físico: con más, todas van más lentas)")
    ap.add_argument("--out")
    ap.add_argument("--ntsc", action="store_true", help="solo cabeceras NTSC o multirregión; excluye PAL y Dendy")
    ap.add_argument("--informe", help="rehacer el informe de una carpeta existente")
    a = ap.parse_args()
    if a.informe:
        informe(pathlib.Path(a.informe))
        return 0
    texto = (RTL_DIR / "n8_top.v").read_text()
    tabla = simtop.mapper_table(texto)
    mappers = [int(x) for x in a.mappers.split(",") if x.strip()] or sorted(tabla)
    cands = candidatos(a.coleccion, mappers, a.por_mapper, ntsc=a.ntsc)
    trabajos = [(rom, m) for m in mappers for rom in cands.get(m, [])]
    print(f"{len(trabajos)} partidas de {a.frames} fotogramas, {len(mappers)} mappers", flush=True)
    buses = {tabla[m] for _, m in trabajos}
    cache = modelos_cov(buses, a.jobs)
    print(f"modelos con cobertura: {len(buses)} en {cache}", flush=True)
    clk50 = set()
    for line in texto.splitlines():
        mm = simtop.INST.match(line)
        if mm:
            src = (RTL_DIR / f"{mm.group(3)}.v").read_text()
            if "posedge clk" in src or "a12_filter" in src or mm.group(2) in ("N8_MAPPER_D", "N8_MAPPER_XD",
                                                                               "N8_MAPPER_DS", "N8_MAPPER_XDP"):
                clk50.add(mm.group(5))
    salida = (pathlib.Path(a.out) if a.out else HERE / "cobertura" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S")).resolve()
    salida.mkdir(parents=True, exist_ok=True)
    res = []
    with cf.ProcessPoolExecutor(max_workers=a.jobs) as ex:
        futuros = {}
        for i, (rom, m) in enumerate(trabajos):
            bus = tabla[m]
            clave = re.sub(r"[^A-Za-z0-9]+", "_", pathlib.Path(rom).stem)[:60]
            d = salida / f"{m:03d}" / clave
            d.mkdir(parents=True, exist_ok=True)
            futuros[ex.submit(jugar, 100 + i % a.jobs, rom, m, cache / f"lib_{bus}.so",
                              50.0 if bus in clk50 else 25.0, a.frames, a.seed, d)] = (rom, m)
        for k, fu in enumerate(cf.as_completed(futuros), 1):
            try:
                r = fu.result()
            except Exception as e:  # noqa: BLE001
                rom, m = futuros[fu]
                r = {"rom": rom, "mapper": m, "error": str(e), "cov": None}
            res.append(r)
            print(f"[{k}/{len(futuros)}] {r['mapper']:3d} {os.path.basename(r['rom'])[:50]}: "
                  f"{r.get('secs', '?')} s{' SIN COBERTURA' if not r.get('cov') else ''}", flush=True)
            (salida / "partidas.json").write_text(json.dumps(res, indent=1, ensure_ascii=False))
    informe(salida)
    return 0


if __name__ == "__main__":
    sys.exit(main())
