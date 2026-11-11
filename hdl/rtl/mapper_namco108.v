`timescale 1ns/1ps
// mapper_namco108.v — Mapper 206 (Namco 108 / Namcot 118, DxROM) y variantes 76, 88, 95 y 154.
// Implementación propia (clean room).
// Antecesor del MMC3, sin IRQ, sin modos ni registro de mirroring (va en la placa: cabecera).
// $8000-$FFFF par: selección de registro (D2-D0); impar: dato. El chip solo decodifica A15 y A0: los registros
// se repiten en todo $8000-$FFFF (corregido el 2026-11-08; antes solo $8000-$9FFF). Hecho visto con la prueba de
// ROM sintética contra Mesen2 y confirmado leyendo la referencia MIT de Krikzz (N8 PRO, mapper 88).
//   R0/R1: CHR de 2 KB en $0000/$0800 (bit bajo ignorado); R2-R5: CHR de 1 KB en $1000-$1FFF;
//   R6: PRG de 8 KB en $8000; R7: PRG de 8 KB en $A000; $C000-$FFFF fijo a los 16 KB finales.
//   CHR de 6 bits (64 KB), PRG de 4 bits (128 KB). 4 pantallas (Gauntlet): genérico en n8_top.
// Variantes (por map_id, fase 3c):
//   76  (Namcot-3446): CHR de 2 KB: R2-R5 en $0000/$0800/$1000/$1800 (128 KB); R0/R1 sin uso.
//   88  (Namcot-3443): CHR A16 = PPU A12: R0/R1 en los 64 KB bajos, R2-R5 en los 64 KB altos.
//   154 (Namcot-3453): como 88 + pantalla única = D6 de cualquier escritura en $8000-$FFFF.
//   95  (Namcot-3425): nametables $2000/$2400 = R0 bit 5, $2800/$2C00 = R1 bit 5.
//
// Lógica según la descripción pública (NESdev Wiki); casos límite contrastados leyendo la
// referencia MIT de Krikzz (N8 PRO) solo para entenderlos. Todas las salidas son activo-alto.

module mapper_namco108 (
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

    wire M76 = (map_id == 8'd76), M88 = (map_id == 8'd88), M95 = (map_id == 8'd95), M154 = (map_id == 8'd154);

    reg [2:0] sel;
    reg       one_sc;                                   // 154: pantalla única
    reg [5:0] r0, r1, r2, r3, r4, r5;
    reg [3:0] r6, r7;
    initial begin
        sel = 0; r0 = 0; r1 = 2; r2 = 4; r3 = 5; r4 = 6; r5 = 7; r6 = 0; r7 = 1; one_sc = 0;
    end
    wire reg_wr = !romsel_n && !cpu_rw;                                // $8000-$FFFF (A15 y A0)
    always @(negedge m2) begin
        if (rst) begin
            sel <= 0; r0 <= 0; r1 <= 2; r2 <= 4; r3 <= 5; r4 <= 6; r5 <= 7; r6 <= 0; r7 <= 1;
            one_sc <= 1'b0;
        end else begin
          if (M154 && !romsel_n && !cpu_rw) one_sc <= cpu_d[6];
          if (reg_wr) begin
            if (!cpu_a[0]) sel <= cpu_d[2:0];
            else case (sel)
                3'd0: r0 <= cpu_d[5:0];
                3'd1: r1 <= cpu_d[5:0];
                3'd2: r2 <= cpu_d[5:0];
                3'd3: r3 <= cpu_d[5:0];
                3'd4: r4 <= cpu_d[5:0];
                3'd5: r5 <= cpu_d[5:0];
                3'd6: r6 <= cpu_d[3:0];
                3'd7: r7 <= cpu_d[3:0];
            endcase
          end
        end
    end

    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = {2'd0, r6};
            2'd1: bank8 = {2'd0, r7};
            2'd2: bank8 = 6'b111110;
            2'd3: bank8 = 6'b111111;
        endcase
    end

    reg [6:0] bank1;
    always @(*) begin
        if (M76)
            case (ppu_a[12:11])                             // 2 KB: R2-R5
                2'd0: bank1 = {r2, ppu_a[10]};
                2'd1: bank1 = {r3, ppu_a[10]};
                2'd2: bank1 = {r4, ppu_a[10]};
                2'd3: bank1 = {r5, ppu_a[10]};
            endcase
        else
            case (ppu_a[12:10])
                3'd0: bank1 = {1'b0, r0[5:1], 1'b0};
                3'd1: bank1 = {1'b0, r0[5:1], 1'b1};
                3'd2: bank1 = {1'b0, r1[5:1], 1'b0};
                3'd3: bank1 = {1'b0, r1[5:1], 1'b1};
                3'd4: bank1 = {M88 || M154, r2};            // 88/154: CHR A16 = A12
                3'd5: bank1 = {M88 || M154, r3};
                3'd6: bank1 = {M88 || M154, r4};
                3'd7: bank1 = {M88 || M154, r5};
            endcase
    end

    // La placa real no tiene PRG-RAM (y $6000-$7FFF son registros): no se habilita.
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {bank8, cpu_a[12:10]};
    assign chr_a = cfg[7] ? {6'd0, bank1[2:0]} : {2'd0, bank1};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq       = 1'b0;
    assign ciram_a10 = M154 ? one_sc :
                       M95  ? (ppu_a[11] ? r1[5] : r0[5]) :
                       cfg[0] ? ppu_a[10] : ppu_a[11];   // mirroring de la cabecera

endmodule
