# Banco de pruebas N8 en Mesen2: modelo Verilator de hdl/rtl + Mesen2 parcheado.
#   make model    -> libn8model.so (nuestro Verilog en C++; se recompila en segundos)
#   make mesen    -> Mesen2 con el mapper puente (solo hace falta una vez)
#   make all      -> las dos cosas
# El puente carga el modelo en tiempo de ejecución (N8_MODEL=ruta/libn8model.so).

HDL    := $(realpath ../../hdl)
MESEN  := $(realpath ../mesen2)
RTL    ?= $(wildcard $(HDL)/rtl/*.v)
VINC   := /usr/share/verilator/include
VFLAGS := --cc -O3 --top-module n8_sim_top -Wno-fatal -Wno-lint -Wno-style $(VDEF_RBF)
# mismas definiciones que usa Verilator para su runtime (si no, VerilatedContext cambia de forma)
VDEFS  := -DVERILATOR=1 -DVM_COVERAGE=0 -DVM_SC=0 -DVM_TIMING=0 -DVM_TRACE=0 -DVM_TRACE_FST=0 \
          -DVM_TRACE_VCD=0 -DVM_TRACE_SAIF=0 -DVM_VPI=0 -faligned-new
CXXOPT := -fPIC -O3 -march=native $(VDEFS)
CXXM   ?= clang++
OBJ    ?= obj_dir
LIB    ?= libn8model.so

.PHONY: all model mesen clean cov

# Modelo con cobertura de líneas (ramas if/case de cada módulo) para elegir juegos por mapper (cobertura.py):
#   make cov -> libn8model_cov.so; con N8_COV=archivo.dat escribe los contadores al terminar
cov:
	$(MAKE) OBJ=obj_cov LIB=libn8model_cov.so VFLAGS="$(VFLAGS) --coverage-line" \
	    VDEFS="$(subst -DVM_COVERAGE=0,-DVM_COVERAGE=1,$(VDEFS))" COVLIB="$(VINC)/verilated_cov.cpp" libn8model_cov.so


all: model mesen

model: $(LIB)

$(LIB) libn8model_cov.so: n8_sim_top.v n8model.cpp n8model.h $(RTL)
	rm -rf $(OBJ)
	verilator $(VFLAGS) -Mdir $(OBJ) n8_sim_top.v $(RTL)
	# Una sola unidad de compilación con clang (2026-11-05): ~25 % más rápido que la librería por partes con g++.
	for f in $(OBJ)/Vn8_sim_top*.cpp; do echo "#include \"$$f\""; done > $(OBJ)/todo.cpp
	$(CXXM) $(CXXOPT) -shared -o $@.tmp -I. -I$(OBJ) -I$(VINC) -I$(VINC)/vltstd n8model.cpp \
	    $(OBJ)/todo.cpp $(VINC)/verilated.cpp $(VINC)/verilated_threads.cpp $(COVLIB) -latomic -lpthread
	mv -f $@.tmp $@

mesen:
	touch N8FpgaMapper.cpp $(MESEN)/Core/NES/MapperFactory.cpp   # el makefile de Mesen2 no sigue cabeceras
	$(MAKE) -C $(MESEN) -j8 N8SIM=$(CURDIR)
	# copiar y renombrar (atómico): las ejecuciones en marcha conservan la versión anterior
	cp $(MESEN)/bin/linux-x64/Release/linux-x64/publish/Mesen run/Mesen.new && mv -f run/Mesen.new run/Mesen
	cp $(MESEN)/bin/linux-x64/Release/MesenCore.so run/MesenCore.so.new && mv -f run/MesenCore.so.new run/MesenCore.so

clean:
	rm -rf obj_dir libn8model.so
