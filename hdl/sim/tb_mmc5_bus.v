`timescale 1ns/1ps
module tb_mmc5_bus;
`include "tb_bus.vh"
initial begin
 repeat(4)cpu_read(0);
 start_game(5,15,31,0);
 cpu_write(16'h5105,8'hff);cpu_write(16'h5106,8'h52);cpu_write(16'h5107,3);
 // Transceptor de datos de la PPU (pin ppu_ex = ciram_en): con A13=1 solo conecta la FPGA con la PPU si la CIRAM
 // está apagada. Tiene que depender solo de la dirección, ya antes de que baje /RD (lección del modo imagen del OS).
 ppu_a=14'h2000;#60;check(ppu_ex===1'b0,"fill: transceptor conectado por direccion, antes de /RD");
 ppu_rd_n=0;#160;check(ppu_ex===1'b0,"fill: transceptor conectado durante la lectura");
 check(ppu_d===8'h52,"MMC5 fill reaches actual PPU pins");
 check(chr_oe_n && ciram_ce_n,"PPU drive excludes SRAM and CIRAM");
 check(chr_ce_n,"NT internal source does not select CHR SRAM");
 ppu_rd_n=1;#60;check(ppu_d===8'hzz,"PPU bus released after /RD rises");
 cpu_read(0);
 ppu_a=14'h23c0;#60;check(ppu_ex===1'b0,"fill: atributo con el transceptor conectado antes de /RD");
 ppu_rd_n=0;#160;check(ppu_d===8'hff,"fill attribute on PPU pins");
 ppu_rd_n=1;#60;
 // Nametable en la CIRAM ($5105=0): el transceptor queda como siempre (ppu_ex=1) y la FPGA no conduce.
 cpu_write(16'h5105,8'h00);cpu_read(0);
 ppu_a=14'h2400;ppu_rd_n=0;#160;
 check(ppu_ex===1'b1 && !ciram_ce_n && !dut.ppu_drive && ppu_d===8'hzz,"CIRAM: nametable de la consola, la FPGA no conduce");
 ppu_rd_n=1;#60;
 // ExRAM como nametable ($5104=0, $5105=$AA): lectura y escritura de la PPU sin la CIRAM y con el transceptor.
 cpu_write(16'h5104,2);cpu_write(16'h5c05,8'h3c);cpu_write(16'h5104,0);cpu_write(16'h5105,8'haa);cpu_read(0);
 ppu_a=14'h2005;#60;check(ppu_ex===1'b0,"ExRAM nametable: transceptor conectado antes de /RD");
 ppu_rd_n=0;#160;check(ppu_d===8'h3c && ciram_ce_n && ppu_ex===1'b0,"ExRAM nametable: dato en los pines de la PPU");
 ppu_rd_n=1;#60;
 ppu_a=14'h2006;#20;ppu_wr_n=0;#100;check(ppu_ex===1'b0 && ciram_ce_n,"ExRAM nametable: la escritura de la PPU no va a la CIRAM");
 ppu_wr_n=1;#60;
 cpu_write(16'h5104,8'h00);cpu_write(16'h5105,8'hff);
 cpu_write(16'h5104,2);cpu_write(16'h5c00,8'ha5);cpu_read(16'h5c00);
 check(last_cpu_d===8'ha5,"ExRAM read reaches CPU pins");
 cpu_read(16'h8000);check(!dut.cpu_drive,"ROM reads never enable CPU register driver");
 ppu_a=14'h2000;ppu_rd_n=0;#100;
 back_to_menu();check(!dut.ppu_drive,"OS mode releases PPU driver");
 if(errors)$fatal(1,"MMC5 bus failures %0d",errors);
 $display("OK: MMC5 CPU/PPU bus ownership");$finish;
end
endmodule
