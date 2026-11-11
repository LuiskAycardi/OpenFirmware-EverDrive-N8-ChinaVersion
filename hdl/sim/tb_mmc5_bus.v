`timescale 1ns/1ps
module tb_mmc5_bus;
`include "tb_bus.vh"
initial begin
 repeat(4)cpu_read(0);
 start_game(5,15,31,0);
 cpu_write(16'h5105,8'hff);cpu_write(16'h5106,8'h52);cpu_write(16'h5107,3);
 ppu_a=14'h2000;ppu_rd_n=0;#160;
 check(ppu_d===8'h52,"MMC5 fill reaches actual PPU pins");
 check(chr_oe_n && ciram_ce_n,"PPU drive excludes SRAM and CIRAM");
 check(chr_ce_n,"NT internal source does not select CHR SRAM");
 ppu_rd_n=1;#60;check(ppu_d===8'hzz,"PPU bus released after /RD rises");
 cpu_read(0);
 ppu_a=14'h23c0;ppu_rd_n=0;#160;check(ppu_d===8'hff,"fill attribute on PPU pins");
 ppu_rd_n=1;#60;
 cpu_write(16'h5104,2);cpu_write(16'h5c00,8'ha5);cpu_read(16'h5c00);
 check(last_cpu_d===8'ha5,"ExRAM read reaches CPU pins");
 cpu_read(16'h8000);check(!dut.cpu_drive,"ROM reads never enable CPU register driver");
 ppu_a=14'h2000;ppu_rd_n=0;#100;
 back_to_menu();check(!dut.ppu_drive,"OS mode releases PPU driver");
 if(errors)$fatal(1,"MMC5 bus failures %0d",errors);
 $display("OK: MMC5 CPU/PPU bus ownership");$finish;
end
endmodule
