# Makefile del proyecto de mappers N8
#   make sim     -> simulación con iverilog (todos los testbenches)
#   make build   -> compila con Quartus II 13.0sp1 los RBF aislados out/100.RBF a out/106.RBF
#                   (cada uno con su macro N8_RBF_nnn; ver rtl/n8_top.v y tools/gen_qsf.py)
#   make clean

RTL  := $(wildcard rtl/*.v)
TBS  := tb_nrom tb_fase1 tb_mmc3 tb_fase3 tb_fase3b tb_fase3c tb_sonido tb_fase3d tb_n163 tb_fase4 tb_mmc5 tb_mmc5_ext tb_mmc5_bus tb_snd_mmc5 tb_fase4_rest tb_misc4_direct tb_jy_direct tb_mmc3c_direct tb_fk23c_direct tb_eeprom_direct tb_vrc7_golden tb_pirate_direct
OUT  := out
QDIR := quartus
RBFS := 100 101 102 103 104 105 106

# Quartus: se usa el del PATH si existe; si no, la instalación por defecto en ~/altera
QUARTUS_ROOTDIR ?= $(HOME)/altera/13.0sp1/quartus
QUARTUS_SH := $(shell command -v quartus_sh 2>/dev/null || echo $(QUARTUS_ROOTDIR)/bin/quartus_sh)
export QUARTUS_64BIT := 1

.PHONY: sim build clean mutate

sim: $(addprefix $(OUT)/,$(addsuffix .vvp,$(TBS)))
	python3 -I tools/run_sim.py $(addprefix $(OUT)/,$(addsuffix .vvp,$(TBS)))

$(OUT)/%.vvp: sim/%.v sim/tb_bus.vh $(wildcard sim/*.vh) $(RTL)
	@mkdir -p $(OUT)
	iverilog -g2005 -Wall -I sim -o $@ $< $(RTL)

build: $(addprefix $(OUT)/,$(addsuffix .RBF,$(RBFS)))

# Los dos proyectos se pueden compilar a la vez (make -j2 build): cada uno en su carpeta.
$(OUT)/%.RBF: $(RTL) $(QDIR)/n8_nrom.qsf $(QDIR)/n8_nrom.sdc tools/gen_qsf.py
	python3 -I tools/gen_qsf.py $*
	cd $(QDIR)/rbf$* && $(QUARTUS_SH) --64bit --flow compile n8_$* > build.log 2>&1 || (tail -40 build.log; exit 1)
	@mkdir -p $(OUT)
	python3 -I tools/pad_rbf.py $(QDIR)/rbf$*/output_files/n8_$*.rbf $@
	@grep -E "Total logic elements|Total pins" $(QDIR)/rbf$*/output_files/n8_$*.fit.summary

clean:
	rm -rf $(OUT) $(QDIR)/db $(QDIR)/incremental_db $(QDIR)/output_files $(QDIR)/rbf1*

mutate:
	python3 -I tools/mutate.py
