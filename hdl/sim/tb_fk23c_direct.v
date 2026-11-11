`timescale 1ns/1ps
// Direct test of mapper_fk23c.v (mapper 176, Waixing FK23C). Standalone; built by make sim.
// Expected values follow the FK23C register facts (also checked against Mesen2 by fuzz.py).
module tb_fk23c_direct;
    reg [14:0] cpu_a = 0;
    reg [7:0]  cpu_d = 0, cfg = 0, map_id = 176;
    reg romsel_n = 1, cpu_rw = 1, m2 = 0, rst = 0, clk = 0;
    reg [13:0] ppu_a = 0;
    reg ppu_rd_n = 1, ppu_wr_n = 1;
    wire [18:10] prg_a, chr_a;
    wire prg_rom_en, prg_ram_en, prg_wr, chr_en, chr_wr, ciram_en, ciram_a10, irq, chr_raw;
    mapper_fk23c dut(.*);
    always #10 clk = ~clk;

    integer checks = 0, i;
    task check(input ok, input [640:0] msg);
        begin checks = checks + 1; if (!ok) $fatal(1, "FK23C: %0s", msg); end
    endtask
    task cycle;   begin #100; m2 = 1; #500; m2 = 0; #400; end endtask
    task wr(input [15:0] a, input [7:0] d);
        begin cpu_a = a[14:0]; romsel_n = !a[15]; cpu_d = d; cpu_rw = 0; cycle; cpu_rw = 1; #100; end
    endtask
    task bank(input [7:0] n, input [7:0] d); begin wr(16'h8000, n); wr(16'h8001, d); end endtask
    task ep(input [15:0] a, input [5:0] b);
        begin cpu_a = a[14:0]; romsel_n = !a[15]; cpu_rw = 1; #100;
              check(prg_a == {b, a[12:10]} && prg_rom_en == a[15], "PRG bank"); end
    endtask
    task ec(input [13:0] a, input [8:0] b, input raw);
        begin ppu_a = a; #100; check(chr_a == b && chr_raw == raw, "CHR bank / RAM select"); end
    endtask
    // RAM access at a CPU address: expected enable, write enable and 8 KiB bank
    task er(input [15:0] a, input wr_cycle, input en, input we, input [1:0] b);
        begin cpu_a = a[14:0]; romsel_n = 1; cpu_rw = !wr_cycle; #50; m2 = 1; #100;
              check(prg_ram_en == en && prg_wr == we, "WRAM enable / write");
              if (en) check(prg_a[14:13] == b && prg_a[18:15] == 0, "WRAM bank");
              m2 = 0; cpu_rw = 1; #100; end
    endtask
    task a12pulse; begin ppu_a = 0; repeat (5) cycle; ppu_a = 14'h1000; #400; end endtask

    initial begin
        rst = 1; repeat (3) cycle; rst = 0; cycle;

        // ---- power-on: mode 0, MMC3 defaults, vertical mirroring, no WRAM
        ep(16'h8000, 0); ep(16'ha000, 1); ep(16'hc000, 62); ep(16'he000, 63);
        for (i = 0; i < 8; i = i + 1) ec(i * 1024, i, 0);
        ppu_a = 14'h2400; #100; check(ciram_a10, "vertical at power-on");
        er(16'h6000, 0, 0, 0, 0);

        // ---- only $5xxx with A4=1 are FK23 registers ($7xxx and A4=0 are not)
        wr(16'h7012, 8'h20); ec(0, 0, 0);
        wr(16'h5002, 8'h20); ec(0, 0, 0);
        wr(16'h5012, 8'h20); ec(0, 9'h100, 0);           // CHR base $20 -> outer $100
        wr(16'h5012, 8'h00); ec(0, 0, 0);

        // ---- PRG modes 5-7 keep the previous mapping
        bank(6, 5); ep(16'h8000, 5);
        wr(16'h5010, 8'h05); ep(16'h8000, 5);
        bank(6, 9);          ep(16'h8000, 5);            // frozen
        wr(16'h5010, 8'h07); ep(16'h8000, 5);
        wr(16'h5010, 8'h00); ep(16'h8000, 9);            // mode 0 again: follows r6

        // ---- inner mask by mode and outer base (non-extended)
        // mode 1: inner mask $1F; base 3 (<<1 = 6) lies inside the mask, so only r6 shows
        wr(16'h5011, 8'h03); wr(16'h5010, 8'h01); ep(16'h8000, 9);
        // base $10 (<<1 = $20) is outside the mask and becomes the outer bank
        wr(16'h5011, 8'h10);
        ep(16'h8000, 6'h29); ep(16'hc000, 6'h3e); ep(16'he000, 6'h3f);
        // ---- mode 3 (16 KiB mirrored) and mode 4 (32 KiB)
        wr(16'h5011, 8'h03); wr(16'h5010, 8'h03);
        ep(16'h8000, 6); ep(16'ha000, 7); ep(16'hc000, 6); ep(16'he000, 7);
        wr(16'h5010, 8'h04);
        ep(16'h8000, 4); ep(16'ha000, 5); ep(16'hc000, 6); ep(16'he000, 7);

        // ---- extended MMC3: r8/r9 at $C000/$E000, OR'ed with the base; A14 inversion swaps 0/2
        wr(16'h5011, 8'h00); wr(16'h5010, 8'h00); wr(16'h5013, 8'h02);
        bank(6, 8'h11); bank(7, 8'h12); bank(8, 8'h13); bank(9, 8'h14);
        ep(16'h8000, 6'h11); ep(16'ha000, 6'h12); ep(16'hc000, 6'h13); ep(16'he000, 6'h14);
        wr(16'h8000, 8'h40);
        ep(16'h8000, 6'h13); ep(16'ha000, 6'h12); ep(16'hc000, 6'h11); ep(16'he000, 6'h14);
        // extended CHR order r0,r10,r1,r11,r2..r5
        bank(0, 8'h20); bank(10, 8'h21); bank(1, 8'h22); bank(11, 8'h23);
        ec(14'h0000, 9'h020, 0); ec(14'h0400, 9'h021, 0); ec(14'h0800, 9'h022, 0); ec(14'h0c00, 9'h023, 0);
        wr(16'h8000, 8'h80);                             // CHR A12 inversion
        ec(14'h1000, 9'h020, 0); ec(14'h1400, 9'h021, 0);
        wr(16'h8000, 8'h00); wr(16'h5013, 8'h00);

        // ---- CNROM / direct CHR mode
        wr(16'h5012, 8'h04); wr(16'h5010, 8'h40); wr(16'h5013, 8'h04);   // base 4, direct, cnrom
        ec(14'h0000, 9'h020, 0); ec(14'h1c00, 9'h027, 0);
        wr(16'h9000, 8'h02); ec(14'h0000, 9'h030, 0);                     // (2 & 3) | 4 = 6 -> 6<<3
        wr(16'hb000, 8'h01); ec(14'h0000, 9'h030, 0);                     // $A000-$BFFF: no latch
        wr(16'h5013, 8'h00); wr(16'h5010, 8'h00); wr(16'h5012, 8'h00);

        // ---- mirroring and single screen (needs $A001 bit5 + bit3)
        wr(16'ha000, 1); ppu_a = 14'h2800; #100; check(ciram_a10, "horizontal");
        wr(16'ha000, 3); ppu_a = 14'h2000; #100; check(!ciram_a10, "single screen needs $A001.3 -> horizontal");
        wr(16'ha001, 8'h28); ppu_a = 14'h2000; #100; check(ciram_a10, "screen B");
        wr(16'ha000, 2); #100; check(!ciram_a10, "screen A");
        wr(16'ha001, 8'h08); wr(16'ha000, 2); ppu_a = 14'h2400; #100;
        check(ciram_a10, "bit5 clear masks single screen -> vertical");
        wr(16'ha000, 0);

        // ---- WRAM
        wr(16'ha001, 8'h80);                              // enable, bank 0
        er(16'h6000, 1, 1, 1, 0); er(16'h6000, 0, 1, 0, 0);
        er(16'h5800, 0, 0, 0, 0);                          // no $4000-$5FFF without the config
        wr(16'ha001, 8'hc0);                              // write protected (and FK regs on)
        er(16'h6000, 1, 0, 0, 0); er(16'h6000, 0, 1, 0, 0);
        wr(16'ha001, 8'ha2);                              // config: $6000 = bank 2, $4000 = bank 3
        er(16'h6000, 1, 1, 1, 2); er(16'h4800, 1, 1, 1, 3);
        er(16'h5000, 1, 1, 1, 3);                          // $5xxx is RAM while FK regs are off
        wr(16'h5012, 8'h20); ec(0, 9'h020, 0);             // ... so it is no longer a register (r0=$20)
        er(16'h4010, 0, 0, 0, 0);                          // $4000-$401F never
        wr(16'ha001, 8'he3);                              // config + FK regs: bank 3, $4000 = bank 0
        er(16'h6000, 1, 1, 1, 3); er(16'h4800, 1, 1, 1, 0);
        er(16'h5000, 1, 0, 0, 0);                          // $5xxx write goes to the register
        er(16'h5000, 0, 1, 0, 0);                          // ... but reads are RAM
        wr(16'ha001, 8'h00); er(16'h6000, 0, 0, 0, 0);

        // ---- CHR-RAM: select bit, RAM in the first CHR bank, CHR-RAM-only cartridges
        bank(0, 8'h00);
        wr(16'h5010, 8'h20); ec(14'h0400, 9'h101, 1);
        ppu_a = 14'h0400; ppu_wr_n = 0; #100; check(chr_wr, "CHR-RAM writable"); ppu_wr_n = 1;
        wr(16'h5010, 8'h00); ec(14'h0400, 9'h001, 0);
        ppu_wr_n = 0; #100; check(!chr_wr, "CHR-ROM not writable"); ppu_wr_n = 1;
        wr(16'ha001, 8'h24); ec(14'h0400, 9'h101, 1);     // pages 0-7 -> RAM
        bank(2, 8'h08); ec(14'h1000, 9'h008, 0);          // page 8 stays ROM
        wr(16'ha001, 8'h00); bank(2, 8'h04);
        cfg = 8'h80; ec(14'h1000, 9'h104, 1); cfg = 0;

        // ---- IRQ: 2 CPU cycles after reaching 0; $E000 is the only acknowledge
        wr(16'hc000, 1); wr(16'hc001, 0); wr(16'he001, 0);
        a12pulse; cycle; cycle; check(!irq, "reload to latch 1 does not fire");
        a12pulse; check(!irq, "counter 0: not yet (delay)");
        cycle; check(!irq, "one CPU cycle later");
        cycle; check(irq, "asserted after 2 CPU cycles");
        repeat (3) cycle; check(irq, "held until $E000");
        wr(16'he000, 0); #200; check(!irq, "$E000 acknowledges");
        wr(16'he001, 0); wr(16'hc000, 0); wr(16'hc001, 0);
        a12pulse;                                         // latch 0: fires on every rise
        wr(16'he000, 0);                                  // disable inside the delay window
        cycle; cycle; check(irq, "delayed IRQ still asserts after $E000");
        wr(16'he000, 0); #200; check(!irq, "second $E000 acknowledges");
        a12pulse; repeat (3) cycle; check(!irq, "disabled: no new IRQ");

        rst = 1; cycle; rst = 0; cycle;
        ep(16'h8000, 0); ec(0, 0, 0); check(!irq, "reset");
        $display("PASS tb_fk23c_direct: %0d checks", checks); $finish;
    end
    initial begin #20000000; $fatal(1, "watchdog"); end
endmodule
