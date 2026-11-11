`timescale 1ns/1ps
// Clean-room MMC5A audio, based on NESdev register descriptions.
// A15 is !romsel_n. Writes/read side effects commit on falling M2.
// rst: synchronous active-high full deterministic reset (not chip power-on).
// Frame divider M2/7424 follows the die-derived, unconfirmed NESdev estimate.
// snd: unsigned linear sum, 0..285; board gain/inversion/filtering external.
// $5010 drives bits 7,0 (revision=1); $5015 drives bits 1,0 only.
// Frame/write collision: writes win; envelope restart waits until next tick.
module snd_mmc5 (
 input wire [14:0] cpu_a,
 input wire [7:0] cpu_d,
 input wire romsel_n, cpu_rw, m2, rst,
 output wire [9:0] snd,
 output reg [7:0] cpu_dout, cpu_doe,
 output wire irq
);
 reg [7:0] control[0:1], length[0:1];
 reg [10:0] period[0:1];
 reg [11:0] timer[0:1];
 reg [2:0] phase[0:1];
 reg [3:0] decay[0:1], env_div[0:1];
 reg [1:0] enabled, env_start;
 reg [12:0] frame_count;
 reg pcm_read, pcm_irq_enable, pcm_trip;
 reg [7:0] pcm;
 wire frame_tick = frame_count == 13'd7423;
 assign irq = pcm_irq_enable && pcm_trip;
 function [7:0] length_value;
 input [4:0] index;
 begin
 case(index)
 0:length_value=10; 1:length_value=254; 2:length_value=20; 3:length_value=2;
 4:length_value=40; 5:length_value=4; 6:length_value=80; 7:length_value=6;
 8:length_value=160; 9:length_value=8; 10:length_value=60; 11:length_value=10;
 12:length_value=14; 13:length_value=12; 14:length_value=26; 15:length_value=14;
 16:length_value=12; 17:length_value=16; 18:length_value=24; 19:length_value=18;
 20:length_value=48; 21:length_value=20; 22:length_value=96; 23:length_value=22;
 24:length_value=192; 25:length_value=24; 26:length_value=72; 27:length_value=26;
 28:length_value=16; 29:length_value=28; 30:length_value=32; 31:length_value=30;
 endcase
 end
 endfunction
 function duty_on;
 input [1:0] duty;
 input [2:0] step;
 begin
 case(duty)
 0:duty_on=step==1;
 1:duty_on=step==1 || step==2;
 2:duty_on=step>=1 && step<=4;
 3:duty_on=step!=1 && step!=2;
 endcase
 end
 endfunction
 wire [3:0] volume0=control[0][4] ? control[0][3:0] : decay[0];
 wire [3:0] volume1=control[1][4] ? control[1][3:0] : decay[1];
 wire [3:0] pulse0=(length[0]!=0 && duty_on(control[0][7:6],phase[0])) ? volume0 : 4'd0;
 wire [3:0] pulse1=(length[1]!=0 && duty_on(control[1][7:6],phase[1])) ? volume1 : 4'd0;
 assign snd={2'b0,pcm}+{6'b0,pulse0}+{6'b0,pulse1};
 always @* begin
 cpu_dout=0; cpu_doe=0;
 if(!rst && m2 && cpu_rw && romsel_n) begin
 case(cpu_a)
 15'h5010:begin cpu_dout={irq,6'b0,1'b1}; cpu_doe=8'h81; end
 15'h5015:begin cpu_dout={6'b0,(length[1]!=0),(length[0]!=0)}; cpu_doe=8'h03; end
 default:begin end
 endcase
 end
 end
 integer ch;
 always @(negedge m2) begin
 if(rst) begin
 enabled<=0; env_start<=0; frame_count<=0;
 pcm_read<=0; pcm_irq_enable<=0; pcm_trip<=0; pcm<=0;
 for(ch=0;ch<2;ch=ch+1) begin
 control[ch]<=0; length[ch]<=0; period[ch]<=0; timer[ch]<=0;
 phase[ch]<=0; decay[ch]<=0; env_div[ch]<=0;
 end
 end else begin
 frame_count<=frame_tick ? 13'd0 : frame_count+13'd1;
 for(ch=0;ch<2;ch=ch+1) begin
 // 2*(period+1) CPU cycles per duty step; no low-period muting.
 // Divider runs while disabled; high register resets phase, not divider.
 if(timer[ch]==0) begin timer[ch]<={period[ch],1'b1}; phase[ch]<=phase[ch]+3'd1; end
 else timer[ch]<=timer[ch]-12'd1;
 if(frame_tick) begin
 if(!control[ch][5] && length[ch]!=0) length[ch]<=length[ch]-8'd1;
 if(env_start[ch]) begin
 env_start[ch]<=0; decay[ch]<=15; env_div[ch]<=control[ch][3:0];
 end else if(env_div[ch]!=0) env_div[ch]<=env_div[ch]-4'd1;
 else begin
 env_div[ch]<=control[ch][3:0];
 if(decay[ch]!=0) decay[ch]<=decay[ch]-4'd1;
 else if(control[ch][5]) decay[ch]<=15;
 end
 end
 if(romsel_n && !cpu_rw && cpu_a[14:3]==12'hA00 && cpu_a[2]==(ch==1)) begin
 case(cpu_a[1:0])
 0:control[ch]<=cpu_d;
 2:period[ch][7:0]<=cpu_d;
 3:begin
 period[ch][10:8]<=cpu_d[2:0]; phase[ch]<=0; env_start[ch]<=1;
 if(enabled[ch]) length[ch]<=length_value(cpu_d[7:3]);
 end
 default:begin end // $5001/$5005: no sweep
 endcase
 end
 end
 if(romsel_n && !cpu_rw) begin
 case(cpu_a)
 15'h5010:begin pcm_read<=cpu_d[0]; pcm_irq_enable<=cpu_d[7]; end
 15'h5011:if(!pcm_read) begin
 pcm_trip<=cpu_d==0; if(cpu_d!=0) pcm<=cpu_d;
 end
 15'h5015:begin
 enabled<=cpu_d[1:0];
 if(!cpu_d[0]) length[0]<=0;
 if(!cpu_d[1]) length[1]<=0;
 end
 default:begin end
 endcase
 end
 if(cpu_rw) begin
 if(romsel_n && cpu_a==15'h5010) pcm_trip<=0;
 if(pcm_read && !romsel_n && !cpu_a[14]) begin
 pcm_trip<=cpu_d==0; if(cpu_d!=0) pcm<=cpu_d;
 end
 end
 end
 end
endmodule
