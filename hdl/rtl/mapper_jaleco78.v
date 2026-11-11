`timescale 1ns/1ps
// mapper_jaleco78.v — Mapper 78 (Irem IF-12 / Jaleco JF-16). Implementación propia (clean room).
// Un registro en $8000-$FFFF: D2-D0 PRG de 16 KB en $8000 ($C000 fijo al último), D7-D4 CHR
// de 8 KB, D3 mirroring. Dos placas:
//   Holy Diver (Irem IF-12): D3 = 1 vertical, 0 horizontal.
//   Uchuusen Cosmo Carrier (Jaleco JF-16): D3 = pantalla única (1 = B).
// El OS no envía el submapper NES 2.0; las cabeceras iNES de Holy Diver llevan el bit de 4
// pantallas como marca (convención de NESdev), así que cfg[3] elige la placa. Por eso n8_top
// no activa la RAM de 4 pantallas con el 78.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_jaleco78 (
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
    input  wire        clk,        // reloj del sistema
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

    wire HOLY = cfg[3];
    reg [7:0] r;
    initial r = 0;
    always @(negedge m2) begin
        if (rst)                        r <= 8'd0;
        else if (!romsel_n && !cpu_rw)  r <= cpu_d;
    end

    wire [4:0] bank16 = cpu_a[14] ? 5'b11111 : {2'd0, r[2:0]};
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank16, cpu_a[13:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {2'd0, r[7:4], ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = HOLY ? (r[3] ? ppu_a[10] : ppu_a[11]) : r[3];

endmodule
