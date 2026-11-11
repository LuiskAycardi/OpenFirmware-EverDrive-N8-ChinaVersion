`timescale 1ns/1ps
// tb_pirate_direct.v — direct checks of the pirate batch: mapper_pirate.v (59, 83, 253), mapper116.v and
// the 209 CHR latch of mapper_jy.v. The full behaviour is compared against Mesen2 by the fuzz bench
// (tools/n8sim/fuzz) and real games; this bench pins the parts the fuzz rarely reaches.
module tb_pirate_direct;
    reg [14:0] cpu_a = 0;
    reg [7:0]  cpu_d = 0, cfg = 8'h01, map_id = 8'd253;
    reg        romsel_n = 1, cpu_rw = 1, m2 = 0, rst = 1, clk = 0;
    reg [13:0] ppu_a = 0;
    reg        ppu_rd_n = 1, ppu_wr_n = 1;
    reg [7:0]  ppu_din = 0;
    wire [5:0] chr_size = 6'h3f;
    always #10 clk = ~clk;

    wire [18:10] prg_a, chr_a, prg_a2, chr_a2, prg_a3, chr_a3;
    wire prg_rom_en, prg_ram_en, prg_wr, chr_en, chr_wr, ciram_en, ciram_a10, irq, chr_raw;
    wire [7:0] cpu_dout, cpu_doe, ppu_dout, ppu_doe;
    mapper_pirate dut (.*);
    wire p2, r2, w2, ce2, cw2, ci2, a102, irq2;
    mapper116 d116 (.cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(romsel_n), .cpu_rw(cpu_rw), .m2(m2), .ppu_a(ppu_a),
        .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(rst), .clk(clk), .map_id(8'd116),
        .prg_a(prg_a2), .prg_rom_en(p2), .prg_ram_en(r2), .prg_wr(w2), .chr_a(chr_a2), .chr_en(ce2),
        .chr_wr(cw2), .ciram_en(ci2), .ciram_a10(a102), .irq(irq2));
    wire p3, r3, w3, ce3, cw3, ci3, a103, irq3, raw3; wire [7:0] do3, doe3;
    mapper_jy d209 (.cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(romsel_n), .cpu_rw(cpu_rw), .m2(m2), .ppu_a(ppu_a),
        .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(8'h00), .rst(rst), .clk(clk), .map_id(8'd209),
        .chr_size(chr_size), .prg_a(prg_a3), .prg_rom_en(p3), .prg_ram_en(r3), .prg_wr(w3), .chr_a(chr_a3),
        .chr_en(ce3), .chr_wr(cw3), .ciram_en(ci3), .ciram_a10(a103), .irq(irq3), .chr_raw(raw3),
        .cpu_dout(do3), .cpu_doe(doe3));

    integer checks = 0, n;
    task check(input ok, input [639:0] msg);
        begin checks = checks + 1; if (ok !== 1'b1) $fatal(1, "map %0d: %0s", map_id, msg); end
    endtask
    task cycle; begin #100; m2 = 1; #300; m2 = 0; #158; end endtask      // ~559 ns, like the CPU
    task wr(input [15:0] a, input [7:0] d);
        begin cpu_a = a[14:0]; romsel_n = !a[15]; cpu_d = d; cpu_rw = 0; cycle; cpu_rw = 1; romsel_n = 1; cpu_a = 0; end
    endtask
    task ppu_write(input [13:0] a, input [7:0] d);
        begin ppu_a = a; ppu_din = d; #50; ppu_wr_n = 0; #120; ppu_wr_n = 1; #50; end
    endtask
    task ppu_read(input [13:0] a);
        begin ppu_a = a; #50; ppu_rd_n = 0; #120; end                // left low: caller checks, then ends
    endtask
    task ppu_end; begin ppu_rd_n = 1; #100; end endtask
    task reset_all; begin rst = 1; cycle; cycle; rst = 0; cycle; end endtask

    initial begin
        // ---------------------------------------------------------------- 253
        reset_all;
        wr(16'h8010, 8'h05); wr(16'hA010, 8'h09);
        cpu_a = 15'h0000; romsel_n = 0; #20; check(prg_a == {6'd5, 3'd0}, "253 PRG $8000");
        cpu_a = 15'h2400; #20; check(prg_a == {6'd9, 3'd1}, "253 PRG $A000");
        cpu_a = 15'h4000; #20; check(prg_a == {6'h3E, 3'd0}, "253 PRG $C000 = -2");
        romsel_n = 1;
        // CHR registers by nibble: $B000 low = 3, $B004 = $B1 -> slot 0 = $13, CHR A8 = 1 ($B1 >> 4 = $B)
        wr(16'hB000, 8'h03); wr(16'hB004, 8'hB1);
        ppu_a = 14'h0000; #20; check(chr_a == 9'h113 && chr_en && ppu_doe == 0, "253 CHR ROM bank");
        // slot 1 ($B008/$B00C) = 4 -> CHR-RAM page 0, slot 2 ($C000) = 5 -> page 1
        wr(16'hB008, 8'h04); wr(16'hB00C, 8'h00); wr(16'hC000, 8'h05); wr(16'hC004, 8'h00);
        ppu_write(14'h0410, 8'h5A); ppu_write(14'h0810, 8'hC3);
        ppu_read(14'h0410); #40; check(!chr_en && ppu_doe == 8'hFF && ppu_dout == 8'h5A, "253 CHR-RAM page 0"); ppu_end;
        ppu_read(14'h0810); #40; check(ppu_doe == 8'hFF && ppu_dout == 8'hC3, "253 CHR-RAM page 1"); ppu_end;
        ppu_read(14'h0010); #40; check(ppu_doe == 8'h00 && chr_en, "253 ROM slot not driven"); ppu_end;
        // $B000 = $88 forces CHR-ROM for banks 4/5; $C8 releases it
        wr(16'hB000, 8'h08); wr(16'hB004, 8'h08);
        ppu_read(14'h0410); #40; check(ppu_doe == 8'h00 && chr_en && chr_a == 9'h004, "253 forced CHR-ROM"); ppu_end;
        wr(16'hB004, 8'h0C);
        ppu_read(14'h0410); #40; check(ppu_doe == 8'hFF && ppu_dout == 8'h5A, "253 released ($C8)"); ppu_end;
        // mirroring: header (cfg D0) until the first $9400 write ($9008 is not the register)
        cfg = 8'h00; reset_all; wr(16'h9008, 8'h00);
        ppu_a = 14'h2800; #20; check(ciram_a10 == 1'b1, "253 header horizontal at power-on");
        cfg = 8'h01; reset_all;
        ppu_a = 14'h2400; #20; check(ciram_a10 == 1'b1, "253 header vertical at power-on");
        wr(16'h9400, 8'h01); ppu_a = 14'h2800; #20; check(ciram_a10 == 1'b1, "253 horizontal");
        wr(16'h9400, 8'h03); ppu_a = 14'h2000; #20; check(ciram_a10 == 1'b1, "253 screen B");
        // IRQ: reload $FE, enable: fires after 2 x 114 CPU cycles, reloads, acknowledged by $F000
        wr(16'hF000, 8'h0E); wr(16'hF004, 8'h0F); wr(16'hF008, 8'h02);
        for (n = 0; n < 226; n = n + 1) cycle;
        check(!irq, "253 IRQ not yet");
        repeat (3) cycle; check(irq, "253 IRQ after 2 x 114 cycles");
        wr(16'hF000, 8'h0E); check(!irq, "253 IRQ acknowledged");
        wr(16'hF008, 8'h00);

        // ---------------------------------------------------------------- 83
        map_id = 8'd83; reset_all;
        wr(16'h5101, 8'h77); cpu_a = 15'h5101; cpu_rw = 1; #20; m2 = 1; #50;
        check(cpu_doe == 8'hFF && cpu_dout == 8'h77, "83 $5101 RAM"); m2 = 0; #50;
        cpu_a = 15'h5000; #20; m2 = 1; #50; check(cpu_doe == 8'h03 && cpu_dout[1:0] == 2'b00, "83 $5000 DIP"); m2 = 0;
        wr(16'h8300, 8'h11); wr(16'h8301, 8'h12); wr(16'h8302, 8'h13);
        cpu_a = 15'h4000; romsel_n = 0; #20; check(prg_a == {6'h13, 3'd0}, "83 8 KiB PRG $C000");
        cpu_a = 15'h6000; #20; check(prg_a == {6'h3F, 3'd0}, "83 last bank");
        wr(16'h8000, 8'h33);                                            // outer + 16 KiB mode
        cpu_a = 15'h2000; romsel_n = 0; #20; check(prg_a == {5'h13, 1'b1, 3'd0}, "83 16 KiB $8000");
        cpu_a = 15'h4000; #20; check(prg_a == {6'b111110, 3'd0}, "83 16 KiB $C000 = (bank & $30) | $0F");
        romsel_n = 1;
        wr(16'h8310, 8'h40); wr(16'h8311, 8'h41);                       // 2 KiB CHR mode (after $8000)
        ppu_a = 14'h0400; #20; check(chr_a == {8'h40, 1'b1}, "83 2 KiB CHR");
        wr(16'h8313, 8'h55);                                            // cancels 2 KiB mode for good
        ppu_a = 14'h0C00; #20; check(chr_a == {1'b1, 8'h55}, "83 1 KiB CHR (+outer bit)");
        wr(16'h8100, 8'h80); wr(16'h8200, 8'h03); wr(16'h8201, 8'h00);
        cycle; check(!irq, "83 IRQ counting"); cycle; check(irq, "83 IRQ at 0");
        wr(16'h8200, 8'h00); check(!irq, "83 IRQ ack");
        repeat (5) cycle; check(!irq && dut.e83 == 1'b0 && dut.c83 == 16'hFF00, "83 IRQ disabled itself ($FFFF, low byte rewritten by the ack)");

        // ---------------------------------------------------------------- 59
        map_id = 8'd59; reset_all;
        wr(16'h80DD, 8'h00);                                            // A7 16 KiB bank 5, CHR 5, H
        cpu_a = 15'h4000; romsel_n = 0; #20; check(prg_a == {6'd10, 3'd0}, "59 16 KiB mirrored at $C000");
        romsel_n = 1; ppu_a = 14'h0400; #20; check(chr_a == {6'd5, 3'd1}, "59 CHR 8 KiB");
        ppu_a = 14'h2800; #20; check(ciram_a10 == 1'b1, "59 horizontal");
        wr(16'h8160, 8'h00);                                            // A8: DIP reads, 32 KiB bank 3
        cpu_a = 15'h0000; romsel_n = 0; cpu_rw = 1; #20; m2 = 1; #50;
        check(!prg_rom_en && cpu_doe == 8'hFF && cpu_dout == 8'h00, "59 DIP read"); m2 = 0; romsel_n = 1;

        // ---------------------------------------------------------------- 116
        reset_all;
        cpu_a = 15'h4000; romsel_n = 0; #20; check(prg_a2 == {6'h3E, 3'd0}, "116 VRC2 $C000 = -2");
        wr(16'h8000, 8'h07); cpu_a = 15'h0000; romsel_n = 0; #20; check(prg_a2 == {6'd7, 3'd0}, "116 VRC2 PRG");
        wr(16'hB002, 8'h0A); wr(16'hB003, 8'h03); ppu_a = 14'h0400; #20; check(chr_a2 == 9'h03A, "116 VRC2 CHR nibbles");
        wr(16'hB800, 8'h05); ppu_a = 14'h0400; #20; check(chr_a2 == 9'h035, "116 VRC2 A11 also selects the odd register");
        wr(16'h4100, 8'h05);                                            // MMC3 + CHR A18
        wr(16'h8000, 8'h06); wr(16'h8001, 8'h0B);
        cpu_a = 15'h0000; romsel_n = 0; #20; check(prg_a2 == {6'd11, 3'd0}, "116 MMC3 R6");
        romsel_n = 1; ppu_a = 14'h1400; #20; check(chr_a2 == {1'b1, 8'd5}, "116 MMC3 R3 + outer");
        wr(16'h4101, 8'h02);                                            // MMC1 (reset)
        cpu_a = 15'h4000; romsel_n = 0; #20; check(prg_a2 == {6'b011110, 3'd0}, "116 MMC1 power-on: bank 15 at $C000");
        romsel_n = 1;
        for (n = 0; n < 5; n = n + 1) wr(16'hE000, {7'd0, n == 0 || n == 1});   // PRG = 3
        cpu_a = 15'h0000; romsel_n = 0; #20; check(prg_a2 == {6'd6, 3'd0}, "116 MMC1 serial PRG");
        romsel_n = 1;

        // ---------------------------------------------------------------- 209 (CHR latch)
        reset_all;
        wr(16'hD000, 8'h08);                                            // CHR mode 1 (4 KiB)
        wr(16'h9000, 8'h10); wr(16'h9002, 8'h20); wr(16'h9004, 8'h30); wr(16'h9006, 8'h40);
        ppu_a = 14'h0000; #40; check(chr_a3 == {8'h10, 2'd0}, "209 latch 0 at power-on");
        ppu_a = 14'h1000; #40; check(chr_a3 == {8'h30, 2'd0}, "209 latch 1 at power-on");
        ppu_read(14'h0FE8); #40; ppu_end; #100;
        ppu_a = 14'h0000; #40; check(chr_a3 == {8'h20, 2'd0}, "209 $0FE8 -> register 2");
        ppu_read(14'h1FE8); #40; ppu_end; #100;
        ppu_a = 14'h1000; #40; check(chr_a3 == {8'h40, 2'd0}, "209 $1FE8 -> register 6");
        ppu_read(14'h0FD8); #40; ppu_end; #100;
        ppu_a = 14'h0000; #40; check(chr_a3 == {8'h10, 2'd0}, "209 $0FD8 -> register 0");

        $display("PASS tb_pirate_direct: %0d checks", checks);
        $finish;
    end
    initial begin #50000000; $fatal(1, "watchdog"); end
endmodule
