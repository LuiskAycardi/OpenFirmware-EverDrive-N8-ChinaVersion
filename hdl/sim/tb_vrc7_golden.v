`timescale 1ns/1ps
// tb_vrc7_golden.v — vrc7_fm.v against stored oracle samples (no emu2413 needed in make sim).
// vrc7_golden_w.hex: count, then {sample[15:0], reg, data} per write; vrc7_golden_ref.hex: count, then
// one 16-bit sample per line. Both are produced by tools/fm/fmcheck.py --golden from tools/fm/fmref
// (emu2413 configured as Mesen2's VRC7). The full random equivalence test is fmcheck.py itself.
module tb_vrc7_golden;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst = 1, wr = 0, tick = 0;
    reg [7:0] wreg = 0, wdata = 0;
    wire signed [15:0] sample;
    wire valid;
    vrc7_fm dut (.clk(clk), .rst(rst), .wr(wr), .wreg(wreg), .wdata(wdata), .tick(tick),
                 .sample(sample), .valid(valid));

    `include "vrc7_golden.vh"
    reg [31:0] wm [0:GOLD_NW];
    reg [15:0] rm [0:GOLD_NS];
    integer nw, ns, i, k, bad, nz;
    initial begin
        $readmemh("../sim/vrc7_golden_w.hex", wm);
        $readmemh("../sim/vrc7_golden_ref.hex", rm);
        nw = wm[0]; ns = rm[0]; k = 1; bad = 0; nz = 0;
        repeat (4) @(posedge clk);
        rst <= 0;
        @(posedge clk);
        for (i = 0; i < ns; i = i + 1) begin
            while (k <= nw && wm[k][31:16] <= i) begin
                wreg <= wm[k][15:8]; wdata <= wm[k][7:0]; wr <= 1;
                @(posedge clk); wr <= 0;
                k = k + 1;
            end
            repeat (3) @(posedge clk);
            tick <= 1; @(posedge clk); tick <= 0;
            @(posedge clk);
            while (!valid) @(posedge clk);
            if (sample !== $signed(rm[i + 1])) begin
                bad = bad + 1;
                if (bad <= 5) $display("FALLO muestra %0d: rtl %0d ref %0d", i, sample, $signed(rm[i + 1]));
            end
            if (sample != 0) nz = nz + 1;
        end
        if (bad == 0 && nz > ns / 4) $display("PASS tb_vrc7_golden: %0d muestras iguales (%0d no nulas)", ns, nz);
        else $display("FALLO tb_vrc7_golden: %0d muestras distintas, %0d no nulas", bad, nz);
        $finish;
    end
endmodule
