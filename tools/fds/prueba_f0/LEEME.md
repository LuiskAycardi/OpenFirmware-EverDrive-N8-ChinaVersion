# Prueba F0 del FDS: escribir la SRAM PRG en modo juego

Comprueba en la consola lo único del soporte FDS que depende del hardware y no del código: que la FPGA pueda
**escribir la SRAM PRG en modo juego** (ahí vivirán la BIOS y las caras del disco) y **conducir lecturas en
`$40xx`** (los registros del FDS). Ver [docs/fds-diseno.md](../../../docs/fds-diseno.md).

- `hdl/rtl/mapper_prueba254.v`: mapper 254 de prueba, solo en el `254.RBF` (`make -C hdl out/254.RBF`).
  Ventana `$4800-$4FFF` a la SRAM PRG (banco en `$40F0`), `$40F1` = `$A5`, `$40F2` = el banco. No toca la PRG-RAM.
- `f0.s`: la ROM (`make` aquí → `PRUEBA_F0.nes`, mapper 254). Tarda unos 10 s con la pantalla apagada y luego enseña
  una línea por prueba: fondo **verde** si todo va bien, **rojo** si algo falla (con el número de errores en hex).
- En la SD: `EDFC/MAPS/254.RBF`, `EDFC/MAPROUT.BIN` con 254 → 254 (`hdl/tools/gen_maprout.py`; frente a la
  v0.5.1-beta solo cambia esa entrada) y la ROM.

`simulador.png`: el resultado en Mesen2 con nuestro HDL (tools/n8sim), 790 fotogramas.
