`timescale 1ns/1ps
// mapper_uxrom.v — Mapper 2 (UNROM / UOROM y variantes hasta 512 KB). Implementación propia.
//
// Escritura en $8000-$FFFF: banco de 16 KB para $8000-$BFFF (5 bits -> hasta 512 KB).
// $C000-$FFFF: último banco fijo (todo unos; la máscara PRG_SIZE del OS lo ajusta al tamaño real).
// CHR: 8 KB (normalmente CHR-RAM). Mirroring fijo según la cabecera (cfg[0]).
// Se ignoran los conflictos de bus: se usa el valor escrito tal cual.

module mapper_uxrom (
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

    reg [4:0] bank;
    initial bank = 5'd0;

    always @(negedge m2) begin
        if (rst)                        bank <= 5'd0;
        else if (!romsel_n && !cpu_rw)  bank <= cpu_d[4:0];
    end

    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);
    // 180 (UNROM con 74HC08, Crazy Climber): $8000 fijo al primer banco, $C000 conmutable (D2-D0).
    wire M180 = (map_id == 8'd180);
    wire [4:0] bank16 = M180 ? (cpu_a[14] ? {2'd0, bank[2:0]} : 5'd0)
                             : (cpu_a[14] ? 5'b11111 : bank);

    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]} : {bank16, cpu_a[13:10]};
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;

    assign chr_a      = {6'd0, ppu_a[12:10]};
    assign chr_en     = !ppu_a[13];
    assign chr_wr     = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en   = ppu_a[13];
    assign ciram_a10  = cfg[0] ? ppu_a[10] : ppu_a[11];
    assign irq        = 1'b0;

endmodule
