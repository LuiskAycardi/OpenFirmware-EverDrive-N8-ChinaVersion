# Makefile de la ROM de la prueba F0 del FDS. Salida: PRUEBA_F0.nes (necesita cc65 y la fuente del OS).
FUENTE := ../../../os/build/fuente.chr

PRUEBA_F0.nes: f0.s f0.cfg $(FUENTE)
	cp $(FUENTE) fuente.chr
	ca65 -o f0.o f0.s
	ld65 -C f0.cfg -o $@ f0.o
	rm -f f0.o fuente.chr

clean:
	rm -f PRUEBA_F0.nes f0.o fuente.chr
