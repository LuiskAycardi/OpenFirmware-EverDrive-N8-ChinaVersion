`timescale 1ns/1ps
// mapper_pirate.v — Pirate boards without an MMC3 core. Own implementation (clean room); register facts
// from the NESdev Wiki pages, behaviour checked against Mesen2 (the bench oracle; its source was read
// for facts only).
//
//  59 (BMC-T3H53 / D1038 multicarts): the write ADDRESS ($8000-$FFFF) is the register:
//     A7 = 1: 16 KiB bank A6-A4 at $8000 and $C000; A7 = 0: 32 KiB bank A6-A5.
//     A2-A0 = 8 KiB CHR bank, A3 = mirroring (1 H, 0 V), A8 = 1: ROM reads return the DIP switches (0).
//  83 (Cony / Yoko fighting games): full-address decode as the oracle:
//     $8000 = outer bank + 16 KiB mode + 2 KiB CHR mode, $B000/$B0FF/$B1FF = outer bank + 16 KiB mode,
//     $8100 = mode (D1-D0 mirroring, D7 IRQ enable source), $8200/$8201 = IRQ counter low/high,
//     $8300-$8302 = 8 KiB PRG ($8000/$A000/$C000; leaves 16 KiB mode), $8310-$8317 = 1 KiB CHR
//     ($8312-$8315 cancel the 2 KiB mode for good), $5100-$5103 = 4 bytes of RAM, $5000 D1-D0 = DIP (0).
//     IRQ: CPU-cycle down-counter; at 0 it fires once and disables itself.
// 253 (Waixing Dragon Ball): $8010/$A010 = 8 KiB PRG, $9400 = mirroring, $B000-$E00C = nibble-wide 1 KiB
//     CHR registers (low byte + 4 high bits); banks 4/5 are 2 KiB of CHR-RAM unless $B000 = $88
//     forced CHR-ROM ($C8 releases it). The CHR-ROM fills 512 KiB, so the RAM is an M4K here and the
//     FPGA drives the PPU bus for it (like the MMC5 ExRAM). IRQ: every 114 CPU cycles the counter
//     counts up; on wrap it reloads ($F000/$F004 nibbles) and fires; $F008 D1 = enable.
module mapper_pirate (
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
    input  wire [5:0]  chr_size,
    output wire [18:10] prg_a,
    output wire        prg_rom_en,
    output wire        prg_ram_en,
    output wire        prg_wr,
    output wire [18:10] chr_a,
    output wire        chr_en,
    output wire        chr_wr,
    output wire        ciram_en,
    output wire        ciram_a10,
    output wire        irq,
    output wire        chr_raw,
    output wire [7:0]  cpu_dout,
    output wire [7:0]  cpu_doe,
    input  wire [7:0]  ppu_din,
    output wire [7:0]  ppu_dout,
    output wire [7:0]  ppu_doe
);
    wire m59 = map_id == 8'd59, m83 = map_id == 8'd83, m253 = map_id == 8'd253;
    wire [15:0] addr = {!romsel_n, cpu_a};
    wire rom_wr = !romsel_n && !cpu_rw;
    wire lo_wr  = romsel_n && !cpu_rw;
    integer i;

    // ------------------------------------------------------------------ 59
    reg [8:0] l59 = 9'd0;

    // ------------------------------------------------------------------ 83
    reg [7:0] r83 [0:10];
    reg [7:0] x83 [0:3];
    reg [7:0] mode83 = 0, bank83 = 0;
    reg       k2 = 0, nk2 = 0;
    reg [15:0] c83 = 0;
    reg       e83 = 0;
    initial begin for (i = 0; i < 11; i = i + 1) r83[i] = 0; for (i = 0; i < 4; i = i + 1) x83[i] = 0; end

    // ------------------------------------------------------------------ 253
    reg [7:0] p253a = 0, p253b = 0, cl [0:7];
    reg [3:0] ch [0:7];
    reg [1:0] mir253 = 0;
    reg       force_rom = 0;
    reg [7:0] rl253 = 0, c253 = 0;
    reg [6:0] sc253 = 0;
    reg       e253 = 0;
    initial for (i = 0; i < 8; i = i + 1) begin cl[i] = 0; ch[i] = 0; end

    reg pend = 1'b0;
    reg [15:0] t83; reg te83, tp, te253; reg [7:0] t253; reg [6:0] ts253; reg [7:0] nl; reg [2:0] slot;

    always @(negedge m2) begin
        if (rst) begin
            l59 <= 9'd0;
            for (i = 0; i < 11; i = i + 1) r83[i] <= 0;
            for (i = 0; i < 4; i = i + 1) x83[i] <= 0;
            mode83 <= 0; bank83 <= 0; k2 <= 0; nk2 <= 0; c83 <= 0; e83 <= 0;
            p253a <= 0; p253b <= 0; mir253 <= {1'b0, !cfg[0]};             // header mirroring until $9400 force_rom <= 0; rl253 <= 0; c253 <= 0; sc253 <= 0; e253 <= 0;
            for (i = 0; i < 8; i = i + 1) begin cl[i] <= 0; ch[i] <= 0; end
            pend <= 1'b0;
        end else begin
            tp = pend;
            // ---------------------------------------------- 59
            if (m59 && rom_wr) l59 <= cpu_a[8:0];
            // ---------------------------------------------- 83
            t83 = c83; te83 = e83;
            if (m83 && lo_wr && addr[15:2] == 14'h1440) x83[cpu_a[1:0]] <= cpu_d;       // $5100-$5103
            if (m83 && rom_wr) begin
                if (addr >= 16'h8300 && addr <= 16'h8302) begin
                    mode83[6] <= 1'b0; r83[8 + addr[1:0]] <= cpu_d;
                end else if (addr[15:3] == 13'h1062) begin                                // $8310-$8317
                    r83[addr[2:0]] <= cpu_d;
                    if (addr[3:0] >= 4'h2 && addr[3:0] <= 4'h5) nk2 <= 1'b1;
                end else case (addr)
                    16'h8000: begin k2 <= 1'b1; bank83 <= cpu_d; mode83[6] <= 1'b1; end
                    16'hB000, 16'hB0FF, 16'hB1FF: begin bank83 <= cpu_d; mode83[6] <= 1'b1; end
                    16'h8100: mode83 <= {cpu_d[7], cpu_d[6] | mode83[6], cpu_d[5:0]};
                    16'h8200: begin t83[7:0] = cpu_d; tp = 1'b0; end
                    16'h8201: begin te83 = mode83[7]; t83[15:8] = cpu_d; end
                    default: ;
                endcase
            end
            if (m83 && te83) begin
                t83 = t83 - 16'd1;
                if (t83 == 16'd0) begin te83 = 1'b0; t83 = 16'hFFFF; tp = 1'b1; end
            end
            c83 <= t83; e83 <= te83;
            // ---------------------------------------------- 253
            t253 = c253; ts253 = sc253; te253 = e253;
            if (m253 && rom_wr) begin
                if (addr >= 16'hB000 && addr <= 16'hE00C) begin
                    slot = {addr[13:12], addr[11] | addr[3]} + 3'd2;
                    nl = addr[2] ? {cpu_d[3:0], cl[slot][3:0]} : (cl[slot] & 8'hF0) | cpu_d;
                    cl[slot] <= nl;
                    if (addr[2]) ch[slot] <= cpu_d[7:4];
                    if (slot == 3'd0 && nl == 8'hC8) force_rom <= 1'b0;
                    if (slot == 3'd0 && nl == 8'h88) force_rom <= 1'b1;
                end else case (addr)
                    16'h8010: p253a <= cpu_d;
                    16'hA010: p253b <= cpu_d;
                    16'h9400: mir253 <= cpu_d[1:0];
                    16'hF000: begin rl253[3:0] <= cpu_d[3:0]; tp = 1'b0; end
                    16'hF004: begin rl253[7:4] <= cpu_d[3:0]; tp = 1'b0; end
                    16'hF008: begin t253 = rl253; te253 = cpu_d[1]; ts253 = 7'd0; tp = 1'b0; end
                    default: ;
                endcase
            end
            if (m253 && te253) begin
                if (ts253 >= 7'd113) begin
                    ts253 = 7'd0; t253 = t253 + 8'd1;
                    if (t253 == 8'd0) begin t253 = rl253; tp = 1'b1; end
                end else ts253 = ts253 + 7'd1;
            end
            c253 <= t253; sc253 <= ts253; e253 <= te253;
            pend <= tp;
        end
    end
    assign irq = pend;

    // ------------------------------------------------------------------ PRG
    wire win6 = romsel_n && cpu_a[14:13] == 2'b11;
    reg [5:0] b8;
    always @(*) begin
        b8 = 6'd0;
        if (m59) b8 = l59[7] ? {1'b0, l59[6:4], cpu_a[13]} : {1'b0, l59[6:5], cpu_a[14:13]};
        if (m83) begin
            if (mode83[6]) b8 = cpu_a[14] ? {bank83[4], 4'b1111, cpu_a[13]} : {bank83[4:0], cpu_a[13]};
            else case (cpu_a[14:13])
                2'd0: b8 = r83[8][5:0];
                2'd1: b8 = r83[9][5:0];
                2'd2: b8 = r83[10][5:0];
                default: b8 = 6'h3F;
            endcase
        end
        if (m253) case (cpu_a[14:13])
            2'd0: b8 = p253a[5:0];
            2'd1: b8 = p253b[5:0];
            2'd2: b8 = 6'h3E;
            default: b8 = 6'h3F;
        endcase
    end
    wire dip59 = m59 && l59[8];                      // ROM reads return the DIP switches (0)
    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]} : {b8, cpu_a[12:10]};
    assign prg_rom_en = !romsel_n && !(dip59 && cpu_rw);
    assign prg_ram_en = win6 && m2 && (m83 || m253);
    assign prg_wr     = prg_ram_en && !cpu_rw;

    // ------------------------------------------------------------------ CPU reads
    wire rd   = cpu_rw && m2;
    wire r5000 = m83 && rd && romsel_n && cpu_a == 15'h5000;
    wire r5100 = m83 && rd && romsel_n && cpu_a[14:2] == 13'h1440;
    wire rdip = dip59 && rd && !romsel_n;
    assign cpu_dout = r5100 ? x83[cpu_a[1:0]] : 8'h00;
    assign cpu_doe  = (r5100 || rdip) ? 8'hFF : r5000 ? 8'h03 : 8'h00;

    // ------------------------------------------------------------------ CHR
    reg [8:0] cb;
    wire [2:0] s = ppu_a[12:10];
    wire [7:0] ls = cl[s];
    wire ram253 = m253 && !force_rom && (ls == 8'd4 || ls == 8'd5) && !ppu_a[13];
    always @(*) begin
        cb = 9'd0;
        if (m59) cb = {4'd0, l59[2:0], ppu_a[11:10]} ;
        if (m83) begin
            if (k2 && !nk2) case (ppu_a[12:11])
                2'd0: cb = {r83[0], ppu_a[10]};
                2'd1: cb = {r83[1], ppu_a[10]};
                2'd2: cb = {r83[6], ppu_a[10]};
                default: cb = {r83[7], ppu_a[10]};
            endcase
            else cb = {bank83[4], r83[s]};
        end
        if (m253) cb = {ch[s][0], ls};
    end
    assign chr_a    = m59 ? {4'd0, l59[2:0], ppu_a[12:10]} : cb;
    assign chr_en   = !ppu_a[13] && !ram253;
    assign chr_wr   = !ppu_a[13] && !ram253 && cfg[7] && !ppu_wr_n;
    assign chr_raw  = 1'b0;
    assign ciram_en = ppu_a[13];
    wire [1:0] mir = m59 ? {1'b0, l59[3]} : m83 ? mode83[1:0] : m253 ? mir253 : {1'b0, !cfg[0]};
    assign ciram_a10 = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : mir[0];

    // ------------------------------------------------------------------ 253: 2 KiB CHR-RAM in an M4K
    reg [7:0] cram [0:2047];
    reg [7:0] cq = 8'd0;
    initial for (i = 0; i < 2048; i = i + 1) cram[i] = 8'd0;
    wire [10:0] ca = {ls[0], ppu_a[9:0]};
    // one write per PPU /WR pulse, two clk after its falling edge (address and data are stable for the
    // whole pulse; writing on every clk could also hit the next address if /WR is seen late)
    reg [2:0] wrs = 3'b111;
    always @(posedge clk) begin
        wrs <= {wrs[1:0], ppu_wr_n};
        if (ram253 && wrs[2:1] == 2'b10 && !ppu_wr_n) cram[ca] <= ppu_din;
        cq <= cram[ca];
    end
    assign ppu_dout = cq;
    assign ppu_doe  = (ram253 && !ppu_rd_n) ? 8'hFF : 8'h00;
endmodule
