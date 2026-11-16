# Makefile del OS propio (etapa 1). Salida: build/OS.BIN (32 KiB). Necesita cc65 (ca65, ld65) y Python 3.
B := build

all: $(B)/OS.BIN

$(B)/fuente.chr: herramientas/fuente.py | $(B)
	python3 -I $< $@

$(B)/hola.o: src/hola.s $(B)/fuente.chr | $(B)
	ca65 --bin-include-dir $(B) -o $@ $<

$(B)/OS.BIN: $(B)/hola.o n8os.cfg
	ld65 -C n8os.cfg -o $@ -m $(B)/hola.map $<
	python3 -I herramientas/comprobar_os.py $@

$(B):
	mkdir -p $@

clean:
	rm -rf $(B)

.PHONY: all clean
