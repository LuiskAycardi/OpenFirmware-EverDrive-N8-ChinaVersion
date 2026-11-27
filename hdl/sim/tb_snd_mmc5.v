`timescale 1ns/1ps
module tb_snd_mmc5;
reg [14:0] cpu_a=0;reg [7:0] cpu_d=0;reg romsel_n=1,cpu_rw=1,m2=0,rst=1;
wire [9:0] snd;wire [7:0] cpu_dout,cpu_doe;wire irq;
snd_mmc5 dut(cpu_a,cpu_d,romsel_n,cpu_rw,m2,rst,snd,cpu_dout,cpu_doe,irq);
task cycle;begin m2=0;#280;m2=1;#280;m2=0;#1;end endtask
task wr(input[14:0] a,input[7:0] d);begin cpu_a=a;cpu_d=d;romsel_n=1;cpu_rw=0;cycle;cpu_rw=1;cpu_a=0;end endtask
task check(input condition,input[8*70-1:0] msg);begin if(!condition)$fatal(1,"%s",msg);end endtask
integer i,nonzero,maxv;
initial begin
 cycle;rst=0;
 wr(15'h5011,8'h40);check(snd==66,"PCM write output (64+2)");
 wr(15'h5011,0);check(snd==66,"zero PCM value holds DAC");
 wr(15'h5010,8'h80);wr(15'h5011,0);check(irq,"PCM zero IRQ");
 cpu_a=15'h5010;cpu_rw=1;m2=1;#40;check(cpu_doe[7] && cpu_dout[7],"PCM status");
 #240;m2=0;#1;check(!irq,"PCM read acknowledgement");
 wr(15'h5010,8'h81);romsel_n=0;cpu_a=15'h0123;cpu_d=8'h20;cycle;
 check(snd==33,"PCM read mode captures ROM data");
 cpu_a=15'h4123;cpu_d=8'h30;cycle;check(snd==33,"PCM excludes C000-FFFF");
 cpu_a=15'h0123;cpu_d=0;cycle;check(irq && snd==33,"PCM zero read holds DAC and raises IRQ");
 wr(15'h5010,0);check(!irq,"PCM IRQ disable");
 // Length enables both channels; two duty outputs actually oscillate.
 wr(15'h5015,3);wr(15'h5000,8'h9f);wr(15'h5002,4);wr(15'h5003,0);
 wr(15'h5004,8'h9a);wr(15'h5006,5);wr(15'h5007,0);
 cpu_a=15'h5015;m2=1;#40;check(cpu_doe==3 && cpu_dout[1:0]==3,"pulse status bits");m2=0;#1;
 cpu_a=0;nonzero=0;
 for(i=0;i<200;i=i+1)begin cycle;if(snd>33)nonzero=nonzero+1;end
 check(nonzero>0 && nonzero<200,"pulse duty oscillation");
 wr(15'h5015,0);check(snd==33,"pulse disable stops output");
 wr(15'h5015,1);wr(15'h5000,8'h80);wr(15'h5002,8'hff);wr(15'h5003,0);
 for(i=0;i<7425;i=i+1)cycle;
 check(dut.decay[0]==15,"envelope restart on frame tick");
 for(i=0;i<7424;i=i+1)cycle;
 check(dut.decay[0]==14,"envelope decay on next frame tick");
 wr(15'h5001,8'hff);check(dut.period[0]==11'h0ff,"MMC5 sweep register has no effect");
 for(i=0;i<74240;i=i+1)cycle;
 check(dut.length[0]==0,"length expires without halt");
 wr(15'h5000,8'hbf);wr(15'h5003,0);
 for(i=0;i<74240;i=i+1)cycle;
 check(dut.length[0]==10,"length halt holds counter");
 // Escala nueva: snd = 2*(pulso0+pulso1) + pcm + (pcm>>5).
 rst=1;cycle;rst=0;cpu_a=0;
 check(snd==0,"reset: silencio");
 wr(15'h5011,8'h40);check(snd==66,"PCM 64 -> 64+2");
 wr(15'h5011,8'hff);check(snd==262,"PCM 255 -> 255+7");
 rst=1;cycle;rst=0;cpu_a=0;
 wr(15'h5015,1);wr(15'h5000,8'h9f);wr(15'h5002,4);wr(15'h5003,0);
 nonzero=0;maxv=0;
 for(i=0;i<200;i=i+1)begin cycle;if(snd>maxv)maxv=snd;if(snd!=0 && snd!=30)nonzero=nonzero+1;end
 check(maxv==30,"un pulso a volumen 15 en fase alta y PCM 0 -> 30");
 check(nonzero==0,"el pulso solo da 0 o 30");
 $display("OK: MMC5 pulse/length/envelope/PCM/IRQ");$finish;
end
endmodule
