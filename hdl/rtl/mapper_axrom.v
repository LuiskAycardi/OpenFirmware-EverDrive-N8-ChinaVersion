`timescale 1ns/1ps
// mapper_axrom.v — Mapper 7 (AxROM: ANROM, AMROM, AOROM). Implementación propia.
//
// Escritura en $8000-$FFFF:
//   bits 3..0 -> banco de 32 KB en $8000-$FFFF (hasta 512 KB)
//   bit 4     -> nametable única (CIRAM A10)
// CHR: 8 KB de CHR-RAM.

module mapper_axrom (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,   // PPU /RD (solo lo usa el MMC2/MMC4)
    input  wire        ppu_wr_n,
    input  wire [7:0]  cfg,
    input  wire        rst,
    input  wire        clk,        // reloj del sistema (sin uso en este mapper)
    input  wire [7:0]  map_id,     // número de mapper (variantes de una misma familia)

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

    reg [3:0] bank;
    reg       nt;
    initial begin bank = 4'd0; nt = 1'b0; end

    always @(negedge m2) begin
        if (rst) begin
            bank <= 4'd0;
            nt   <= 1'b0;
        end else if (!romsel_n && !cpu_rw) begin
            bank <= cpu_d[3:0];
            nt   <= cpu_d[4];
        end
    end

    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);

    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]} : {bank, cpu_a[14:10]};
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;

    assign chr_a      = {6'd0, ppu_a[12:10]};
    assign chr_en     = !ppu_a[13];
    assign chr_wr     = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en   = ppu_a[13];
    assign ciram_a10  = nt;
    assign irq        = 1'b0;

endmodule
