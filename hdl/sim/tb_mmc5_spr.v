// tb_mmc5_spr.v — MMC5: CHR set A/B per fetch phase with 8x16 sprites, over whole scanlines.
// A scanline is 32 BG tiles (NT, AT, pattern lo/hi), 8 sprites (two garbage reads + pattern lo/hi), 2 prefetched
// tiles and the two dummy NT reads. The garbage reads of the sprite phase are generated three ways: NT + attribute
// (Mesen2), NT + NT at the same address, and NT + NT with the first sprite's two addresses different (the NES
// reloads v at dot 257; seen on the console with Uchuu Keibitai SDF: sprites after the 4th one, and then only the
// 8th one, took the BG set). Sprites must use set A and the background set B in both cases, sampled at the start and at the
// end of every pattern read (the slot must not change in the middle of a read).
`timescale 1ns/1ps

module tb_mmc5_spr;
    reg  [14:0] cpu_a = 0;
    reg  [7:0]  cpu_d = 0;
    reg         romsel_n = 1, cpu_rw = 1, m2 = 0;
    reg  [13:0] ppu_a = 0;
    reg         ppu_rd_n = 1, ppu_wr_n = 1;
    reg  [7:0]  cfg = 0;
    reg         rst = 0, clk = 0;
    wire [18:10] prg_a;
    wire        prg_rom_en, prg_ram_en, prg_wr;
    wire [18:10] chr_a;
    wire        chr_en, chr_wr, ciram_en, ciram_a10, irq, chr_raw;
    wire [7:0] cpu_dout, cpu_doe, ppu_dout, ppu_doe;
    reg [7:0] ppu_din = 0;
    wire [9:0]  snd;

    mapper_mmc5 dut (
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(romsel_n), .cpu_rw(cpu_rw), .m2(m2),
        .ppu_din(ppu_din),.ppu_dout(ppu_dout),.ppu_doe(ppu_doe),.ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n),
        .cfg(cfg), .rst(rst), .clk(clk), .map_id(8'd5), .chr_size(6'h3F),
        .prg_a(prg_a), .prg_rom_en(prg_rom_en), .prg_ram_en(prg_ram_en), .prg_wr(prg_wr),
        .chr_a(chr_a), .chr_en(chr_en), .chr_wr(chr_wr), .ciram_en(ciram_en), .ciram_a10(ciram_a10),
        .irq(irq), .chr_raw(chr_raw), .cpu_dout(cpu_dout), .cpu_doe(cpu_doe), .snd(snd));

    always #10 clk = ~clk;

    integer errors = 0, checks = 0;
    reg checking = 0;
    task check(input cond, input [8*80-1:0] msg);
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; $display("FALLO: %0s", msg); end end
    endtask

    task wreg(input [15:0] addr, input [7:0] d);
        begin
            m2 = 0; romsel_n = 1; cpu_rw = 0; cpu_a = addr[14:0]; cpu_d = d; #280;
            m2 = 1; #240; m2 = 0; #40; cpu_rw = 1;
        end
    endtask

    // one PPU read; for pattern reads, the CHR 1 KiB page must be `want` at the start and at the end of /RD low
    task rd(input [13:0] a, input pat, input [8:0] want, input [8*24-1:0] what);
        begin
            ppu_rd_n = 1; ppu_a = a; #100; ppu_rd_n = 0; #20;
            if (checking && pat) begin
                check(chr_a === want, what);
                if (chr_a !== want) $display("   %0s inicio: chr_a=%03h esperado %03h slot=%0d", what, chr_a, want, dut.fetch_index);
            end
            #120;
            if (checking && pat) begin
                check(chr_a === want, what);
                if (chr_a !== want) $display("   %0s final: chr_a=%03h esperado %03h slot=%0d", what, chr_a, want, dut.fetch_index);
            end
            ppu_rd_n = 1; #20;
        end
    endtask

    localparam [8:0] BG = 9'h020, SPR = 9'h010;   // $5128 (set B, $1000 -> B0) and $5120 (set A, $0000 -> A0)
    integer k;
    task line(input [1:0] nt_nt);
        begin
            for (k = 0; k < 32; k = k + 1) begin
                rd(14'h2002 + k, 0, 0, "");
                rd(14'h23C0, 0, 0, "");
                rd(14'h1000, 1, BG, "fondo lo");
                rd(14'h1008, 1, BG, "fondo hi");
            end
            for (k = 0; k < 8; k = k + 1) begin
                rd((nt_nt == 2 && k == 0) ? 14'h2021 : 14'h2002, 0, 0, "");
                rd(nt_nt != 0 ? 14'h2002 : 14'h23C0, 0, 0, "");
                rd(14'h0000, 1, SPR, "sprite lo");
                rd(14'h0008, 1, SPR, "sprite hi");
            end
            for (k = 0; k < 2; k = k + 1) begin
                rd(14'h2000 + k, 0, 0, "");
                rd(14'h23C0, 0, 0, "");
                rd(14'h1000, 1, BG, "precarga lo");
                rd(14'h1008, 1, BG, "precarga hi");
            end
            rd(14'h2002, 0, 0, ""); rd(14'h2002, 0, 0, "");      // dummy NT reads (337, 339)
        end
    endtask

    integer mode, n;
    initial begin
        wreg(16'h5101, 3);                                     // 1 KiB CHR pages
        for (n = 0; n < 4; n = n + 1) wreg(16'h5128 + n, 8'h20 + n);
        for (n = 0; n < 8; n = n + 1) wreg(16'h5120 + n, 8'h10 + n);
        wreg(16'h2000, 8'h20);                                  // PPUCTRL: 8x16 sprites
        for (mode = 0; mode < 3; mode = mode + 1) begin
            checking = 0;
            line(mode[1:0]); line(mode[1:0]);                   // frame start: lines are recognised from here
            checking = 1;
            line(mode[1:0]); line(mode[1:0]); line(mode[1:0]);
            check(dut.in_frame, "dentro del fotograma");
            $display("%0s: %0d comprobaciones, %0d fallos", mode == 2 ? "basura NT+NT, el 1.er sprite con dos direcciones" :
                     mode ? "basura NT+NT (NES)" : "basura NT+AT (Mesen2)",
                     checks, errors);
            repeat (4) wreg(16'h5205, 0);                        // CPU without PPU reads: leaves the frame
        end
        if (errors) $fatal(1, "MMC5 8x16 sprite set failures: %0d", errors);
        $display("PASS tb_mmc5_spr: %0d checks", checks);
        $finish;
    end
endmodule
