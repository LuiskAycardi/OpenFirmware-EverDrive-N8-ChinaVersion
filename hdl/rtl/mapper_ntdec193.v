`timescale 1ns/1ps
// mapper_ntdec193.v — Mapper 193 (NTDEC TC-112). Implementación propia (clean room).
// Registros en $6000-$7FFF (A1-A0): 0 = CHR de 4 KB en $0000 (D7-D1, en unidades de 2 KB),
// 1 = CHR de 2 KB en $1000, 2 = CHR de 2 KB en $1800, 3 = PRG de 8 KB en $8000.
// $A000/$C000/$E000 fijos a los tres últimos bancos de 8 KB. Sin PRG-RAM.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_ntdec193 (
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

    reg [6:0] c0, c1, c2;
    reg [5:0] p0;
    initial begin c0 = 0; c1 = 0; c2 = 0; p0 = 0; end
    wire reg_wr = romsel_n && !cpu_rw && (cpu_a[14:13] == 2'b11);
    always @(negedge m2) begin
        if (rst) begin
            c0 <= 0; c1 <= 0; c2 <= 0; p0 <= 0;
        end else if (reg_wr) begin
            case (cpu_a[1:0])
                2'd0: c0 <= cpu_d[7:1];
                2'd1: c1 <= cpu_d[7:1];
                2'd2: c2 <= cpu_d[7:1];
                2'd3: p0 <= cpu_d[5:0];
            endcase
        end
    end

    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = p0;
            2'd1: bank8 = 6'b111101;
            2'd2: bank8 = 6'b111110;
            2'd3: bank8 = 6'b111111;
        endcase
    end
    // sin PRG-RAM: $6000-$7FFF son registros o la placa no la tiene
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {bank8, cpu_a[12:10]};

    reg [6:0] bank2;
    always @(*) begin
        case (ppu_a[12:11])
            2'd0: bank2 = c0;
            2'd1: bank2 = c0 + 7'd1;
            2'd2: bank2 = c1;
            2'd3: bank2 = c2;
        endcase
    end
    assign chr_a = cfg[7] ? {6'd0, bank2[1:0], ppu_a[10]} : {1'b0, bank2, ppu_a[10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];

endmodule
