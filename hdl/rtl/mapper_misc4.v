`timescale 1ns/1ps
// Clean-room logic from NESdev facts (INES_Mapper_099, GTROM,
// INES_Mapper_186, INES_Mapper_234); local Mesen2 VsSystem, Cheapocabra,
// StudyBox, Mapper234 consulted for register behavior, no code copied.
// Caveats: no PRG-size input, so 99 exposes Gumshoe's alternate 8K bank;
// caller must suppress absent PRG sockets. chr_size is an 8K-bank mask.
// VS coin/DIP/palette/dual-CPU RAM arbitration are outside this interface.
// 111: RAM and read/write latch implemented; flash erase/program, LEDs and
// GTMP3 audio are not represented by these ports. Power-on latch chosen zero.
// 186: BIOS/RAM banking and four-screen RAM implemented. Without a tape input,
// reports disconnected drive, no page/data/IRQ; implements command readiness.
// 234: cpu_d MUST be the read value or resolved write-conflict value at M2 fall.
// Q selects ROMs beyond the 512K address bus: leave undriven instead of aliasing.
// q disables that pair as on hardware. CIC charge-pump has no output here.
// Four-screen RAM for 99/186 uses reserved raw CHR 1K pages 504..507.
module mapper_misc4 (
 input wire [14:0] cpu_a, input wire [7:0] cpu_d,
 input wire romsel_n,cpu_rw,m2,
 input wire [13:0] ppu_a, input wire ppu_rd_n,ppu_wr_n,
 input wire [7:0] cfg, input wire rst,clk,
 input wire [7:0] map_id, input wire [5:0] chr_size,
 output reg [18:10] prg_a, output reg prg_rom_en,prg_ram_en,
 output wire prg_wr, output reg [18:10] chr_a,
 output reg chr_en,chr_wr,ciram_en,ciram_a10,
 output wire irq, output reg chr_raw,
 output reg [7:0] cpu_dout,cpu_doe
);
 reg vs_bank;
 reg [7:0] gt,outer_bank,inner_bank,ram_bank,bios_bank,tape_ctrl;
 reg [6:0] ready_count;
 reg ready;
 wire study_reg=romsel_n && cpu_a>=15'h4200 && cpu_a<=15'h4203;
 initial begin
  vs_bank=0; gt=0; outer_bank=0; inner_bank=0;
  ram_bank=0; bios_bank=0; tape_ctrl=0; ready_count=0; ready=0;
 end
 always @(negedge m2) begin
  if(rst) begin
   vs_bank<=0; gt<=0; outer_bank<=0; inner_bank<=0;
   ram_bank<=0; bios_bank<=0; tape_ctrl<=0; ready_count<=0; ready<=0;
  end else case(map_id)
   99: if(romsel_n && !cpu_rw && cpu_a==15'h4016) vs_bank<=cpu_d[2];
   111: if(romsel_n && cpu_a[14] && cpu_a[12]) gt<=cpu_d;
   234: if(!romsel_n) begin
    if(cpu_a>=15'h7f80 && cpu_a<=15'h7f9f && outer_bank[5:0]==0) outer_bank<=cpu_d;
    if(cpu_a>=15'h7fe8 && cpu_a<=15'h7ff7) inner_bank<=cpu_d;
   end
   186: begin
    if(ready_count!=0) begin
     ready_count<=ready_count-1'b1;
     if(ready_count==1) ready<=1;
    end
    if(study_reg && !cpu_rw) case(cpu_a[1:0])
     0: ram_bank<=cpu_d;
     1: bios_bank<=cpu_d;
     2: begin
      tape_ctrl<=cpu_d;
      if(cpu_d[4]) begin ready<=0; ready_count<=100; end
      if(tape_ctrl[5] && !cpu_d[5]) begin ready<=1; ready_count<=0; end
     end
     default: ;
    endcase
   end
   default: ;
  endcase
 end
 reg [3:0] p234;
 reg [5:0] c234;
 always @* begin
  p234=outer_bank[6] ? {outer_bank[3:1],inner_bank[0]} : outer_bank[3:0];
  c234=outer_bank[6] ? {outer_bank[3:1],inner_bank[6:4]} : {outer_bank[3:0],inner_bank[5:4]};
  prg_a={4'd0,cpu_a[14:10]}; prg_rom_en=0; prg_ram_en=0;
  chr_a={6'd0,ppu_a[12:10]}; chr_en=0; chr_wr=0;
  ciram_en=0; ciram_a10=cfg[0] ? ppu_a[10] : ppu_a[11];
  chr_raw=0; cpu_dout=0; cpu_doe=0;
  case(map_id)
   99: begin
    prg_rom_en=!romsel_n;
    if(!romsel_n && cpu_a[14:13]==0) prg_a={3'd0,vs_bank,2'd0,cpu_a[12:10]};
    prg_ram_en=romsel_n && cpu_a[14:13]==3 && m2;
    if(romsel_n) prg_a={8'd0,cpu_a[10]};
    chr_a={5'd0,vs_bank,ppu_a[12:10]};
    chr_en=!ppu_a[13] && (!vs_bank || chr_size!=0);
    chr_wr=chr_en && cfg[7] && !ppu_wr_n;
    if(ppu_a[13]) begin
     chr_raw=1; chr_en=1; chr_wr=!ppu_wr_n;
     chr_a={7'b1111110,ppu_a[11:10]};
    end
   end
   111: begin
    prg_a={gt[3:0],cpu_a[14:10]}; prg_rom_en=!romsel_n && cpu_rw;
    chr_raw=1; chr_en=1; chr_wr=!ppu_wr_n;
    // Physical RAM A14 is C/N; A13 is PPU A13, A12..0 pass through.
    chr_a={4'd0,ppu_a[13] ? gt[5] : gt[4],ppu_a[13],ppu_a[12:10]};
   end
   186: begin
    prg_rom_en=!romsel_n;
    prg_a=cpu_a[14] ? {5'd0,cpu_a[13:10]} : {1'd0,bios_bank[3:0],cpu_a[13:10]};
    if(romsel_n) begin
     prg_ram_en=m2 && cpu_a>=15'h4400;
     if(cpu_a<15'h5000) prg_a={5'd8,cpu_a[11:10]};
     else if(cpu_a<15'h6000) prg_a={3'd0,1'b1,ram_bank[2:0],cpu_a[11:10]};
     else prg_a={4'd0,ram_bank[7:6],cpu_a[12:10]};
    end
    chr_raw=1; chr_en=1; chr_wr=!ppu_wr_n;
    chr_a=ppu_a[13] ? {7'b1111110,ppu_a[11:10]} : {6'd0,ppu_a[12:10]};
    if(study_reg && cpu_rw && m2) begin
     cpu_doe=8'hff;
     case(cpu_a[1:0])
      0: cpu_dout=0; // no tape byte available
      1: cpu_dout={tape_ctrl[0],7'd0};
      2: cpu_dout={1'b0,ready,2'b00,1'b1,3'd0};
      default: cpu_dout=0;
     endcase
    end
   end
   234: begin
    prg_a={p234,cpu_a[14:10]}; prg_rom_en=!romsel_n && !outer_bank[5];
    chr_a={c234,ppu_a[12:10]}; chr_en=!ppu_a[13] && !outer_bank[5];
    chr_wr=chr_en && cfg[7] && !ppu_wr_n;
    ciram_en=ppu_a[13]; ciram_a10=outer_bank[7] ? ppu_a[11] : ppu_a[10];
   end
   default: ;
  endcase
 end
 assign prg_wr=prg_ram_en && !cpu_rw;
 assign irq=1'b0;
endmodule
