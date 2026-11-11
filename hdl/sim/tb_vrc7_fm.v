`timescale 1ns/1ps
// tb_vrc7_fm.v — drives vrc7_fm.v with a register-write script and dumps one sample per line.
// Script format (same as tools/fm/fmref): first the number of samples, then "sample reg data" lines
// sorted by sample (the write is applied before that sample). Used by tools/fm/fmcheck.py.
//   vvp tb_vrc7_fm.vvp +script=in.txt +out=rtl.txt
module tb_vrc7_fm;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst = 1, wr = 0, tick = 0;
    reg [7:0] wreg = 0, wdata = 0;
    wire signed [15:0] sample;
    wire valid;
    vrc7_fm dut (.clk(clk), .rst(rst), .wr(wr), .wreg(wreg), .wdata(wdata), .tick(tick),
                 .sample(sample), .valid(valid));

    reg [1023:0] sname, oname;
    integer fi, fo, total, i, rc, ws, wrg, wd, have;
    initial begin
        if (!$value$plusargs("script=%s", sname)) begin $display("falta +script"); $finish; end
        if (!$value$plusargs("out=%s", oname)) oname = "rtl.txt";
        fi = $fopen(sname, "r");
        fo = $fopen(oname, "w");
        rc = $fscanf(fi, "%d", total);
        have = ($fscanf(fi, "%d %d %d", ws, wrg, wd) == 3);
        repeat (4) @(posedge clk);
        rst <= 0;
        @(posedge clk);
        for (i = 0; i < total; i = i + 1) begin
            while (have && ws <= i) begin
                wreg <= wrg; wdata <= wd; wr <= 1;
                @(posedge clk); wr <= 0;
                repeat (2) @(posedge clk);       // let the write queue drain
                have = ($fscanf(fi, "%d %d %d", ws, wrg, wd) == 3);
            end
            tick <= 1; @(posedge clk); tick <= 0;
            @(posedge clk);
            while (!valid) @(posedge clk);
            $fdisplay(fo, "%0d", sample);
        end
        $fclose(fo);
        $finish;
    end
endmodule
