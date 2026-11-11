`timescale 1ns/1ps
// mapper_multi_b.v — Mappers 41, 46, 228 y 241 (multicartuchos y placas simples). Implementación propia (clean room).
// Cuatro placas pequeñas en un módulo (variante por map_id):
//   41  (Caltron 6 in 1): escribir en $6000-$67FF guarda la dirección: A2-A0 = PRG de 32 KB,
//       A4-A3 = bits altos de CHR, A5 = mirroring (1 = H). En $8000-$FFFF, D1-D0 = bits bajos de
//       CHR, solo si el banco PRG es 4-7.
//   46  (Rumble Station): $6000-$7FFF = R0, $8000-$FFFF = R1. PRG 32 KB = R0[3:0] << 1 | R1[0];
//       CHR 8 KB = R0[7:4] << 3 | R1[6:4] (recortados a los 512 KB del N8).
//   228 (Action 52 / Cheetahmen II): la dirección de la escritura en $8000-$FFFF lleva el banco:
//       A12-A11 chip (3 = 2), A10-A6 PRG de 16 KB, A5 = 16 KB repetido / 32 KB, A13 mirroring
//       (1 = H); CHR 8 KB = A3-A0 << 2 | D1-D0.
//   241 (BxROM con PRG-RAM): $8000-$FFFF = PRG de 32 KB.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_multi_b (
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

    wire M41 = (map_id == 8'd41), M46 = (map_id == 8'd46), M228 = (map_id == 8'd228);

    reg [7:0] ra, rb;            // 41: ra = dirección (A5-A0), rb = CHR bajo; 46: R0/R1; 228: dirección/dato
    reg [5:0] a228;
    reg [1:0] d228;
    reg       a13;
    initial begin ra = 0; rb = 0; a228 = 0; d228 = 0; a13 = 0; end
    wire rom_wr = !romsel_n && !cpu_rw;
    wire w6000  = romsel_n && !cpu_rw && (cpu_a[14:13] == 2'b11);
    always @(negedge m2) begin
        if (rst) begin
            ra <= 0; rb <= 0; a228 <= 0; d228 <= 0; a13 <= 0;
        end else if (M41) begin
            if (w6000 && !cpu_a[12] && !cpu_a[11]) ra <= {2'd0, cpu_a[5:0]};
            else if (rom_wr && ra[2]) rb <= {6'd0, cpu_d[1:0]};
        end else if (M46) begin
            if (w6000)  ra <= cpu_d;
            if (rom_wr) rb <= cpu_d;
        end else if (M228) begin
            if (rom_wr) begin ra <= cpu_a[12:5]; a228 <= {2'd0, cpu_a[3:0]}; d228 <= cpu_d[1:0]; a13 <= cpu_a[13]; end
        end else begin
            if (rom_wr) rb <= cpu_d;                          // 241
        end
    end

    // ------------------------------------------------ PRG (banco de 16 KB, 5 bits = 512 KB)
    wire [1:0] chip   = (ra[7:6] == 2'd3) ? 2'd2 : ra[7:6];            // 228
    wire [6:0] p228   = {chip, ra[5:1]};
    wire [4:0] b16_228 = ra[0] ? p228[4:0] : {p228[4:1], cpu_a[14]};
    wire [4:0] bank16 = M41  ? {1'b0, ra[2:0], cpu_a[14]} :
                        M46  ? {ra[2:0], rb[0], cpu_a[14]} :
                        M228 ? b16_228 :
                               {rb[3:0], cpu_a[14]};
    wire ram_ok = !(M41 || M46);
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && ram_ok && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank16, cpu_a[13:10]};

    // ------------------------------------------------ CHR (8 KB)
    wire [5:0] chr8 = M41  ? {2'd0, ra[4:3], rb[1:0]} :
                      M46  ? {ra[6:4], rb[6:4]} :
                      M228 ? {a228[3:0], d228} : 6'd0;
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {chr8, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    wire mir_h = M41 ? ra[5] : M228 ? a13 : !cfg[0];
    assign ciram_a10 = mir_h ? ppu_a[11] : ppu_a[10];

endmodule
