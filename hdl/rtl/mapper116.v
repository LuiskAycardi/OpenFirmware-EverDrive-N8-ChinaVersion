`timescale 1ns/1ps
// mapper116.v — Mapper 116 (SOMARI-P / Huang Di: VRC2 + MMC3 + MMC1 clones on one board). Own
// implementation (clean room) from the NESdev Wiki description; behaviour checked against Mesen2 (bench
// oracle, source read for facts only).
//
// $4100-$7FFF with A8 = 1 (addr & $4100 = $4100): mode register. D1-D0 = active chip (0 VRC2, 1 MMC3,
//   2/3 MMC1), D2 = CHR A18 (VRC2/MMC3 only). With A0 = 1 the MMC1 is also reset (control = $0C, PRG = 0,
//   shift register cleared). The whole $4100-$7FFF range is the register window (no PRG-RAM writes).
// $8000-$FFFF go to the active chip, each keeping its own registers:
//   VRC2: $8000 / $A000 = 8 KiB PRG ($C000/$E000 = last two), $9000 D0 = mirroring (1 H), $B000-$E003 =
//         eight 1 KiB CHR registers written by nibbles (A1 selects the odd register, A0 the high nibble).
//   MMC3: usual select/data/mirroring/IRQ ports; only R0-R7 are writable (the two fixed PRG slots are -2/-1).
//         Scanline IRQ on filtered PPU A12 rises, only counted while the MMC3 is the active chip.
//   MMC1: serial port (no consecutive-write filter); 16 KiB mode fixes bank 15 at $C000.
module mapper116 (
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
    reg [7:0] mode = 0;
    reg [7:0] vc [0:7];
    reg [7:0] vp0 = 0, vp1 = 8'd1, vmir = 0;
    reg [7:0] mr [0:7];                          // MMC3 R0-R7
    reg [7:0] mctl = 0, mmir = 0, ilatch = 0;
    reg       ien = 0, rtgl = 0;
    reg [4:0] m1 [0:3];
    reg [4:0] m1buf = 0;
    reg [2:0] m1sh = 0;
    integer i;
    task init_regs;
        begin
            mode = 0; vp0 = 0; vp1 = 1; vmir = 0; mctl = 0; mmir = 0; ilatch = 0; ien = 0;
            for (i = 0; i < 4; i = i + 1) vc[i] = 8'hFF;
            for (i = 4; i < 8; i = i + 1) vc[i] = i[7:0];
            mr[0] = 0; mr[1] = 2; mr[2] = 4; mr[3] = 5; mr[4] = 6; mr[5] = 7; mr[6] = 8'hFC; mr[7] = 8'hFD;
            m1[0] = 5'h0C; m1[1] = 0; m1[2] = 0; m1[3] = 0; m1buf = 0; m1sh = 0;
        end
    endtask
    initial init_regs;

    wire [15:0] addr = {!romsel_n, cpu_a};
    wire rom_wr = !romsel_n && !cpu_rw;
    wire mode_wr = romsel_n && !cpu_rw && cpu_a[14] && cpu_a[8];        // $4100-$7FFF, A8 = 1
    wire [2:0] vslot = {cpu_a[13:12], cpu_a[11] | cpu_a[1]} + 3'd2;
    reg [4:0] nb;

    always @(negedge m2) begin
        if (rst) begin
            mode <= 0; vp0 <= 0; vp1 <= 1; vmir <= 0; mctl <= 0; mmir <= 0; ilatch <= 0; ien <= 0;
            for (i = 0; i < 4; i = i + 1) vc[i] <= 8'hFF;
            for (i = 4; i < 8; i = i + 1) vc[i] <= i[7:0];
            mr[0] <= 0; mr[1] <= 2; mr[2] <= 4; mr[3] <= 5; mr[4] <= 6; mr[5] <= 7; mr[6] <= 8'hFC; mr[7] <= 8'hFD;
            m1[0] <= 5'h0C; m1[1] <= 0; m1[2] <= 0; m1[3] <= 0; m1buf <= 0; m1sh <= 0;
        end else if (mode_wr) begin
            mode <= cpu_d;
            if (cpu_a[0]) begin m1[0] <= 5'h0C; m1[3] <= 0; m1buf <= 0; m1sh <= 0; end
        end else if (rom_wr) case (mode[1:0])
            2'd0: if (addr >= 16'hB000 && addr <= 16'hE003) begin
                      if (cpu_a[0]) vc[vslot] <= {cpu_d[3:0], vc[vslot][3:0]};
                      else          vc[vslot] <= {vc[vslot][7:4], cpu_d[3:0]};
                  end else case (cpu_a[14:12])
                      3'd0: vp0 <= cpu_d;
                      3'd2: vp1 <= cpu_d;
                      3'd1: vmir <= cpu_d;
                      default: ;
                  endcase
            2'd1: case ({cpu_a[14:13], cpu_a[0]})
                      3'b000: mctl <= cpu_d;
                      3'b001: mr[mctl[2:0]] <= cpu_d;
                      3'b010: mmir <= cpu_d;
                      3'b100: ilatch <= cpu_d;
                      3'b101: rtgl <= ~rtgl;
                      3'b110: ien <= 1'b0;
                      3'b111: ien <= 1'b1;
                      default: ;
                  endcase
            default: if (cpu_d[7]) begin
                      m1[0] <= m1[0] | 5'h0C; m1buf <= 0; m1sh <= 0;
                  end else begin
                      nb = m1buf | ({4'd0, cpu_d[0]} << m1sh);
                      if (m1sh == 3'd4) begin m1[cpu_a[14:13]] <= nb; m1buf <= 0; m1sh <= 0; end
                      else begin m1buf <= nb; m1sh <= m1sh + 3'd1; end
                  end
        endcase
    end

    // ------------------------------------------------------------------ PRG
    reg [5:0] b8;
    wire [3:0] m1b = m1[3][3:0];
    always @(*) begin
        case (mode[1:0])
            2'd0: case (cpu_a[14:13])
                      2'd0: b8 = vp0[5:0]; 2'd1: b8 = vp1[5:0]; 2'd2: b8 = 6'h3E; default: b8 = 6'h3F;
                  endcase
            2'd1: case (cpu_a[14:13])
                      2'd0: b8 = mctl[6] ? 6'h3E : mr[6][5:0];
                      2'd1: b8 = mr[7][5:0];
                      2'd2: b8 = mctl[6] ? mr[6][5:0] : 6'h3E;
                      default: b8 = 6'h3F;
                  endcase
            default: if (m1[0][3]) begin
                         if (m1[0][2]) b8 = cpu_a[14] ? {1'b0, 4'hF, cpu_a[13]} : {1'b0, m1b, cpu_a[13]};
                         else          b8 = cpu_a[14] ? {1'b0, m1b, cpu_a[13]} : {5'd0, cpu_a[13]};
                     end else b8 = {1'b0, m1b[3:1], cpu_a[14:13]};
        endcase
    end
    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]} : {b8, cpu_a[12:10]};
    assign prg_rom_en = !romsel_n;
    // $6000-$7FFF: writes are register writes, so the RAM is never written; reads still see it (the
    // oracle reads its never-written work RAM; Kart Fighter depends on it).
    assign prg_ram_en = romsel_n && cpu_a[14:13] == 2'b11 && m2 && cpu_rw;
    assign prg_wr     = 1'b0;

    // ------------------------------------------------------------------ CHR and mirroring
    reg [8:0] cb;
    wire [2:0] ms = ppu_a[12:10] ^ {mctl[7], 2'b00};
    always @(*) begin
        case (mode[1:0])
            2'd0: cb = {mode[2], vc[ppu_a[12:10]]};
            2'd1: case (ms)
                      3'd0: cb = {mode[2], mr[0][7:1], 1'b0};
                      3'd1: cb = {mode[2], mr[0][7:1], 1'b1};
                      3'd2: cb = {mode[2], mr[1][7:1], 1'b0};
                      3'd3: cb = {mode[2], mr[1][7:1], 1'b1};
                      3'd4: cb = {mode[2], mr[2]};
                      3'd5: cb = {mode[2], mr[3]};
                      3'd6: cb = {mode[2], mr[4]};
                      default: cb = {mode[2], mr[5]};
                  endcase
            default: cb = m1[0][4] ? {2'd0, (ppu_a[12] ? m1[2] : m1[1]), ppu_a[11:10]}
                                   : {2'd0, m1[1][4:1], ppu_a[12:10]};
        endcase
    end
    assign chr_a    = cfg[7] ? {6'd0, ppu_a[12:10]} : cb;
    assign chr_en   = !ppu_a[13];
    assign chr_wr   = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en = ppu_a[13];
    reg a10;
    always @(*) begin
        case (mode[1:0])
            2'd0: a10 = vmir[0] ? ppu_a[11] : ppu_a[10];
            2'd1: a10 = mmir[0] ? ppu_a[11] : ppu_a[10];
            default: case (m1[0][1:0])
                         2'd0: a10 = 1'b0; 2'd1: a10 = 1'b1; 2'd2: a10 = ppu_a[10]; default: a10 = ppu_a[11];
                     endcase
        endcase
    end
    assign ciram_a10 = a10;

    // ------------------------------------------------------------------ MMC3 scanline IRQ (clk domain)
    // Counted on filtered PPU A12 rises (a12_filter.v), only while the MMC3 is the active chip.
    // Known difference (Kart Fighter): the oracle freezes its A12 watcher outside MMC3 mode and also
    // reacts to a PPU address notification that does not change the address; neither is visible on
    // the cartridge bus, so here the IRQ the game arms before leaving MMC3 mode does not fire.
    wire a12_clk, m2f_unused;
    a12_filter #(.LOW_M2(4), .W(3)) flt (.clk(clk), .m2(m2), .a12(ppu_a[12]), .a12_clk(a12_clk), .m2_fall(m2f_unused));
    reg [2:0] rel_s = 0; reg [1:0] en_s = 0, md_s = 0;
    reg [7:0] counter = 0; reg reload = 0, pending = 0;
    wire [7:0] next = (counter == 8'd0 || reload) ? ilatch : counter - 8'd1;
    always @(posedge clk) begin
        rel_s <= {rel_s[1:0], rtgl}; en_s <= {en_s[0], ien}; md_s <= {md_s[0], mode[1:0] == 2'd1};
        if (rst) begin counter <= 0; reload <= 0; pending <= 0; end
        else begin
            if (rel_s[2] != rel_s[1]) reload <= 1'b1;
            else if (a12_clk && md_s[1]) begin
                counter <= next; reload <= 1'b0;
                if (next == 8'd0 && en_s[1]) pending <= 1'b1;
            end
            if (!en_s[1]) pending <= 1'b0;
        end
    end
    assign irq = pending;
endmodule
