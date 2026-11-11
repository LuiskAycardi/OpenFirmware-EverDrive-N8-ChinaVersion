#!/usr/bin/env python3
"""fuzz.py — Compara mappers con Mesen2 usando ROMs sintéticas (romgen.py), sin necesidad de juegos.

Para cada mapper genera una ROM que escribe valores pseudoaleatorios en los registros y anota tras cada
escritura qué KB de PRG y de CHR se ve en cada ventana y el mirroring. La ejecuta con el mapper de Mesen2 y con
nuestro Verilog (modelo por instancia, como difftest.py --instancias --clk-auto) y compara paso a paso.

  python3 -I fuzz/fuzz.py 0 1 2 3 4 --pasos 600 --jobs 6
  python3 -I fuzz/fuzz.py 13 --chr-ram          # mapper con CHR-RAM
Resultado: reports/fuzz-<fecha>/resumen.txt y, por mapper, los dos registros y el primer paso distinto.
"""
import argparse
import concurrent.futures as cf
import datetime
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
N8SIM = HERE.parent
sys.path.insert(0, str(N8SIM))
sys.path.insert(0, str(HERE))
import difftest  # noqa: E402
import romgen  # noqa: E402

LUA = HERE / "fuzz.lua"

# Sin el bit de pila en la cabecera: con él Mesen2 crea RAM de partidas en lugar de la RAM de trabajo que el mapper
# coloca en sitios propios (103: $B800-$D7FF).
# 176 (FK23C): with the battery bit Mesen2 maps 8 KiB save RAM for the banked WRAM config but
# 32 KiB work RAM otherwise; without it both use the 32 KiB work RAM the N8 implements.
NO_BATTERY = {56, 103, 176, 178}

# Zonas que no se comparan en cada mapper (además de las de --ignorar). "6000": la placa no tiene PRG-RAM y
# Mesen2 se la pone igual (con el bit de pila de la cabecera de la ROM sintética).
# NO_RAM MMC3 boards (115/248): Mesen2 still maps WRAM at $6000 from the synthetic
# header, the real board has none — same case as the other no-PRG-RAM boards below.
IGNORAR = {m: ("6000",) for m in (116,59,114,215,35,115,248,111,234,91,222,220,0, 2, 3, 7, 11, 13, 28, 30, 31, 60, 77, 96, 142, 164, 171, 175, 188, 221)}

# CHR-RAM mayor de 8 KB: cabecera NES 2.0 con el tamaño (con iNES 1 Mesen2 da 8 KB y los bancos se repiten).
REFERENCE_MAPPER = {220:4,248:115}  # Explicit historical N8 alias; not a native Mesen mapper220.

CHR_RAM_KB = {111:32,28: 32, 30: 32, 96: 32, 157: 8}

# Placas reales distintas con el mismo número: la ROM sintética se genera como NES 2.0 con el submapper de cada
# placa (así Mesen2 la emula como esa placa) y solo escribe en el rango que esa placa decodifica.
# 16: LZ93D50 + EEPROM 24C02 (submapper 5, $8000-$FFFF) y FCG-1/2 (submapper 4, $6000-$7FFF). El N8 no recibe
# el submapper: aplica la semántica de cada placa según el rango de la escritura.
BOARD_VARIANTS = {
    16: {"_lz": dict(submapper=5, nvram_bytes=256, wr_only="hi"),
         "_fcg": dict(submapper=4, wr_only="lo")},
    # 157 (Datach): con la 24C01 del cartucho (Battle Rush: pila + 128 bytes de PRG-NVRAM) y sin ella
    157: {"_br": dict(submapper=0, nvram_bytes=128, wr_only="hi"),
          "_base": dict(submapper=0, wr_only="hi", battery=False)},
}
PRG_RAM_KB = {}

# Tamaños máximos reales de cada placa (PRG KB, CHR KB). Con más, Mesen2 y el OS ven otra placa (p. ej. el
# banco "último" fijo). Por defecto 512/512.
SIZES = {
    35:(512,512),90:(512,512),211:(512,512),99:(32,16),111:(512,0),234:(512,512),165:(512,128),176:(512,256),219:(512,512),248:(512,512),
    56:(256,256),91:(128,256),105:(256,0),117:(512,256),222:(128,128),220:(512,256),
    5: (256, 256),  # MMC5 directed bank-register profile
    0: (32, 8), 2: (256, 8), 3: (32, 32), 7: (256, 8), 11: (128, 128), 13: (32, 16), 34: (128, 8),
    66: (128, 32), 70: (128, 128), 71: (256, 8), 79: (64, 64), 87: (32, 32), 94: (128, 8), 97: (256, 8),
    140: (128, 128), 148: (64, 64), 152: (128, 128), 180: (128, 8), 184: (32, 32), 185: (32, 8),
    232: (256, 8), 9: (128, 128), 10: (256, 128), 16: (256, 256), 159: (256, 256), 153: (512, 0), 157: (256, 0), 209: (128, 512), 194: (256, 256), 195: (256, 256), 114: (256, 256), 121: (256, 512), 215: (256, 256), 59: (128, 64), 83: (128, 256), 253: (256, 512), 116: (256, 256), 192: (512, 256), 18: (512, 256), 33: (256, 256),
    64: (256, 256), 69: (512, 256), 206: (128, 64), 76: (128, 128), 88: (128, 128), 95: (128, 32),
    154: (128, 128), 1: (512, 128), 4: (512, 256), 21: (256, 256), 22: (256, 256), 23: (256, 256),
    25: (256, 256), 74: (512, 256), 191: (512, 256), 199: (512, 256),
    # fase 4 (CHR 0 = CHR-RAM)
    13: (32, 0), 15: (512, 0), 38: (128, 32), 57: (128, 128), 58: (128, 64), 213: (128, 64), 61: (512, 8),
    94: (128, 0), 97: (256, 0), 101: (32, 512), 107: (128, 64), 145: (32, 16), 149: (32, 16), 177: (512, 0),
    200: (128, 64), 201: (128, 64), 202: (128, 64), 203: (512, 32), 212: (128, 64), 214: (64, 32), 216: (64, 64),
    227: (512, 0), 229: (512, 256), 231: (512, 0), 240: (512, 128), 242: (512, 0), 244: (128, 64), 246: (512, 512),
    144: (128, 128), 151: (128, 128),
    27: (256, 256), 183: (256, 256), 252: (512, 256),
    40: (64, 8), 42: (128, 128), 50: (128, 8), 73: (128, 0), 106: (256, 128), 142: (128, 0),
    28: (512, 0), 30: (512, 0), 31: (512, 0), 51: (512, 0), 60: (64, 32), 77: (128, 32), 96: (128, 0),
    103: (128, 0), 108: (128, 64), 164: (512, 0), 168: (64, 0), 171: (32, 128), 175: (256, 128), 178: (512, 0),
    188: (256, 0), 190: (256, 128), 221: (512, 0),
}


def campos(sample_hex):
    b = bytes.fromhex(sample_hex)
    prg = [b[2 * i] | (b[2 * i + 1] << 8) for i in range(40)]          # $6000 + i KB
    chr_ = [b[80 + 2 * i] | (b[81 + 2 * i] << 8) for i in range(8)]
    nt = list(b[96:100])
    irq = list(b[100:105]) if len(b) >= 105 else [0] * 5
    return prg, chr_, nt, irq


def describe(ref_line, n8_line):
    """Qué ventana difiere en un paso."""
    r, n = ref_line.split(), n8_line.split()
    if len(r) < 4 or len(n) < 4:
        return f"líneas distintas: {ref_line.strip()!r} / {n8_line.strip()!r}"
    rp, rc, rn, ri = campos(r[3])
    np_, nc, nn, ni = campos(n[3])
    out = []
    for i in range(40):
        if rp[i] != np_[i]:
            out.append(f"PRG ${0x6000 + i * 0x400:04X}: Mesen {rp[i]:03X} / N8 {np_[i]:03X}")
    for i in range(8):
        if rc[i] != nc[i]:
            out.append(f"CHR ${i * 0x400:04X}: Mesen {rc[i]:04X} / N8 {nc[i]:04X}")
    if rn != nn:
        out.append(f"nametables: Mesen {' '.join('%02X' % x for x in rn)} / N8 {' '.join('%02X' % x for x in nn)}")
    if ri != ni:
        def irqs(v):
            return f"IRQ en ${v[2]:02X}{v[1]:02X} X={v[3]:02X} Y={v[4]:02X}" if v[0] else "sin IRQ"
        out.append(f"Mesen {irqs(ri)} / N8 {irqs(ni)}")
    return "; ".join(out[:6]) + (f" (+{len(out) - 6})" if len(out) > 6 else "")


def run(home, rom, mode, outfile, model, clk, frames):
    for sub in ("Saves", "SaveStates"):
        d = home / sub
        if d.is_dir() and d.parent == home:
            import shutil
            shutil.rmtree(d)
    env = dict(os.environ)
    env.update({"N8_FUZZ_OUT": str(outfile), "N8_FRAMES": str(frames)})
    if mode == "n8":
        env.update({"N8_FPGA": "1", "N8_MODEL": str(model), "N8_CLK_MHZ": str(clk)})
    else:
        env.pop("N8_FPGA", None)
        env.pop("N8_MODEL", None)
    timeout = frames * 2 + 120
    with open(str(outfile) + ".log", "w") as log:
        completed = subprocess.run([str(home / "Mesen"), "--testrunner", f"--timeout={timeout}", str(LUA), str(rom)],
                       cwd=home, env=env, stdout=log, stderr=subprocess.STDOUT)
        log.write(f"\n[runner] exit code: {completed.returncode}\n")


def mask_line(line, ignore):
    """Quita de la muestra las zonas que no se comparan (decisiones conocidas, p. ej. PRG-RAM siempre activa)."""
    p = line.split()
    if len(p) < 4 or not ignore:
        return line
    b = bytearray.fromhex(p[3])
    if "6000" in ignore:
        b[0:16] = bytes(16)
    if "chr" in ignore:
        b[80:96] = bytes(16)
    if "nt" in ignore:
        b[96:100] = bytes(4)
    if "irq" in ignore:
        b[100:105] = bytes(len(b[100:105]))
    return " ".join(p[:3] + [b.hex().upper()])


def mask_open_bus(ref_line, n8_line):
    """Mesen2 deja sin mapear los bancos que el juego aún no ha escrito (bus abierto: los dos bytes valen la
    página de la dirección, p. ej. $8080). En el hardware el estado al encender es indefinido: esas ventanas
    no se comparan mientras Mesen2 las tenga así."""
    r, n = ref_line.split(), n8_line.split()
    if len(r) < 4 or len(n) < 4:
        return ref_line, n8_line
    rb, nb = bytearray.fromhex(r[3]), bytearray.fromhex(n[3])
    for i in range(40):
        page = (0x6000 + i * 0x400) >> 8
        if rb[2 * i] == page and rb[2 * i + 1] == page:
            nb[2 * i] = rb[2 * i]; nb[2 * i + 1] = rb[2 * i + 1]
    for i in range(8):                       # CHR sin mapear en Mesen2: lee 00 01 (bus abierto de la PPU)
        j = 80 + 2 * i
        if rb[j] == 0x00 and rb[j + 1] == 0x01:
            nb[j] = 0x00; nb[j + 1] = 0x01
    return ref_line, " ".join(n[:3] + [nb.hex().upper()])


def compare(ref_file, n8_file, ignore=()):
    ref = ref_file.read_text().splitlines() if ref_file.exists() else []
    n8 = n8_file.read_text().splitlines() if n8_file.exists() else []
    ref = [mask_line(x, ignore) for x in ref]
    n8 = [mask_line(x, ignore) for x in n8]
    n8 = [mask_open_bus(a, b)[1] if a not in ("FIN", "LIMITE") and b not in ("FIN", "LIMITE") else b
          for a, b in zip(ref, n8)] + n8[len(ref):]
    if not ref or ref[-1] != "FIN":
        return "error_ref", f"Mesen2 no terminó ({len(ref)} líneas)", None
    if not n8 or n8[-1] != "FIN":
        return "error_n8", f"N8 no terminó ({len(n8)} líneas)", None
    for i, (a, b) in enumerate(zip(ref, n8)):
        if a != b:
            ndiff = sum(1 for x, y in zip(ref, n8) if x != y)
            return "distinto", f"paso {i}: escritura ${a.split()[1]}={a.split()[2]} -> {describe(a, b)} ({ndiff} pasos distintos)", i
    if len(ref) != len(n8):
        return "distinto", f"longitud {len(ref)} / {len(n8)}", None
    return "igual", f"{len(ref) - 1} pasos idénticos", None


def task(slot, mapper, variant, args, outroot, models, clks):
    home = difftest.prepare_home(slot)
    d = outroot / f"m{mapper:03d}{variant}"
    d.mkdir(parents=True, exist_ok=True)
    rom = d / f"fuzz_{mapper:03d}{variant}.nes"
    prg_kb, chr_kb = SIZES.get(mapper, (args.prg_kb, args.chr_kb))
    chr_ram = (variant == "_ram") or chr_kb == 0
    board = dict(BOARD_VARIANTS.get(mapper, {}).get(variant, {}))
    battery = board.pop("battery", mapper not in NO_BATTERY)
    rom.write_bytes(romgen.build(mapper, args.pasos, chr_ram=chr_ram, seed=args.semilla,
                                 prg_kb=prg_kb, chr_kb=chr_kb or 8, battery=battery,
                                 chr_ram_kb=CHR_RAM_KB.get(mapper), prg_ram_kb=PRG_RAM_KB.get(mapper), **board))
    frames = 60 + args.pasos // 6
    ref_rom=rom
    if mapper in REFERENCE_MAPPER:
        raw=bytearray(rom.read_bytes());ref_mapper=REFERENCE_MAPPER[mapper]
        raw[6]=(raw[6]&15)|((ref_mapper&15)<<4);raw[7]=(raw[7]&15)|(ref_mapper&240)
        ref_rom=d/f"reference_mapper_{ref_mapper:03d}.nes";ref_rom.write_bytes(raw)
    run(home, ref_rom, "ref", d / "ref.txt", None, None, frames)
    run(home, rom, "n8", d / "n8.txt", models[mapper], clks[mapper], frames)
    st, msg, step = compare(d / "ref.txt", d / "n8.txt", tuple(args.ignorar) + IGNORAR.get(mapper, ()))
    return mapper, variant, st, msg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mappers", nargs="+", type=int)
    ap.add_argument("--pasos", type=int, default=600)
    ap.add_argument("--semilla", type=lambda x: int(x, 0), default=None)
    ap.add_argument("--chr-ram", action="store_true", help="también la variante con CHR-RAM")
    ap.add_argument("--solo-chr-ram", action="store_true")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--slot-base", type=int, default=50)
    ap.add_argument("--prg-kb", type=int, default=512)
    ap.add_argument("--chr-kb", type=int, default=512)
    ap.add_argument("--rtl", default=str(N8SIM.parents[1] / "hdl" / "rtl"))
    ap.add_argument("--out")
    ap.add_argument("--ignorar", default="", help="zonas sin comparar: 6000,chr,nt,irq (p. ej. PRG-RAM siempre activa)")
    args = ap.parse_args()
    args.ignorar = tuple(x for x in args.ignorar.split(",") if x)
    outroot = pathlib.Path(args.out) if args.out else N8SIM / "reports" / ("fuzz-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    outroot = outroot.resolve()
    outroot.mkdir(parents=True, exist_ok=True)
    models, clks = difftest.build_instance_models(sorted(set(args.mappers)), args.rtl, args.jobs)
    variants = [""] if not args.solo_chr_ram else []
    if args.chr_ram or args.solo_chr_ram:
        variants.append("_ram")
    todo = [(m, v) for m in args.mappers for v in (list(BOARD_VARIANTS[m]) if m in BOARD_VARIANTS else variants)]
    results = []
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        free = list(range(args.slot_base, args.slot_base + args.jobs))
        futs = {}
        pending = list(todo)
        while pending or futs:
            while pending and free:
                s = free.pop()
                m, v = pending.pop(0)
                futs[ex.submit(task, s, m, v, args, outroot, models, clks)] = s
            done, _ = cf.wait(futs, return_when=cf.FIRST_COMPLETED)
            for f in done:
                free.append(futs.pop(f))
                m, v, st, msg = f.result()
                line = f"m{m:03d}{v:4s} {st:9s} {msg}"
                print(line, flush=True)
                results.append(line)
    results.sort()
    (outroot / "resumen.txt").write_text("\n".join(results) + "\n")
    print(f"\n{sum('igual' in r for r in results)}/{len(results)} iguales -> {outroot / 'resumen.txt'}")

    if any(" igual " not in r for r in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
