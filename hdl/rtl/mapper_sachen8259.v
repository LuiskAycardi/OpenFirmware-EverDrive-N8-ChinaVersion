`timescale 1ns/1ps
// mapper_sachen8259.v — Mappers 137, 138, 139 y 141 (Sachen 8259 D/B/C/A). Implementación propia (clean room).
// Registros en $4100-$7FFF (máscara $C101): $4100 selección (D2-D0), $4101 dato (D2-D0).
//   R0-R3: bancos CHR de 2 KB ($0000/$0800/$1000/$1800); R4: bits altos de CHR; R5: PRG de 32 KB;
//   R6: (solo 8259D) bit extra de CHR; R7: D0 = modo simple (todos los bancos = R0, mirroring
//   fijo), D2-D1 mirroring: 0 V, 1 H, 2 = $2000 en A y el resto en B, 3 pantalla A
//   (en el 8259D, 0 y 1 están al revés).
// Banco de 2 KB = ((R4 << 3) | Rn) << desplazamiento | OR fijo, según la variante:
//   141 (A): << 1, OR 0/1/0/1    138 (B): << 0    139 (C): << 2, OR 0/1/2/3
// 137 (8259D): bancos de 1 KB en $0000-$0FFF: R0, R1 | R4.0 << 4, R2 | R4.1 << 4,
//   R3 | R4.2 << 4 | R6.0 << 3; $1000-$1FFF fijo a los últimos 4 KB.
// Con CHR-RAM (Q Boy) no hay bancos de CHR. Sin PRG-RAM.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_sachen8259 (
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

    wire VA = (map_id == 8'd141), VC = (map_id == 8'd139), VD = (map_id == 8'd137);   // 138 = variante B (la de por defecto)

    reg [2:0] sel, r0, r1, r2, r3, r4, r5, r6, r7;
    initial begin sel = 0; r0 = 0; r1 = 0; r2 = 0; r3 = 0; r4 = 0; r5 = 0; r6 = 0; r7 = 0; end
    wire reg_wr = romsel_n && !cpu_rw && cpu_a[14] && cpu_a[8];
    always @(negedge m2) begin
        if (rst) begin
            sel <= 0; r0 <= 0; r1 <= 0; r2 <= 0; r3 <= 0; r4 <= 0; r5 <= 0; r6 <= 0; r7 <= 0;
        end else if (reg_wr) begin
            if (!cpu_a[0]) sel <= cpu_d[2:0];
            else case (sel)
                3'd0: r0 <= cpu_d[2:0]; 3'd1: r1 <= cpu_d[2:0]; 3'd2: r2 <= cpu_d[2:0]; 3'd3: r3 <= cpu_d[2:0];
                3'd4: r4 <= cpu_d[2:0]; 3'd5: r5 <= cpu_d[2:0]; 3'd6: r6 <= cpu_d[2:0]; 3'd7: r7 <= cpu_d[2:0];
            endcase
        end
    end

    // sin PRG-RAM: $6000-$7FFF son registros o la placa no la tiene
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {1'b0, r5, cpu_a[14:10]};

    wire simple = r7[0];
    // registro de 2 KB (o de 1 KB en el 8259D) para cada cuarto de $0000-$1FFF
    wire [1:0] q = VD ? ppu_a[11:10] : ppu_a[12:11];
    reg  [2:0] rn;
    always @(*) begin
        case (q)
            2'd0: rn = r0;
            2'd1: rn = simple ? r0 : r1;
            2'd2: rn = simple ? r0 : r2;
            2'd3: rn = simple ? r0 : r3;
        endcase
    end
    wire [5:0] hi  = {r4, rn};
    wire [7:0] b2k = VA ? {1'b0, hi, q[0]} :
                     VC ? {hi, q} : {2'd0, hi};           // banco de 2 KB
    reg  [4:0] bd;                                         // 8259D: banco de 1 KB
    always @(*) begin
        case (q)
            2'd0: bd = {2'd0, r0};
            2'd1: bd = {r4[0], 1'b0, rn};
            2'd2: bd = {r4[1], 1'b0, rn};
            2'd3: bd = {r4[2], r6[0], rn};
        endcase
    end
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} :
                   VD ? (ppu_a[12] ? {7'b1111111, ppu_a[11:10]} : {4'd0, bd}) :
                        {b2k, ppu_a[10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    // mirroring
    wire [1:0] m = simple ? 2'd0 : r7[2:1];
    assign ciram_a10 = (m == 2'd0) ? (VD ? ppu_a[11] : ppu_a[10]) :
                       (m == 2'd1) ? (VD ? ppu_a[10] : ppu_a[11]) :
                       (m == 2'd2) ? (ppu_a[11:10] != 2'd0) : 1'b0;

endmodule
