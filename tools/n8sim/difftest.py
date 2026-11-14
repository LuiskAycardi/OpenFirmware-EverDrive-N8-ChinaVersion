#!/usr/bin/env python3
"""difftest.py — Pruebas diferenciales de los mappers del N8 en Mesen2.

Cada ROM se ejecuta dos veces con la misma secuencia de botones:
  ref : Mesen2 con su propio mapper (referencia de comportamiento)
  n8  : Mesen2 con nuestro hdl/rtl/n8_top.v (Verilator) como cartucho, configurado como el OS v13
y se comparan los fotogramas por hash. Si divergen, se capturan los dos fotogramas y una
imagen de diferencias. Resultado: informe HTML + results.json.

Ejemplos (desde tools/n8sim):
  python3 -I difftest.py "/ruta/juego.nes" ...
  python3 -I difftest.py --collection ~/Documents/SD_N8 --mappers 0,1,2,3,4,7 --per-mapper 10
"""
import argparse
import concurrent.futures as cf
import datetime
import html
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
RUN = HERE / "run"
LUA = HERE / "run_test.lua"
HOMES = HERE / "homes"
MINOR_PX = 32      # umbral de "diferencia menor" (píxeles por fotograma)
BOOT_FRAMES = 10   # diferencias solo en los primeros N fotogramas = estado de encendido indefinido
SETTINGS = RUN / "settings.json"

SKIP_NAME = re.compile(r"\((Proto|Beta|Sample|Demo|Hack|Pirate|Virtual Console|.*Collection.*)\)|\[", re.I)
PREFER = ("(USA", "(World", "(Japan, USA", "(USA, Europe", "(Europe")


def ines(path):
    with open(path, "rb") as f:
        h = f.read(16)
    if len(h) != 16 or h[:4] != b"NES\x1a":
        return None
    mapper = (h[6] >> 4) | (h[7] & 0xF0)
    nes2 = (h[7] & 0x0C) == 0x08
    if nes2:
        mapper |= (h[8] & 0x0F) << 8
    def rom_size(low, upper, unit):
        if nes2 and upper == 15:
            return (1 << (low >> 2)) * (2 * (low & 3) + 1)
        return ((upper << 8) | low) * unit
    def ram_size(n):
        return (64 << n) if n else 0
    prg = rom_size(h[4], h[9] & 15 if nes2 else 0, 16384)
    chr_ = rom_size(h[5], h[9] >> 4 if nes2 else 0, 8192)
    if not nes2 and h[4] == 0:
        prg = 4 * 1024 * 1024  # convención iNES que aplica el emulador del banco
    return {"mapper": mapper, "prg_kb": prg / 1024, "chr_kb": chr_ / 1024,
            "prg_bytes": prg, "chr_bytes": chr_, "nes2": nes2,
            "submapper": h[8] >> 4 if nes2 else None,
            "prg_ram_bytes": ram_size(h[10] & 15) if nes2 else None,
            "prg_nvram_bytes": ram_size(h[10] >> 4) if nes2 else None,
            "chr_ram_bytes": ram_size(h[11] & 15) if nes2 else None,
            "chr_nvram_bytes": ram_size(h[11] >> 4) if nes2 else None,
            "extended_rom_encoding": bool(nes2 and h[9]),
            "file_bytes": pathlib.Path(path).stat().st_size,
            "trainer": bool(h[6] & 4), "console_type": h[7] & 3,
            "byte6": h[6], "four_screen": bool(h[6] & 8), "battery": bool(h[6] & 2)}


def supported(info):
    if info is None:
        return "no es iNES"
    if info["mapper"] > 255:
        return "mapper >= 256"
    if info["prg_kb"] == 0 or info["prg_kb"] > 512:
        return "PRG > 512 KB"
    if info["chr_kb"] > 512:
        return "CHR > 512 KB"
    return None


def pick_from_collection(root, mappers, per_mapper):
    by_mapper = {m: [] for m in mappers}
    for dp, _, files in os.walk(root):
        if "/EDFC" in dp:
            continue
        for f in files:
            if not f.lower().endswith(".nes") or f.startswith("._") or SKIP_NAME.search(f):
                continue
            p = os.path.join(dp, f)
            info = ines(p)
            if info and info["mapper"] in by_mapper and not supported(info):
                by_mapper[info["mapper"]].append(p)
    out = []
    for m in mappers:
        lst = sorted(by_mapper[m], key=lambda p: (not any(t in os.path.basename(p) for t in PREFER), os.path.basename(p)))
        # sin repetir el mismo juego en varias regiones/revisiones
        seen, chosen = set(), []
        for p in lst:
            base = re.sub(r"\s*\(.*$", "", os.path.basename(p)).lower()
            if base in seen:
                continue
            seen.add(base)
            chosen.append(p)
            if len(chosen) >= per_mapper:
                break
        out += chosen
    return out


def prepare_home(i):
    home = HOMES / f"w{i}"
    home.mkdir(parents=True, exist_ok=True)
    exe = home / "Mesen"
    src = RUN / "Mesen"
    if not exe.exists() or exe.stat().st_ino != src.stat().st_ino:
        if exe.exists():
            exe.unlink()
        os.link(src, exe)
    shutil.copyfile(SETTINGS, home / "settings.json")
    return home


def run_one(home, rom, mode, frames, seed, shots, outdir, args, model=None, clk=None):
    for sub in ("Saves", "SaveStates"):
        d = home / sub
        if d.is_dir() and d.parent == home:
            shutil.rmtree(d)
    fill = getattr(args, "prgram_fill", None)
    if fill is not None and mode != "n8":
        # misma PRG-RAM inicial en la referencia: partida (.sav) de 8 KB con ese byte
        (home / "Saves").mkdir(exist_ok=True)
        (home / "Saves" / (pathlib.Path(rom).stem + ".sav")).write_bytes(bytes([fill]) * 0x2000)
    outdir.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({"N8_FRAMES": str(frames), "N8_SEED": str(seed), "N8_OUT": str(outdir / "hashes.txt"),
                "N8_SHOTS": ",".join(str(s) for s in shots), "N8_SHOT_DIR": str(outdir),
                "N8_SCRIPT": args.script})
    if mode == "n8":
        env.update({"N8_FPGA": "1", "N8_MODEL": str(model or args.model), "N8_CLK_MHZ": str(clk or args.clk)})
        if fill is not None:
            env["N8_PRGRAM_FILL"] = str(fill)
    else:
        for k in ("N8_FPGA", "N8_MODEL"):
            env.pop(k, None)
    # n8 va ~8x más lento que tiempo real a 25 MHz (más con clk mayor o con la CPU compartida)
    slow = 60 * max(1.0, (clk or args.clk) / 25.0) if mode == "n8" else 4
    timeout = int(frames / 60 * slow) + 120
    t0 = time.time()
    with open(outdir / "log.txt", "w") as log:
        p = subprocess.run([str(home / "Mesen"), "--testrunner", f"--timeout={timeout}", str(LUA), rom],
                           cwd=home, env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        from PIL import Image
        for ppm in outdir.glob("f*.ppm"):
            Image.open(ppm).save(ppm.with_suffix(".png"))
            ppm.unlink()
    except ImportError:
        pass
    hashes = []
    hp = outdir / "hashes.txt"
    if hp.exists():
        hashes = [l.split()[1] for l in hp.read_text().splitlines() if l.strip()]
    return {"exit": p.returncode, "secs": round(time.time() - t0, 1), "hashes": hashes}


def diff_image(a_png, b_png, out_png):
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        return None
    if not (a_png.exists() and b_png.exists()):
        return None
    a = np.asarray(Image.open(a_png).convert("RGB")).astype(int)
    b = np.asarray(Image.open(b_png).convert("RGB")).astype(int)
    if a.shape != b.shape:
        return None
    mask = np.any(a != b, axis=2)
    img = (b * 0.35).astype("uint8")
    img[mask] = [255, 40, 40]
    Image.fromarray(img).save(out_png)
    return int(mask.sum())


def task(slot, rom, args, outroot):
    home = prepare_home(slot)
    info = ines(rom)
    name = os.path.basename(rom)
    key = re.sub(r"[^A-Za-z0-9]+", "_", os.path.splitext(name)[0])[:60]
    d = outroot / key
    res = {"rom": rom, "name": name, "key": key, **info}
    extra = [int(x) for x in args.shots.split(",") if x.strip()]
    shots = sorted(set(extra + [args.frames]))
    model = args.models.get(info["mapper"], args.model) if args.models else args.model
    clk = args.clks.get(info["mapper"], args.clk) if args.clks else args.clk
    res["model"], res["clk"] = str(model), clk
    ref = run_one(home, rom, "ref", args.frames, args.seed, shots, d / "ref", args)
    n8 = run_one(home, rom, "n8", args.frames, args.seed, shots, d / "n8", args, model, clk)
    res["secs_ref"], res["secs_n8"] = ref["secs"], n8["secs"]
    if len(ref["hashes"]) < args.frames:
        res["status"] = "error_ref"
        return res
    if len(n8["hashes"]) < args.frames:
        res["status"] = "error_n8"
        res["frames_n8"] = len(n8["hashes"])
        return res
    first = next((i + 1 for i, (x, y) in enumerate(zip(ref["hashes"], n8["hashes"])) if x != y), None)
    res["diff_frames"] = sum(1 for x, y in zip(ref["hashes"], n8["hashes"]) if x != y)
    res["first_diff"] = first
    if first is None:
        res["status"] = "ok"
        return res
    # Clasificación automática: se capturan hasta 5 fotogramas distintos repartidos y se cuentan
    # píxeles. "menor" = como mucho MINOR_PX píxeles por fotograma (típico de un efecto que el juego
    # cambia a mitad de línea y que cae unos píxeles antes/después); "diverge" = cualquier cosa mayor
    # (una barra de estado desplazada una línea ya son >= 256 píxeles).
    diffs = [i + 1 for i, (x, y) in enumerate(zip(ref["hashes"], n8["hashes"])) if x != y]
    pick = sorted({diffs[0], diffs[len(diffs) // 4], diffs[len(diffs) // 2], diffs[3 * len(diffs) // 4], diffs[-1]})
    run_one(home, rom, "ref", pick[-1], args.seed, pick, d / "ref_div", args)
    run_one(home, rom, "n8", pick[-1], args.seed, pick, d / "n8_div", args, model, clk)
    samples = {}
    for f in pick:
        samples[f] = diff_image(d / "ref_div" / f"f{f:05d}.png", d / "n8_div" / f"f{f:05d}.png", d / f"diff_{f:05d}.png")
    worst = max(samples, key=lambda f: samples[f] or 0)
    res["diff_samples"] = samples
    res["worst_frame"] = worst
    res["status"] = classify(samples)
    return res


def build_instance_models(mappers, rtl_dir, jobs):
    """Un modelo Verilator por instancia de mapper (simtop.py): solo la instancia del juego, el resto del
    top igual. Se guardan en models/<hash del RTL>/ y se reutilizan mientras el RTL no cambie."""
    import hashlib
    sys.path.insert(0, str(HERE))
    import simtop
    rtl = sorted(pathlib.Path(rtl_dir).glob("*.v"))
    h = hashlib.md5()
    for f in rtl + [HERE / "n8_sim_top.v", HERE / "n8model.cpp", HERE / "n8model.h", HERE / "simtop.py"]:
        h.update(f.name.encode()); h.update(f.read_bytes())
    cache = HERE / "models" / h.hexdigest()[:12]
    cache.mkdir(parents=True, exist_ok=True)
    text = (pathlib.Path(rtl_dir) / "n8_top.v").read_text()
    table = simtop.mapper_table(text)
    buses = {m: table.get(m, "bus_000") for m in mappers}
    def build(bus):
        lib = cache / f"lib_{bus}.so"
        if lib.exists():
            return
        top = cache / f"top_{bus}.v"
        top.write_text(simtop.generate(text, bus))
        files = " ".join(str(f) for f in rtl if f.name != "n8_top.v") + f" {top}"
        r = subprocess.run(["make", "-s", "model", f"OBJ={cache}/obj_{bus}", f"LIB={lib}", f"RTL={files}"],
                           cwd=HERE, capture_output=True, text=True)
        if r.returncode != 0 or not lib.exists():
            raise RuntimeError(f"modelo {bus}: {r.stderr[-2000:]}")
        shutil.rmtree(cache / f"obj_{bus}", ignore_errors=True)
    with cf.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
        list(ex.map(build, sorted(set(buses.values()))))
    print(f"modelos por instancia: {len(set(buses.values()))} en {cache}")
    # Instancias que usan clk (filtro de A12, latches del MMC2, motores de sonido) o que conducen el bus de
    # la CPU (la habilitación espera 2 ciclos de clk): siempre a 50 MHz, el oscilador real. En las demás clk
    # solo mueve la vigilancia de M2 del OS y el DAC de sonido, así que con --clk-auto van a 25 MHz (mismo
    # resultado y casi el doble de rápido).
    rtl_dir = pathlib.Path(rtl_dir)
    clk50 = set()
    for line in text.splitlines():
        mm = simtop.INST.match(line)
        if not mm:
            continue
        macro, mod, bus = mm.group(2), mm.group(3), mm.group(5)
        src = (rtl_dir / f"{mod}.v").read_text()
        uses_clk = "posedge clk" in src or "a12_filter" in src or "snd_5b" in src
        if uses_clk or macro in ("N8_MAPPER_D", "N8_MAPPER_XD", "N8_MAPPER_DS", "N8_MAPPER_XDP"):
            clk50.add(bus)
    clks = {m: (50.0 if b in clk50 else 25.0) for m, b in buses.items()}
    return {m: cache / f"lib_{b}.so" for m, b in buses.items()}, clks


def classify(samples):
    """arranque: solo difieren los primeros BOOT_FRAMES fotogramas (registros sin configurar al
    encender: indefinido en el hardware; Mesen2 deja la CHR sin mapear, nosotros arrancamos en 0).
    menor: después del arranque, como mucho MINOR_PX píxeles por fotograma. diverge: el resto."""
    post = [v for f, v in samples.items() if int(f) > BOOT_FRAMES]
    if not post:
        return "arranque"
    if any(v is None for v in post):
        return "diverge"
    return "menor" if max(post) <= MINOR_PX else "diverge"


def write_report(outroot, results, args):
    (outroot / "results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False))
    ok = sum(r["status"] == "ok" for r in results)
    minor = sum(r["status"] in ("menor", "arranque") for r in results)
    rows = []
    for r in sorted(results, key=lambda r: (r["status"] == "ok", r.get("mapper", 0), r["name"])):
        k = r["key"]
        if r["status"] == "ok":
            st = f'<span class="ok">idéntico ({args.frames} fotogramas)</span>'
            imgs = f'<img src="{k}/n8/f{args.frames:05d}.png" title="nuestro Verilog, último fotograma">'
        elif r["status"] in ("diverge", "menor", "arranque"):
            f, w = r["first_diff"], r.get("worst_frame", r["first_diff"])
            cls = "bad" if r["status"] == "diverge" else "minor"
            label = {"diverge": "diverge", "menor": "diferencias menores",
                     "arranque": f"solo al encender (fotogramas ≤ {BOOT_FRAMES})"}[r["status"]]
            samples = ", ".join(f"{k}: {v}" for k, v in sorted(r.get("diff_samples", {}).items(), key=lambda kv: int(kv[0])))
            st = (f'<span class="{cls}">{label}</span> desde el fotograma {f}<br>'
                  f'<small>{r["diff_frames"]} fotogramas distintos; píxeles distintos por fotograma muestreado: {samples}</small>')
            imgs = (f'<figure><img src="{k}/ref_div/f{w:05d}.png"><figcaption>Mesen ({w})</figcaption></figure>'
                    f'<figure><img src="{k}/n8_div/f{w:05d}.png"><figcaption>N8 Verilog ({w})</figcaption></figure>'
                    f'<figure><img src="{k}/diff_{w:05d}.png"><figcaption>diferencias</figcaption></figure>')
        else:
            st = f'<span class="bad">{r["status"]}</span>'
            imgs = ""
        flags = ("4 pantallas " if r.get("four_screen") else "") + ("pila" if r.get("battery") else "")
        rows.append(f'<tr><td>{r.get("mapper")}</td><td>{html.escape(r["name"])}<br><small>PRG {r.get("prg_kb")} KB, '
                    f'CHR {r.get("chr_kb") or "RAM"}{" KB" if r.get("chr_kb") else ""} {flags}</small></td>'
                    f'<td>{st}<br><small>{r.get("secs_ref")} s / {r.get("secs_n8")} s</small></td><td class="imgs">{imgs}</td></tr>')
    page = f"""<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Pruebas N8</title>
<style>body{{font-family:sans-serif;margin:16px;background:#fafafa;color:#222}} table{{border-collapse:collapse}}
td{{border-bottom:1px solid #ddd;padding:6px;vertical-align:top}} img{{width:256px;image-rendering:pixelated}}
figure{{display:inline-block;margin:0 6px 0 0}} figcaption{{font-size:12px;text-align:center}}
.ok{{color:#167a2c;font-weight:bold}} .minor{{color:#b26a00;font-weight:bold}} .bad{{color:#b3261e;font-weight:bold}}</style></head><body>
<h1>Pruebas diferenciales N8 — {ok}/{len(results)} idénticos, {minor} con diferencias menores o de arranque</h1>\n<p>Menor = como mucho {MINOR_PX} píxeles por fotograma. Arranque = solo en los primeros {BOOT_FRAMES} fotogramas (registros sin configurar).</p>
<p>{datetime.datetime.now():%Y-%m-%d %H:%M} · {args.frames} fotogramas · semilla {args.seed} · clk {args.clk} MHz ·
modelo {html.escape(str(args.model))}</p><table>{''.join(rows)}</table></body></html>"""
    (outroot / "index.html").write_text(page)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("roms", nargs="*")
    ap.add_argument("--collection")
    ap.add_argument("--mappers", default="0,1,2,3,4,7")
    ap.add_argument("--per-mapper", type=int, default=10)
    ap.add_argument("--frames", type=int, default=1200)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--script", default="", help='botones fijos en vez de aleatorios: "120-126:start;300-306:a"')
    ap.add_argument("--prgram-fill", type=lambda x: int(x, 0), default=None,
                    help="contenido inicial de la PRG-RAM/SRAM en los dos lados (p. ej. 0xFF)")
    ap.add_argument("--shots", default="", help="fotogramas extra a capturar, separados por comas")
    ap.add_argument("--clk", type=float, default=50.0)   # clk real: oscilador de 50 MHz
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--model", default=str(HERE / "libn8model.so"))
    ap.add_argument("--out", default=None)
    ap.add_argument("--slot-base", type=int, default=0, help="primera carpeta homes/wN (para lanzar varias tandas a la vez)")
    ap.add_argument("--report-only", help="reclasificar y regenerar el informe de una carpeta existente")
    ap.add_argument("--instancias", action="store_true",
                    help="un modelo por instancia de mapper (simtop.py): ~1,5-2 veces más rápido, mismo resultado")
    ap.add_argument("--clk-auto", action="store_true",
                    help="con --instancias: 50 MHz solo en los mappers que usan clk o conducen el bus; 25 MHz el resto")
    ap.add_argument("--rtl", default=str(HERE.parents[1] / "hdl" / "rtl"), help="carpeta del RTL (con --instancias)")
    ap.add_argument("--rom-list", help="archivo con una ruta de ROM por línea")
    args = ap.parse_args()
    args.model = pathlib.Path(args.model).resolve()
    if args.report_only:
        d = pathlib.Path(args.report_only).resolve()
        results = json.loads((d / "results.json").read_text())
        for r in results:
            if r.get("diff_samples"):
                r["status"] = classify(r["diff_samples"])
        write_report(d, results, args)
        print({s: sum(r["status"] == s for r in results) for s in ("ok", "arranque", "menor", "diverge")})
        return

    roms = list(args.roms)
    if args.rom_list:
        roms += [l.strip() for l in open(args.rom_list, encoding="utf-8") if l.strip()]
    if args.collection:
        roms += pick_from_collection(args.collection, [int(x) for x in args.mappers.split(",")], args.per_mapper)
    todo = []
    for r in roms:
        why = supported(ines(r))
        if why:
            print(f"omitida ({why}): {r}")
        else:
            todo.append(r)
    if not todo:
        sys.exit("no hay ROMs que probar")
    args.models, args.clks = None, None
    if args.instancias:
        args.models, clks = build_instance_models(sorted({ines(r)["mapper"] for r in todo}), args.rtl, args.jobs)
        if args.clk_auto:
            args.clks = clks
            print("clk a 50 MHz:", sorted(m for m, c in clks.items() if c == 50.0), flush=True)
    outroot = (pathlib.Path(args.out) if args.out else HERE / "reports" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S")).resolve()
    outroot.mkdir(parents=True, exist_ok=True)
    print(f"{len(todo)} ROMs, {args.jobs} en paralelo, {args.frames} fotogramas -> {outroot}", flush=True)

    results, slots = [], list(range(args.slot_base, args.slot_base + args.jobs))
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        free = list(slots)
        futs = {}
        pending = list(todo)
        while pending or futs:
            while pending and free:
                s = free.pop()
                rom = pending.pop(0)
                futs[ex.submit(task, s, rom, args, outroot)] = (s, rom)
            done, _ = cf.wait(futs, return_when=cf.FIRST_COMPLETED)
            for f in done:
                s, rom = futs.pop(f)
                free.append(s)
                try:
                    r = f.result()
                except Exception as e:  # noqa: BLE001
                    r = {"rom": rom, "name": os.path.basename(rom), "key": "error", "status": f"excepción: {e}"}
                results.append(r)
                extra = (f"desde fotograma {r.get('first_diff')}, máx {max((v or 0) for v in r.get('diff_samples', {0: 0}).values())} píxeles"
                         if r["status"] in ("diverge", "menor", "arranque") else "")
                print(f"[{len(results)}/{len(todo)}] {r['status']:9s} m{r.get('mapper')} {r['name']} {extra}", flush=True)
                write_report(outroot, results, args)
    ok = sum(r["status"] == "ok" for r in results)
    minor = sum(r["status"] in ("menor", "arranque") for r in results)
    print(f"\n{ok}/{len(results)} idénticos, {minor} con diferencias menores. Informe: {outroot / 'index.html'}")
    sys.exit(0 if ok + minor == len(results) else 1)


if __name__ == "__main__":
    main()
