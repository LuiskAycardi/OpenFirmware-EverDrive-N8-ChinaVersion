#!/usr/bin/env python3
"""simtop.py — n8_top reducido a una sola instancia de mapper, solo para el banco de pruebas.

En Verilator el coste de cada evaluación crece con todo lo que lleva el RBF (todas las instancias se
recalculan en cada flanco de clk aunque el juego use una sola). Para el banco basta la instancia del
mapper del juego: las demás no influyen en sus salidas (el selector del top solo deja pasar la elegida).
Este script copia hdl/rtl/n8_top.v cambiando las otras instancias por buses a cero; el selector, las
máscaras, la interfaz del OS, las 4 pantallas y el resto del top quedan igual.

  simtop.py map               -> {mapper: bus} (JSON) según el selector del top
  simtop.py gen BUS SALIDA.v  -> top con solo la instancia BUS (p. ej. bus_004)
"""
import json
import pathlib
import re
import sys

TOP = pathlib.Path(__file__).resolve().parents[2] / "hdl" / "rtl" / "n8_top.v"
INST = re.compile(r"^(\s*)`(N8_MAPPER\w*)\((\w+),\s*(\w+),\s*(bus_\w+)((?:,\s*\w+)*)\)(.*)$")


def mapper_table(text):
    """Etiquetas del case del selector principal (g = bus_xxx)."""
    body = text.split("case (mapper_id)", 1)[1].split("endcase", 1)[0]
    table, pending = {}, []
    for line in body.splitlines():
        line = line.split("//", 1)[0]
        if line.strip().startswith("`"):
            continue
        pending += [int(n) for n in re.findall(r"8'd(\d+)", line)]
        m = re.search(r"g\s*=\s*(bus_\w+)", line)
        if m:
            for n in pending:
                table[n] = m.group(1)
            pending = []
    return table


def generate(text, keep):
    out, found = [], False
    for line in text.splitlines():
        m = INST.match(line)
        if not m:
            out.append(line)
            continue
        ind, macro, _mod, _inst, bus, extra, _rest = m.groups()
        if bus == keep:
            out.append(line)
            found = True
            continue
        extras = [e.strip() for e in extra.split(",") if e.strip()]
        decl = [f"wire [26:0] {bus} = 27'd0;"]
        if macro in ("N8_MAPPER_D", "N8_MAPPER_XD", "N8_MAPPER_XDP"):
            decl += [f"wire [7:0] {extras[0]} = 8'd0;", f"wire [7:0] {extras[1]} = 8'd0;"]
        elif macro == "N8_MAPPER_S":
            decl += [f"wire [9:0] {extras[0]} = 10'd0;"]
        elif macro in ("N8_MAPPER_DS", "N8_MAPPER_M5"):
            decl += [f"wire [7:0] {extras[0]} = 8'd0;", f"wire [7:0] {extras[1]} = 8'd0;",
                     f"wire [9:0] {extras[2]} = 10'd0;"]
        if macro == "N8_MAPPER_XDP":
            decl += [f"wire [7:0] {extras[2]} = 8'd0;", f"wire [7:0] {extras[3]} = 8'd0;"]
        if macro == "N8_MAPPER_M5":
            decl += [f"wire [7:0] {extras[3]} = 8'd0;", f"wire [7:0] {extras[4]} = 8'd0;"]
        out.append(ind + " ".join(decl) + "   // (banco: instancia quitada)")
    if not found and keep != "bus_000":
        sys.exit(f"no hay ninguna instancia con {keep}")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    a = sys.argv[1:]
    text = TOP.read_text()
    if a[:1] == ["map"]:
        print(json.dumps(mapper_table(text)))
    elif len(a) == 3 and a[0] == "gen":
        pathlib.Path(a[2]).write_text(generate(text, a[1]))
    else:
        sys.exit(__doc__)
