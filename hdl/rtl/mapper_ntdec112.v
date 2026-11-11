`timescale 1ns/1ps
// mapper_ntdec112.v — Mapper 112 (NTDEC / Asder). Implementación propia (clean room).
// Registros (máscara $E001): $8000 selección (D2-D0), $A000 dato, $C000 bits altos de CHR,
// $E000 mirroring D0 (1 = H; al arrancar, vertical como en Mesen2).
//   R0/R1: PRG de 8 KB en $8000/$A000; $C000/$E000 fijos a los dos últimos.
//   R2/R3: CHR de 2 KB en $0000/$0800 (banco y banco + 1, unidades de 1 KB)
//   R4-R7: CHR de 1 KB en $1000-$1C00; el bit 8 de cada uno sale de $C000 D4-D7.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_ntdec112 (
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

    reg [2:0] sel;
    reg [7:0] r0, r1, r2, r3, r4, r5, r6, r7, outer;
    reg       mir_h;
    initial begin sel = 0; r0 = 0; r1 = 0; r2 = 0; r3 = 0; r4 = 0; r5 = 0; r6 = 0; r7 = 0; outer = 0; mir_h = 0; end
    wire rom_wr = !romsel_n && !cpu_rw && !cpu_a[0];
    always @(negedge m2) begin
        if (rst) begin
            sel <= 0; r0 <= 0; r1 <= 0; r2 <= 0; r3 <= 0; r4 <= 0; r5 <= 0; r6 <= 0; r7 <= 0;
            outer <= 0; mir_h <= 0;
        end else if (rom_wr) begin
            case (cpu_a[14:13])
                2'd0: sel <= cpu_d[2:0];
                2'd1: case (sel)
                          3'd0: r0 <= cpu_d; 3'd1: r1 <= cpu_d; 3'd2: r2 <= cpu_d; 3'd3: r3 <= cpu_d;
                          3'd4: r4 <= cpu_d; 3'd5: r5 <= cpu_d; 3'd6: r6 <= cpu_d; 3'd7: r7 <= cpu_d;
                      endcase
                2'd2: outer <= cpu_d;
                2'd3: mir_h <= cpu_d[0];
            endcase
        end
    end

    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = r0[5:0];
            2'd1: bank8 = r1[5:0];
            2'd2: bank8 = 6'b111110;
            2'd3: bank8 = 6'b111111;
        endcase
    end
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};

    reg [8:0] bank1;
    always @(*) begin
        case (ppu_a[12:10])
            3'd0: bank1 = {1'b0, r2};
            3'd1: bank1 = {1'b0, r2 + 8'd1};
            3'd2: bank1 = {1'b0, r3};
            3'd3: bank1 = {1'b0, r3 + 8'd1};
            3'd4: bank1 = {outer[4], r4};
            3'd5: bank1 = {outer[5], r5};
            3'd6: bank1 = {outer[6], r6};
            3'd7: bank1 = {outer[7], r7};
        endcase
    end
    assign chr_a = cfg[7] ? {6'd0, bank1[2:0]} : bank1;
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = mir_h ? ppu_a[11] : ppu_a[10];

endmodule
