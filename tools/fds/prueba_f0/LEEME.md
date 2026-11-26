# Prueba F0 del FDS: escribir la SRAM PRG en modo juego

> ☕ ¿Te resulta útil? Apoya el proyecto en **[Ko-fi](https://ko-fi.com/luiskaycardi)** / Find it useful? Support the
> project on **[Ko-fi](https://ko-fi.com/luiskaycardi)**.

Comprueba en la consola lo único del soporte FDS que depende del hardware y no del código: que la FPGA pueda
**escribir la SRAM PRG en modo juego** (ahí vivirán la BIOS y las caras del disco) y **conducir lecturas en
`$40xx`** (los registros del FDS). Ver [docs/fds-diseno.md](../../../docs/fds-diseno.md).

- `hdl/rtl/mapper_prueba254.v` (retirado al llegar el mapper FDS; está en el commit b4ac387): mapper 254 de prueba,
  en el `254.RBF` de entonces.
  Ventana `$4800-$4FFF` a la SRAM PRG (banco en `$40F0`); en las lecturas de `$4020-$7FFF` (salvo `$4400-$45FF` y la
  ventana) conduce `$A5`, y en `$40F2` el banco. No toca la PRG-RAM.
- `f0.s`: la ROM (`make` aquí → `PRUEBA_F0.nes`, mapper 254). Lee 19 direcciones de `$4020-$7FFF`, escribe y relee
  448 KiB de la SRAM PRG (unos 10 s con la pantalla apagada) y lo enseña: fondo **verde** si la SRAM va bien, **rojo**
  si no, y cada dirección con lo leído (`A5` = llega a la CPU).
- En la SD: `EDFC/MAPS/254.RBF`, `EDFC/MAPROUT.BIN` con 254 → 254 (`hdl/tools/gen_maprout.py`; frente a la
  v0.5.1-beta solo cambia esa entrada) y la ROM.

`simulador.png`: la primera versión de la ROM en Mesen2 con nuestro HDL (tools/n8sim), 790 fotogramas; en el simulador todas las lecturas llegan (no modela el CPLD).

## Resultado en la NES (2026-11-20)

`consola_mapa.jpg`: SRAM PRG **escrita y releída sin errores** (en las tres pasadas del día); lecturas que conduce la
FPGA: **`$4000-$41FF` no llegan** (bus abierto: `$40`/`$41`), **`$4200-$7FFF` sí** (`$A5`). Pasadas anteriores, con la
misma conclusión: `$40F1-$40F6` daban `$40` también con el `/CE` de la SRAM PRG o de la PRG-RAM activo.
