`timescale 1ns/1ps
// mapper_sunsoft4.v — Mapper 68 (Sunsoft-4). Implementación propia (clean room).
// $8000/$9000/$A000/$B000: CHR de 2 KB en $0000/$0800/$1000/$1800
// $C000/$D000: banco de 1 KB de CHR-ROM para las nametables (se le suma $80: últimos 128 KB)
// $E000: D1-D0 mirroring (0 V, 1 H, 2 A, 3 B), D4 = nametables desde CHR-ROM
// $F000: D2-D0 PRG de 16 KB en $8000, D4 = PRG-RAM activa; $C000 fijo al último.
// Con D4 de $E000 las nametables salen de la CHR-ROM (la CIRAM no se usa): el registro 0 o 1 lo
// elige el mirroring igual que elegiría la página de la CIRAM.
// No implementado: la ROM externa con temporizador de licencia de Nantettatte!! Baseball
// (cartucho de 144 KB).
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_sunsoft4 (
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

    reg [7:0] c0, c1, c2, c3, nt0, nt1;
    reg [2:0] prg;
    reg [1:0] mir;
    reg       nt_chr, ram_on;
    initial begin c0 = 0; c1 = 0; c2 = 0; c3 = 0; nt0 = 0; nt1 = 0; prg = 0; mir = 0; nt_chr = 0; ram_on = 0; end
    wire rom_wr = !romsel_n && !cpu_rw;
    always @(negedge m2) begin
        if (rst) begin
            c0 <= 0; c1 <= 0; c2 <= 0; c3 <= 0; nt0 <= 0; nt1 <= 0; prg <= 0;
            mir <= cfg[0] ? 2'd0 : 2'd1; nt_chr <= 0; ram_on <= 0;
        end else if (rom_wr) begin
            case (cpu_a[14:12])
                3'd0: c0 <= cpu_d;
                3'd1: c1 <= cpu_d;
                3'd2: c2 <= cpu_d;
                3'd3: c3 <= cpu_d;
                3'd4: nt0 <= cpu_d | 8'h80;
                3'd5: nt1 <= cpu_d | 8'h80;
                3'd6: begin mir <= cpu_d[1:0]; nt_chr <= cpu_d[4]; end
                3'd7: begin prg <= cpu_d[2:0]; ram_on <= cpu_d[4]; end
            endcase
        end
    end

    wire [4:0] bank16 = cpu_a[14] ? 5'b11111 : {2'd0, prg};
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && ram_on && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank16, cpu_a[13:10]};

    // página de nametable según el mirroring
    wire nt_sel = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : mir[0];
    reg [7:0] bank2;
    always @(*) begin
        case (ppu_a[12:11])
            2'd0: bank2 = c0;
            2'd1: bank2 = c1;
            2'd2: bank2 = c2;
            2'd3: bank2 = c3;
        endcase
    end
    wire nt_rom = ppu_a[13] && nt_chr;                    // nametable desde CHR-ROM
    assign chr_a = nt_rom ? {1'b0, nt_sel ? nt1 : nt0} :
                   cfg[7] ? {6'd0, bank2[1:0], ppu_a[10]} : {bank2, ppu_a[10]};
    assign chr_en    = !ppu_a[13] || nt_rom;
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13] && !nt_chr;
    assign ciram_a10 = nt_sel;
    assign irq = 1'b0;

endmodule
