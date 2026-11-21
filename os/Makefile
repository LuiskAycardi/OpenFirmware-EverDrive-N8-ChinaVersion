# Makefile del OS propio (etapa 1). Salida: build/OS.BIN (32 KiB). Necesita cc65 (ca65, ld65) y Python 3.
B := build
OBJS := $(B)/arranque.o $(B)/principal.o $(B)/sd.o $(B)/fat.o $(B)/lanzar.o $(B)/partida.o $(B)/orden.o $(B)/banco.o $(B)/fds.o

all: $(B)/OS.BIN $(B)/fds_parche.bin

$(B)/fuente.chr: herramientas/fuente.py | $(B)
	python3 -I $< $@

$(B)/%.o: src/%.s src/os.inc src/fds_tablas.inc $(B)/fuente.chr | $(B)
	ca65 -I src --bin-include-dir $(B) -o $@ $<

# Bloque del parche FDS (corre en $5000): lo incluye fds.s y lo usa tools/fds/probar_parche.py.
$(B)/fds_parche.bin: src/fds_parche.s fds_parche.cfg | $(B)
	ca65 -o $(B)/fds_parche.o src/fds_parche.s
	ld65 -C fds_parche.cfg -o $@ -Ln $(B)/fds_parche.lbl $(B)/fds_parche.o

$(B)/OS.BIN: $(OBJS) n8os.cfg
	ld65 -C n8os.cfg -o $@ -m $(B)/os.map -Ln $(B)/os.lbl $(OBJS)
	python3 -I herramientas/comprobar_os.py $@

$(B):
	mkdir -p $@

clean:
	rm -rf $(B)

.PHONY: all clean
