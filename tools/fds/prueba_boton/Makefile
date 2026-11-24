# Makefile del programa del disco de prueba del cambio de cara a mano (necesita cc65). La imagen .fds la hace
# hacer_disco.py (copia el archivo de licencia de un disco del usuario).
programa.bin vectores.bin: boton.s boton.cfg
	ca65 -o boton.o boton.s
	ld65 -C boton.cfg boton.o
	rm -f boton.o

clean:
	rm -f programa.bin vectores.bin boton.o BOTON.fds
