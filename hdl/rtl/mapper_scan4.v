`timescale 1ns/1ps
// Mappers 91 (JY submapper0), 117, 222. Own logic from public register facts.
// 91 follows NESdev's 64 raw A12 rises, not Mesen2's MMC3 approximation.
// OS v13 has no submapper register: 91.1 is not selected by this implementation.
module mapper_scan4 (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,
    input  wire        ppu_wr_n,
    input  wire [7:0]  cfg,
    input  wire        rst,
    input  wire        clk,
    input  wire [7:0]  map_id,

    output wire [18:10] prg_a,
    output wire        prg_rom_en,
    output wire        prg_ram_en,
    output wire        prg_wr,
    output wire [18:10] chr_a,
    output wire        chr_en,
    output wire        chr_wr,
    output wire        ciram_en,
    output wire        ciram_a10,
    output wire        irq
);
wire m91=map_id==91,m117=map_id==117,m222=map_id==222;
reg [7:0] pr[0:3],ch[0:7];
reg [1:0] outer=0;
reg horizontal=0;
reg enable=0;
reg [7:0] reload_value=0;
reg load_toggle=0,ack_toggle=0;
wire wr8=!romsel_n && !cpu_rw;
wire wr6=romsel_n && !cpu_rw && cpu_a[14:13]==3;
integer i;
initial begin
 for(i=0;i<4;i=i+1)pr[i]=8'hfc+i;
 for(i=0;i<8;i=i+1)ch[i]=0;
end
always @(negedge m2) begin
 if(rst)begin
  for(i=0;i<4;i=i+1)pr[i]<=8'hfc+i;
  for(i=0;i<8;i=i+1)ch[i]<=0;
  outer<=0; horizontal<=!cfg[0];enable<=0;reload_value<=0;load_toggle<=0;ack_toggle<=0;
 end else if(m91)begin
  if(wr8 && cpu_a[14:13]==0)outer<=cpu_d[2:1];
  if(wr6)begin
   if(!cpu_a[12])ch[cpu_a[1:0]]<=cpu_d;
   else case(cpu_a[1:0])
    0:pr[0]<={4'd0,cpu_d[3:0]};
    1:pr[1]<={4'd0,cpu_d[3:0]};
    // IRQ is MMC3-style (Mesen Mapper91: $7002->$E000 disable+ack,
    // $7003->$C000=7 latch, $C001 reload, $E001 enable). Latch fixed at 7.
    2:begin enable<=0;ack_toggle<=~ack_toggle;end
    3:begin enable<=1;reload_value<=8'd7;load_toggle<=~load_toggle;end
   endcase
  end
 end else if(m117 && wr8)begin
  if(cpu_a[14:2]==13'h0000)pr[cpu_a[1:0]]<=cpu_d;
  else if(cpu_a[14:3]==12'h400)ch[cpu_a[2:0]]<=cpu_d;
  else case(cpu_a)
   15'h4001:reload_value<=cpu_d;
   15'h4002:ack_toggle<=~ack_toggle;
   15'h4003:load_toggle<=~load_toggle;
   15'h5000:horizontal<=cpu_d[0];
   15'h6000:begin enable<=cpu_d[0];ack_toggle<=~ack_toggle;end
   default:;
  endcase
 end else if(m222 && wr8)begin
  case({cpu_a[14:12],cpu_a[1:0]})
   5'b00000:pr[0]<=cpu_d;
   5'b00100:horizontal<=cpu_d[0];
   5'b01000:pr[1]<=cpu_d;
   5'b11100:begin reload_value<=cpu_d;load_toggle<=~load_toggle;ack_toggle<=~ack_toggle;end
   default:;
  endcase
  if(cpu_a[14:12]>=3 && cpu_a[14:12]<=6 && !cpu_a[0])
   ch[{(cpu_a[14:12]-3'd3),cpu_a[1]}]<=cpu_d;
 end
end
wire a12_line,a12_raw,unused_fall0,unused_fall1;
a12_filter filtered(.clk(clk),.m2(m2),.a12(ppu_a[12]),.a12_clk(a12_line),.m2_fall(unused_fall0));
a12_filter #(.LOW_M2(0)) raw(.clk(clk),.m2(m2),.a12(ppu_a[12]),.a12_clk(a12_raw),.m2_fall(unused_fall1));
reg [2:0] load_sync=0,ack_sync=0;
reg [7:0] counter=0;
reg pending=0,armed=0;
always @(posedge clk)begin
 load_sync<={load_sync[1:0],load_toggle};ack_sync<={ack_sync[1:0],ack_toggle};
 if(rst)begin counter<=0;pending<=0;armed<=0;end
 else begin
  if(ack_sync[2]!=ack_sync[1])pending<=0;
  if(load_sync[2]!=load_sync[1])begin counter<=reload_value;armed<=1;end
  else if(m91 && a12_line)begin
   // Sharp MMC3 counter: reload latch at 0/after reload, else decrement; the
   // transition to 0 raises IRQ when enabled.
   if(counter==0 || armed)begin counter<=reload_value;armed<=0;end
   else begin counter<=counter-1'b1; if(counter==8'd1 && enable)pending<=1;end
  end else if(m117 && enable && armed && a12_line && counter!=0)begin
   counter<=counter-1'b1;
   if(counter==1)begin pending<=1;armed<=0;end
  end else if(m222 && a12_line && counter!=0)begin
   if(counter>=239)begin pending<=1;counter<=0;end
   else counter<=counter+1'b1;
  end
 end
end
wire [1:0] w=cpu_a[14:13];
reg [5:0] bank;
always @*begin
 if(m117)bank=pr[w][5:0];
 else if(m91)bank={outer,w[1] ? {3'b111,w[0]} : pr[w][3:0]};
 else bank=w[1] ? {5'b11111,w[0]} : pr[w][5:0];
end
wire win6=romsel_n && cpu_a[14:13]==3;
assign prg_a=win6 ? {6'd0,cpu_a[12:10]} : {bank,cpu_a[12:10]};
assign prg_rom_en=!romsel_n;
assign prg_ram_en=m117 && win6 && m2;
assign prg_wr=prg_ram_en && !cpu_rw;
assign chr_a=cfg[7] ? {6'd0,ppu_a[12:10]} : m91 ? {ch[ppu_a[12:11]][7:0],ppu_a[10]} : {1'b0,ch[ppu_a[12:10]]};
assign chr_en=!ppu_a[13];assign chr_wr=cfg[7] && !ppu_wr_n && !ppu_a[13];
assign ciram_en=ppu_a[13];assign ciram_a10=(m91 ? !cfg[0] : horizontal) ? ppu_a[11] : ppu_a[10];
assign irq=pending;
endmodule
