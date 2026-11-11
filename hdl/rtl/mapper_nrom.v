`timescale 1ns/1ps
// mapper_nrom.v — Mapper 0 (NROM-128 / NROM-256), implementación propia.
//
// CPU: $8000-$FFFF -> PRG (16 KB se espeja con la máscara PRG_SIZE que pone el OS)
//      $6000-$7FFF -> 8 KB de PRG-RAM (banco 0)
// PPU: $0000-$1FFF -> CHR (ROM, o RAM si cfg[7] = 1)
//      $2000-$3FFF -> CIRAM; cfg[0] = 1 vertical (A10), 0 horizontal (A11)
//
// Todas las salidas son activo-alto; el top-level aplica polaridades y máscaras.

module mapper_nrom (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,      // sin uso (interfaz común de mappers)
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,   // PPU /RD (solo lo usa el MMC2/MMC4)
    input  wire        ppu_wr_n,
    input  wire [7:0]  cfg,
    input  wire        rst,        // sin uso
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

    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);

    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]}    // PRG-RAM, banco 0
                                 : {4'd0, cpu_a[14:10]};   // 32 KB de PRG
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
