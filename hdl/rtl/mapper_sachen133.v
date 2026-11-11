`timescale 1ns/1ps
// mapper_sachen133.v — Mapper 133 (Sachen SA-72008 / 3009). Implementación propia (clean room).
// Registro en las direcciones con (A & $6100) = $4100 (también las de $C100-$DFFF):
// D2 = PRG de 32 KB, D1-D0 = CHR de 8 KB. Sin PRG-RAM.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_sachen133 (
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

    reg prg;
    reg [1:0] chr;
    initial begin prg = 0; chr = 0; end
    always @(negedge m2) begin
        if (rst) begin
            prg <= 0; chr <= 0;
        end else if (!cpu_rw && cpu_a[14] && !cpu_a[13] && cpu_a[8]) begin
            prg <= cpu_d[2];
            chr <= cpu_d[1:0];
        end
    end

    // sin PRG-RAM: $6000-$7FFF son registros o la placa no la tiene
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {3'd0, prg, cpu_a[14:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {4'd0, chr, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];

endmodule
