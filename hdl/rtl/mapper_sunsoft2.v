`timescale 1ns/1ps
// mapper_sunsoft2.v — Mappers 89 y 93 (Sunsoft-2). Implementación propia (clean room).
// Un registro en $8000-$FFFF; $C000 fijo a los 16 KB finales.
//   89 (placa Sunsoft-3): D6-D4 PRG de 16 KB, D7 y D2-D0 CHR de 8 KB, D3 pantalla única (1 = B)
//   93 (placa Sunsoft-3R, CHR-RAM): D6-D4 PRG, D0 = CHR activa. Desactivada, la PPU lee el bus
//      abierto ($FF por las resistencias de pull-up de ppu_d) y las escrituras no llegan.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_sunsoft2 (
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

    wire M93 = (map_id == 8'd93);
    reg [7:0] r;
    reg       written;                      // hasta la primera escritura: cabecera / CHR activa
    initial begin r = 0; written = 0; end
    always @(negedge m2) begin
        if (rst) begin
            r <= 0; written <= 0;
        end else if (!romsel_n && !cpu_rw) begin
            r <= cpu_d; written <= 1'b1;
        end
    end

    wire [4:0] bank16 = cpu_a[14] ? 5'b11111 : {2'd0, r[6:4]};
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank16, cpu_a[13:10]};

    wire [3:0] chr8 = {r[7], r[2:0]};
    wire chr_on = !M93 || r[0] || !written;
    assign chr_a = (cfg[7] || M93) ? {6'd0, ppu_a[12:10]} : {2'd0, chr8, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13] && chr_on;
    assign chr_wr    = cfg[7] && chr_on && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = (M93 || !written) ? (cfg[0] ? ppu_a[10] : ppu_a[11]) : r[3];

endmodule
