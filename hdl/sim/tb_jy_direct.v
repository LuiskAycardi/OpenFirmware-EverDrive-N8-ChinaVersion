`timescale 1ns/1ps
module tb_jy_direct;
reg [14:0] cpu_a=0;
reg [7:0] cpu_d=0,cfg=0,map_id=90;
reg romsel_n=1,cpu_rw=1,m2=0,rst=1,clk=0;
reg [13:0] ppu_a=0;
reg ppu_rd_n=1,ppu_wr_n=1;
reg [5:0] chr_size=0;
wire [18:10] prg_a,chr_a;
wire prg_rom_en,prg_ram_en,prg_wr,chr_en,chr_wr,ciram_en,ciram_a10,irq,chr_raw;
wire [7:0] cpu_dout,cpu_doe;
mapper_jy dut(.*);
always #5 clk=~clk;
integer checks=0,j,k;
reg [15:0] expected_product;
task check;
input ok; input [511:0] msg;
begin checks=checks+1; if(ok!==1'b1) begin $display("FAIL %0s",msg); $fatal(1); end end
endtask
task reset;
begin rst=1; m2=0; ppu_rd_n=1; #80; rst=0; #80; end
endtask
task write;
input [15:0] a; input [7:0] d;
begin cpu_a=a[14:0]; romsel_n=~a[15]; cpu_d=d; cpu_rw=0;
#40; m2=1; #80; m2=0;
// Cartridge /ROMSEL releases 15 ns after M2 fall; no delayed live decode.
#15; romsel_n=1; cpu_rw=1; cpu_a=0; cpu_d=~d; #65; end
endtask
task cpuclock;
begin m2=1; #80; m2=0; #80; end
endtask
task readreg;
input [15:0] a; input [7:0] d,mask;
begin cpu_a=a[14:0]; romsel_n=~a[15]; cpu_rw=1; m2=1; #80;
check(cpu_doe==mask && (cpu_dout & mask)==(d & mask),"register read / OE");
m2=0; #80; check(cpu_doe==0,"read OE gated by M2"); end
endtask
task ppuread;
input [13:0] a;
begin ppu_a=a; #80; ppu_rd_n=0; #80;
// Next ALE address is already present at the exact /RD rising edge.
ppu_rd_n=1; ppu_a=14'h2000; #80; end
endtask
task pbank;
input [15:0] a; input [5:0] b;
begin cpu_a=a[14:0]; romsel_n=~a[15]; #20;
check(prg_a=={b,a[12:10]},"PRG bank and physical offset"); end
endtask
task cbank;
input [13:0] a; input [8:0] b;
begin ppu_a=a; #40; check(chr_a==b,"CHR bank"); end
endtask
initial begin
reset;
for(k=0;k<2;k=k+1) begin
map_id=k==0 ? 90 : 211; reset;   // mapper 35 is now mapper35.v
write('h5800,19); write('h5801,23);
readreg('h5800,181,255); readreg('h5ffd,1,255);
write('h5803,'ha6); readreg('h5803,'ha6,255); readreg('h5802,0,0); readreg('h5000,0,255);
write('h8000,5); write('h8001,9); write('h8002,13); write('h8003,17);
write('hd000,6); pbank('h8000,5); pbank('ha400,9); pbank('hc800,13); pbank('hec00,17);
write('h8800,33); pbank('h8000,33); // addr&F007: A11 don't-care, so $8800 writes pb[0]
write('hd000,2); pbank('he000,63);
// mode 0 = 4x8K from prgReg3 (SelectPrgPage4x: consecutive pages p3..p3+3)
write('hd000,4); pbank('h8000,17); pbank('he000,20);
// mode 1: low window prgReg1<<1 (aligned 16K), high window prgReg3 directly (p3, p3+1)
write('hd000,5); pbank('h8000,18); pbank('ha000,19); pbank('hc000,17); pbank('he000,18);
// mode 3: InvertPrgBits(pb[0]=33)=0x42 -> bank &0x3F = 2
write('hd000,7); pbank('h8000,2);
write('hd000,'h86); pbank('h6000,17); m2=1; #40; check(prg_rom_en && !prg_ram_en,"ROM at 6000"); m2=0;
write('hd000,6); cpu_a='h6000; romsel_n=1; m2=1; #40;
check(!prg_ram_en,"no WRAM without battery/enablePrgAt6000"); m2=0;
for(j=0;j<8;j=j+1) write('h9000+j,j+3);
write('hd003,'h20); write('hd000,'h1e);
for(j=0;j<8;j=j+1) cbank(j*1024,j+3);
write('ha000,1); cbank(0,259);
write('hd003,0); cbank(0,3); write('hd003,1); cbank(0,259);
write('hd003,'h20); write('ha000,0);
write('hd000,6); cbank('h1c00,31);
write('hd000,'h16); cbank('h0800,10);
write('hd000,'h0e); cbank('h1000,28);
// mirrorChr ($D003 bit7) mirrors CHR indices 2/3 onto 0/1 in 1KB/2KB modes.
// Mappers 90/211 have no 209-style CHR latch, so reads do not toggle banks.
write('hd000,'h18);                       // chrMode 3 (1KB)
write('hd003,'h20); cbank('h0800,5);      // non-block, mirror off: index 2 = chrLow[2]=5
write('hd003,'ha0); cbank('h0800,3);      // mirror on: index 2 -> 0 = chrLow[0]=3
write('hd003,'h20); write('hd000,'h0e);   // restore non-block, chrMode 1
// $D001 simple mirroring applies to mapper 90 only; 211 is always advanced NT.
if(map_id==90) begin
write('hd001,0); ppu_a='h2400; #30; check(ciram_a10,"vertical");
write('hd001,1); ppu_a='h2400; #30; check(!ciram_a10,"horizontal");
end
write('hb001,'h81); write('hd000,'h20); ppu_a='h2400; ppu_rd_n=0; #80;
check(chr_en==(map_id!=90) && ciram_en==(map_id==90),"NT ROM variant");
if(map_id!=90) check(chr_a==129,"NT ROM bank");
ppu_rd_n=1; ppu_wr_n=0; #80; check(ciram_en && !chr_en,"NT writes go to CIRAM"); ppu_wr_n=1;
write('hb001,'h80); write('hd000,0); write('hd001,8); ppu_a='h2400; #30;
check(ciram_a10==(map_id==90),"D001 extended mirroring");
cfg='h80; write('hd002,0); ppu_a=0; ppu_wr_n=0; #30; check(!chr_wr,"CHR protected");
write('hd002,'h40); #30; check(chr_wr,"CHR write enable"); ppu_wr_n=1; cfg=0;
end
// Multiplier corner sweep, including zero and FF*FF, through external reads.
map_id=90; reset;
for(j=0;j<256;j=j+1) begin
write('h5800,j); write('h5801,255-j);
expected_product=j*(255-j);
readreg('h5800,expected_product[7:0],255);
readreg('h5801,expected_product[15:8],255);
end
write('h5800,255); write('h5801,255); readreg('h5800,1,255); readreg('h5801,254,255);
// Advanced nametable control (mapper 211 is always advanced).
map_id=211; reset;
write('hb000,'h80); write('hb004,1); write('hd000,'h20);
ppu_a='h2000; ppu_rd_n=0; #80; check(chr_en && chr_a==384,"NT high bank bits");
ppu_rd_n=1; #80; write('hd002,'h80); ppu_rd_n=0; #80;
check(ciram_en && !chr_en,"NT selection XOR"); ppu_rd_n=1; #80;
write('hd000,'h60); ppu_rd_n=0; #80; check(chr_en,"NT forced globally"); ppu_rd_n=1; #80;
// $D800 decodes as $D000 (addr&0xF007): writing mode 0 drops NT ROM back to CIRAM.
write('hd800,0); ppu_rd_n=0; #80; check(!chr_en && ciram_en,"D800 aliases D000"); ppu_rd_n=1; #80;
// IRQ source selection. The prescaler/counter advance on every source tick even
// while disabled (Mesen ProcessCpuClock/TickIrqCounter), and CpuClock/CpuWrite
// sources also tick during register writes, so this checks that each source
// eventually raises IRQ (counter 0xFF, up, 3-bit prescaler) rather than an exact
// tick count. The precise prescaler corners below use the A12 source, which does
// not tick during the register writes, so their state is deterministic.
map_id=90;
for(k=0;k<4;k=k+1) begin
reset; write('hc001,'h44|k); write('hc005,'hff); write('hc003,0);
if(k==0) repeat(16) cpuclock;
if(k==1) repeat(16) begin ppu_a=0; #40; ppu_a='h1000; #40; end
if(k==2) repeat(16) ppuread(0);
if(k==3) repeat(16) write('h4000,0);
check(irq,"IRQ source raises line"); write('hc802,0); check(!irq,"IRQ acknowledge alias");
end
// 3-bit down prescaler (A12 source). Mesen clocks when the masked value is 1
// (0 wraps to 7 without clocking), so pre=1 clocks the counter 0 -> 0xFF.
reset; write('hc101,'h85); write('hc104,1); write('hc105,0); write('hc103,0);
ppu_a=0; #40; ppu_a='h1000; #40;
check(irq,"3-bit down wrap at zero");
write('hc102,0); repeat(10) begin ppu_a=0; #40; ppu_a='h1000; #40; end
check(!irq,"acknowledged IRQ stays clear");
// 8-bit up: pre 0xFE needs two ticks to wrap, then the counter 0xFF -> 0 fires.
reset; write('hc101,'h41); write('hc104,'hfe); write('hc105,'hff); write('hc103,0);
ppu_a=0; #40; ppu_a='h1000; #40; check(!irq,"8-bit up pre before wrap");
ppu_a=0; #40; ppu_a='h1000; #40; check(irq,"8-bit up pre wrap");
// 8-bit down: pre 2 -> tick1 (2->1) no clock, tick2 clocks, counter 0 -> 0xFF.
reset; write('hc101,'h81); write('hc104,2); write('hc105,0); write('hc103,0);
ppu_a=0; #40; ppu_a='h1000; #40; check(!irq,"8-bit down before underflow");
ppu_a=0; #40; ppu_a='h1000; #40; check(irq,"8-bit down underflow");
// Directions 0 and 3 never clock the counter.
reset; write('hc101,'h01); write('hc104,255); write('hc105,255); write('hc103,0);
repeat(4) begin ppu_a=0; #40; ppu_a='h1000; #40; end check(!irq,"direction zero inhibited");
write('hc101,'hc1); repeat(4) begin ppu_a=0; #40; ppu_a='h1000; #40; end check(!irq,"direction three inhibited");
reset; write('hc001,0); write('hc004,255); write('hc005,255); write('hc003,0);
repeat(3) cpuclock; check(!irq,"direction zero inhibited");
write('hc001,'hc0); repeat(3) cpuclock; check(!irq,"direction three inhibited");
reset; map_id=1; cpu_a=0; romsel_n=0; #30;
check(!prg_rom_en && !chr_en && !ciram_en && !irq && cpu_doe==0,"inactive isolation");
$display("PASS tb_jy_direct: %0d checks",checks); $finish;
end
initial begin #10000000; $fatal(1,"timeout"); end
endmodule
