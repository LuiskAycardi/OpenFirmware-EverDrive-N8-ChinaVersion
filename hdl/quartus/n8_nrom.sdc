# Restricciones de tiempo. clk = oscilador X1 de 50,000 MHz (visto en el N8 de Famicom y en el de NES, 2026-11-05)
create_clock -name clk -period 20.000 [get_ports clk]
create_clock -name m2  -period 558.000 [get_ports cpu_m2_gclk]
set_clock_groups -asynchronous -group {clk} -group {m2}
# PPU /RD ya no es un reloj: desde el 2026-11-05 los latches del MMC2/MMC4 van con clk (ver docs/hardware-fpga.md).
