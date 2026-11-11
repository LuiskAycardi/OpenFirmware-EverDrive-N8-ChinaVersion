#!/usr/bin/env python3
"""Genera el proyecto de Quartus de un RBF a partir de la plantilla quartus/n8_nrom.qsf.

  gen_qsf.py NNN      -> quartus/rbfNNN/n8_NNN.qpf y n8_NNN.qsf

La plantilla tiene el dispositivo, las opciones y los pines. Aquí se añaden:
  - todos los archivos de rtl/ (así un módulo nuevo no hay que añadirlo a mano),
  - la macro N8_RBF_NNN, que elige qué mappers entran en este RBF (ver n8_top.v),
  - el SDC común y el pull-up débil de ppu_d (bus abierto de la PPU = $FF, mappers 93 y 185).
"""
import pathlib
import sys

hdl = pathlib.Path(__file__).resolve().parent.parent
rbf = sys.argv[1]
if not (rbf.isdigit() and len(rbf) == 3):
    sys.exit("uso: gen_qsf.py NNN (p. ej. 100)")

tpl = (hdl / "quartus" / "n8_nrom.qsf").read_text().splitlines()
keep = [l for l in tpl
        if "-name VERILOG_FILE" not in l and "-name SDC_FILE" not in l
        and "-name VERILOG_MACRO" not in l and "WEAK_PULL_UP_RESISTOR" not in l]

out = [f"# Generado por tools/gen_qsf.py desde n8_nrom.qsf: RBF {rbf}. No editar a mano."]
out += keep
out += [f"set_global_assignment -name VERILOG_FILE ../../rtl/{f.name}"
        for f in sorted((hdl / "rtl").glob("*.v"))]
out += [f'set_global_assignment -name VERILOG_MACRO "N8_RBF_{rbf}=1"',
        "set_global_assignment -name SDC_FILE ../n8_nrom.sdc"]
out += [f"set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to ppu_d[{i}]" for i in range(8)]

d = hdl / "quartus" / f"rbf{rbf}"
d.mkdir(exist_ok=True)
(d / f"n8_{rbf}.qsf").write_text("\n".join(out) + "\n")
(d / f"n8_{rbf}.qpf").write_text(f'QUARTUS_VERSION = "13.0"\nPROJECT_REVISION = "n8_{rbf}"\n')
print(f"{d}/n8_{rbf}.qsf")
