# Makefile del OS propio (etapa 1). Salida: build/OS.BIN (32 KiB). Necesita cc65 (ca65, ld65) y Python 3.
B := build
OBJS := $(B)/arranque.o $(B)/principal.o $(B)/sd.o $(B)/fat.o $(B)/lanzar.o $(B)/partida.o

all: $(B)/OS.BIN

$(B)/fuente.chr: herramientas/fuente.py | $(B)
	python3 -I $< $@

$(B)/%.o: src/%.s src/os.inc $(B)/fuente.chr | $(B)
	ca65 -I src --bin-include-dir $(B) -o $@ $<

$(B)/OS.BIN: $(OBJS) n8os.cfg
	ld65 -C n8os.cfg -o $@ -m $(B)/os.map -Ln $(B)/os.lbl $(OBJS)
	python3 -I herramientas/comprobar_os.py $@

$(B):
	mkdir -p $@

clean:
	rm -rf $(B)

.PHONY: all clean
