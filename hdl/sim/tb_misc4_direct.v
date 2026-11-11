`timescale 1ns/1ps
module tb_misc4_direct;
 reg [14:0] cpu_a=0; reg [7:0] cpu_d=0;
 reg romsel_n=1,cpu_rw=1,m2=0;
 reg [13:0] ppu_a=0; reg ppu_rd_n=1,ppu_wr_n=1;
 reg [7:0] cfg=0; reg rst=0,clk=0;
 reg [7:0] map_id=0; reg [5:0] chr_size=1;
 wire [18:10] prg_a,chr_a;
 wire prg_rom_en,prg_ram_en,prg_wr,chr_en,chr_wr,ciram_en,ciram_a10,irq,chr_raw;
 wire [7:0] cpu_dout,cpu_doe;
 mapper_misc4 dut(.*);
 integer checks=0,i,j,k,expected;
 task check; input condition; input [511:0] label;
 begin checks=checks+1; if(condition!==1'b1) begin
  $display("FAIL %0s check=%0d prg=%h chr=%h",label,checks,prg_a,chr_a); $fatal(1);
 end end endtask
 task addr; input [15:0] a; begin cpu_a=a[14:0]; romsel_n=~a[15]; #1; end endtask
 task tick; begin m2=1; #2; m2=0; #2; end endtask
 task bus; input [15:0] a; input [7:0] d; input rd;
 begin addr(a); cpu_d=d; cpu_rw=rd; tick; cpu_rw=1; end endtask
 task reset_map; input [7:0] id;
 begin map_id=id; addr(0); rst=1; tick; rst=0; cfg=0; ppu_a=0; ppu_wr_n=1; #1; end endtask
 initial begin
  reset_map(99);
  for(i=0;i<2;i=i+1) begin
   bus(16'h4016,i*4,0);
   for(j=0;j<32;j=j+1) begin addr(16'h8000+j*1024);
    expected=j<8 ? i*32+j : j; check(prg_a==expected && prg_rom_en,"99 PRG"); end
   ppu_a=0; #1; check(chr_a==i*8 && chr_en,"99 CHR select");
  end
  chr_size=0; #1; check(!chr_en,"99 absent CHR socket"); chr_size=1;
  bus(16'h4017,0,0); ppu_a=0; #1; check(chr_a==8,"99 exact register");
  bus(16'h4016,0,1); #1; check(chr_a==8,"99 reads ignored");
  for(i=0;i<8;i=i+1) begin addr(16'h6000+i*1024); m2=1; #1;
   check(prg_ram_en && prg_a==(i%2),"99 2K RAM mirrors"); end
  m2=0; #1; check(!prg_ram_en,"99 M2 gate");
  for(i=0;i<4;i=i+1) begin ppu_a=16'h2000+i*1024; ppu_wr_n=0; #1;
   check(chr_raw && chr_a==504+i && chr_wr && !ciram_en,"99 four screen"); end
  $display("PASS mapper 99");
  reset_map(111);
  for(i=0;i<64;i=i+1) begin
   bus(i[0] ? 16'h7000 : 16'h5000,i,i[1]);
   addr(16'h8000); #1; check(prg_a==(i%16)*32 && prg_rom_en,"111 PRG/read latch");
   for(j=0;j<16;j=j+1) begin ppu_a=j*1024; ppu_wr_n=0; #1;
    expected=j<8 ? ((i/16)%2)*16+j : ((i/32)%2)*16+j;
    check(chr_a==expected && chr_raw && chr_en && chr_wr && !ciram_en,"111 RAM/bonus RAM");
   end
  end
  bus(16'h6000,0,0); addr(16'h8000); #1; check(prg_a==480,"111 decode excludes 6000");
  cpu_rw=0; #1; check(!prg_rom_en && !prg_wr,"111 no flash programming");
  $display("PASS mapper 111");
  reset_map(186);
  for(i=0;i<256;i=i+1) begin
   bus(16'h4200,i,0); bus(16'h4201,i,0);
   addr(16'h8000); check(prg_a==(i%16)*16,"186 BIOS bank");
   addr(16'hc000); check(prg_a==0,"186 fixed BIOS");
   addr(16'h4400); m2=1; #1; check(prg_ram_en && prg_a==33,"186 fixed RAM"); m2=0;
   addr(16'h5000); m2=1; #1; check(prg_ram_en && prg_a==32+(i%8)*4,"186 4K RAM bank"); m2=0;
   addr(16'h6000); m2=1; cpu_rw=0; #1;
   check(prg_ram_en && prg_wr && prg_a==(i/64)*8,"186 8K RAM bank");
   m2=0; cpu_rw=1;
  end
  addr(16'h43ff); m2=1; #1; check(!prg_ram_en,"186 RAM lower boundary"); m2=0;
  bus(16'h4202,8'h31,0); addr(16'h4202); m2=1; #1;
  check(cpu_doe==255 && cpu_dout==8,"186 disconnected busy"); m2=0; #1;
  addr(0); repeat(99) tick;
  addr(16'h4202); m2=1; #1; check(cpu_dout==8'h48,"186 100 clock readiness"); m2=0; #1;
  bus(16'h4202,1,0); addr(16'h4201); m2=1; #1;
  check(cpu_dout==8'h80 && cpu_doe==255 && !irq,"186 decoder no tape");
  cpu_rw=0; #1; check(cpu_doe==0,"186 no drive on writes"); m2=0;
  for(i=0;i<4;i=i+1) begin ppu_a=16'h2000+i*1024; ppu_wr_n=0; #1;
   check(chr_a==504+i && chr_raw && chr_wr && !ciram_en,"186 four screen"); end
  $display("PASS mapper 186");
  // Exhaust all lower block/mode choices and every inner-register value.
  for(i=0;i<32;i=i+1) begin
   reset_map(234); bus(16'hff80,(i%16) | ((i/16)*64) | 128,1);
   for(j=0;j<256;j=j+1) begin
    bus(16'hffe8,j,j[0]); addr(16'h8000); ppu_a=0; #1;
    expected=i<16 ? i : ((i%16)/2)*2+(j%2);
    check(prg_a==expected*32,"234 PRG modes");
    expected=i<16 ? i*4+((j/16)%4) : ((i%16)/2)*8+((j/16)%8);
    check(chr_a==expected*8 && chr_en,"234 CHR modes");
   end
  end
  reset_map(234); bus(16'hff80,8'hc0,1); bus(16'hff9f,8'h43,1);
  bus(16'hff80,0,0); addr(16'h8000); #1; check(prg_a==64,"234 outer locks only on low six bits");
  bus(16'hfff8,8'h71,1); addr(16'h8000); #1; check(prg_a==64,"234 FFF8 excluded");
  bus(16'hfff7,8'h71,1); addr(16'h8000); #1; check(prg_a==96 && chr_a==120,"234 inner end included");
  ppu_a=16'h2400; #1; check(ciram_en && ciram_a10,"234 vertical mirroring");
  reset_map(234); bus(16'hff80,8'h81,1); ppu_a=16'h2800; #1;
  check(ciram_a10,"234 horizontal mirroring");
  reset_map(234); bus(16'hff80,8'h20,1); addr(16'h8000); ppu_a=0; #1;
  check(!prg_rom_en && !chr_en,"234 unaddressable ROM pair no alias");
  reset_map(234); bus(16'hff80,8'h10,1); addr(16'h8000); #1;
  check(prg_rom_en && chr_en,"234 q alone does not disable first pair");
  reset_map(0); #1;
  check(!prg_rom_en && !prg_ram_en && !chr_en && !chr_wr && cpu_doe==0 && !irq,"inactive mapper");
  $display("PASS misc4_direct checks=%0d",checks); $finish;
 end
 initial begin #1000000; $fatal(1,"timeout"); end
endmodule
