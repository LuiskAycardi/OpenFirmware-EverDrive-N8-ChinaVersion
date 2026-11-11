`timescale 1ns/1ps
// mapper_jaleco72.v — Mappers 72 y 92 (Jaleco JF-17 / JF-19). Implementación propia (clean room).
// Un registro en $8000-$FFFF. El banco se carga en el flanco de subida de un bit de control:
//   D7 0 -> 1: PRG de 16 KB = D3-D0 (72: en $8000, $C000 fijo al último;
//              92: en $C000, $8000 fijo al primero)
//   D6 0 -> 1: CHR de 8 KB = D3-D0
// El chip de voz (uPD7756, bits D5-D4) no está implementado.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_jaleco72 (
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

    wire M92 = (map_id == 8'd92);
    reg [3:0] prg, chr;
    reg       f7, f6, prg_set;          // 92: hasta la primera carga, $C000 = último (como Mesen2)
    initial begin prg = 0; chr = 0; f7 = 0; f6 = 0; prg_set = 0; end
    always @(negedge m2) begin
        if (rst) begin
            prg <= 0; chr <= 0; f7 <= 0; f6 <= 0; prg_set <= 0;
        end else if (!romsel_n && !cpu_rw) begin
            if (!f7 && cpu_d[7]) begin prg <= M92 ? cpu_d[3:0] : {1'b0, cpu_d[2:0]}; prg_set <= 1'b1; end
            if (!f6 && cpu_d[6]) chr <= cpu_d[3:0];
            f7 <= cpu_d[7];
            f6 <= cpu_d[6];
        end
    end

    wire [4:0] bank16 = M92 ? (cpu_a[14] ? (prg_set ? {1'b0, prg} : 5'b11111) : 5'd0)
                            : (cpu_a[14] ? 5'b11111 : {1'b0, prg});
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank16, cpu_a[13:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {2'd0, chr, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];

endmodule
