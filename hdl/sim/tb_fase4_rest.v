`timescale 1ns/1ps
module tb_fase4_rest;
`include "tb_bus.vh"
localparam P512=5'h1f,C512=8'h3f;
integer i,j;
task serial105(input[15:0] address,input[4:0] value);
begin for(j=0;j<5;j=j+1)begin cpu_write(address,{7'd0,value[j]});cpu_read(0);end end
endtask
task line;
begin ppu_a=0;repeat(5)cpu_read(0);ppu_a=14'h1000;#160;cpu_read(0);end
endtask
initial begin
 repeat(4)cpu_read(0);
 start_game(56,P512,C512,0);
 cpu_write(16'hf46c,9);expect_prg(16'h8000,19'h12000,"56 power-on selector is PRG0");
 cpu_write(16'he000,1);cpu_write(16'hf000,3);
 expect_prg(16'h8000,19'h06000,"56 PRG nibble bank");
 cpu_write(16'he000,0);cpu_write(16'hf000,8'h10);
 expect_prg(16'h8000,19'h26000,"56 independent high PRG bit");
 cpu_write(16'hfc02,5);expect_chr(14'h0800,19'h01400,"56 1KB CHR");
 cpu_write(16'hf800,1);expect_a10(14'h2400,1,"56 vertical mirroring");
 cpu_write(16'he000,4);cpu_write(16'hf000,3);
 cpu_read(16'h6000);check(last_ram_ce && !last_prg_ce,"56 starts with WRAM at6000");
 cpu_write(16'he000,5);cpu_write(16'hf000,4);
 expect_prg(16'h6000,19'h06000,"56 ROM enabled at6000");
 cpu_write(16'h8000,14);cpu_write(16'h9000,15);cpu_write(16'ha000,15);cpu_write(16'hb000,15);
 cpu_write(16'hc000,2);check(irq_n===0,"56 one-shot counter terminal");
 cpu_write(16'hd000,0);check(irq_n===1,"56 IRQ acknowledgement");back_to_menu;

 start_game(117,P512,C512,1);
 expect_prg(16'h8000,19'h78000,"117 initial last32KB");
 cpu_write(16'h8001,5);expect_prg(16'ha000,19'h0a000,"117 independent PRG");
 cpu_write(16'h8011,9);expect_prg(16'ha000,19'h0a000,"117 exact register decoding");
 cpu_write(16'ha006,7);expect_chr(14'h1800,19'h01c00,"117 CHR1KB");
 cpu_write(16'hc001,3);cpu_write(16'hc003,0);cpu_write(16'he000,1);
 line;check(irq_n===1,"117 counter step1");line;check(irq_n===1,"117 counter step2");
 line;check(irq_n===0,"117 IRQ on third scanline");
 cpu_write(16'hc002,0);#100;check(irq_n===1,"117 IRQ ack");
 line;check(irq_n===1,"117 one shot requires rearm");back_to_menu;

 start_game(222,P512,C512,1);
 cpu_write(16'h8120,5);expect_prg(16'h8000,19'h0a000,"222 F003 aliases");
 cpu_write(16'hc002,9);expect_chr(14'h0c00,19'h02400,"222 CHR register ordering");
 expect_prg(16'hc000,19'h7c000,"222 fixed penultimate bank");
 cpu_write(16'hf000,238);line;check(irq_n===1,"222 count239");line;check(irq_n===0,"222 threshold240");
 cpu_write(16'hf000,0);#100;check(irq_n===1,"222 zero stops and acknowledges");back_to_menu;

 start_game(91,P512,C512,1);
 cpu_write(16'h6002,5);expect_chr(14'h1000,19'h02800,"91 2KB CHR");
 cpu_write(16'h7000,3);expect_prg(16'h8000,19'h06000,"91 inner PRG");
 cpu_write(16'h8000,4);expect_prg(16'h8000,19'h46000,"91 outer PRG bank");
 // $7003 is MMC3-style (Mesen Mapper91): latch 7, reload, enable. The first
 // filtered A12 rise reloads to 7, then 7 decrements fire on the 8th rise.
 cpu_write(16'h7003,0);
 for(i=0;i<7;i=i+1)begin line;check(irq_n===1,"91 counts down before IRQ");end
 line;check(irq_n===0,"91 MMC3-style IRQ after 8 A12 rises");
 cpu_write(16'h7002,0);#100;check(irq_n===1,"91 stop acknowledge");back_to_menu;

 start_game(105,5'h0f,CHR_RAM,0);
 expect_prg(16'h8000,0,"105 startup forces first32KB");
 serial105(16'ha000,0);serial105(16'ha000,16);
 serial105(16'ha000,6);expect_prg(16'h8000,19'h18000,"105 discrete32KB mode");
 serial105(16'ha000,24);serial105(16'he000,3);
 expect_prg(16'h8000,19'h2c000,"105 MMC1 upper PRG region");expect_prg(16'hc000,19'h3c000,"105 fixed last bank");
 serial105(16'h8000,8);expect_prg(16'h8000,19'h20000,"105 MMC1 fixed first8");
 serial105(16'he000,19);cpu_read(16'h6000);check(!last_ram_ce,"105 WRAM disable");
 serial105(16'ha000,8);
 dut.m405.timer_count=dut.m405.TIMER_LIMIT-1;
 cpu_read(0);check(irq_n===0,"105 long timer terminal boundary");
 serial105(16'ha000,24);check(irq_n===1,"105 timer acknowledgement");
 expect_chr(14'h1c00,19'h01c00,"105 fixed8KB CHR RAM");
 if(errors)$fatal(1,"Remaining mapper tests failed: %0d",errors);
 $display("OK: mappers56/91/105/117/222");$finish;
end
endmodule
