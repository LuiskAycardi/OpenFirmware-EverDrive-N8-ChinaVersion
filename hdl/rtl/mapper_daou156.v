`timescale 1ns/1ps
// mapper_daou156.v — Mapper 156 (Daou Infosys DIS23C01). Implementación propia (clean room).
// Registros en $C000-$C014: $C000-$C003 / $C008-$C00B byte bajo de los bancos CHR 0-3 / 4-7,
// $C004-$C007 / $C00C-$C00F byte alto; $C010 PRG de 16 KB en $8000 ($C000 fijo al último);
// $C014 mirroring D0 (1 = H). Al arrancar: pantalla única A.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_daou156 (
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

    reg [7:0] lo0, lo1, lo2, lo3, lo4, lo5, lo6, lo7;
    reg       hi0, hi1, hi2, hi3, hi4, hi5, hi6, hi7;
    reg [4:0] prg;
    reg [1:0] mir;                                  // 0 V, 1 H, 2 pantalla A
    initial begin
        lo0 = 0; lo1 = 0; lo2 = 0; lo3 = 0; lo4 = 0; lo5 = 0; lo6 = 0; lo7 = 0;
        hi0 = 0; hi1 = 0; hi2 = 0; hi3 = 0; hi4 = 0; hi5 = 0; hi6 = 0; hi7 = 0; prg = 0; mir = 2;
    end
    wire reg_wr = !romsel_n && !cpu_rw && (cpu_a[14:5] == 10'h200);   // $C000-$C01F
    always @(negedge m2) begin
        if (rst) begin
            lo0 <= 0; lo1 <= 0; lo2 <= 0; lo3 <= 0; lo4 <= 0; lo5 <= 0; lo6 <= 0; lo7 <= 0;
            hi0 <= 0; hi1 <= 0; hi2 <= 0; hi3 <= 0; hi4 <= 0; hi5 <= 0; hi6 <= 0; hi7 <= 0;
            prg <= 0; mir <= 2'd2;
        end else if (reg_wr) begin
            case (cpu_a[4:0])
                5'h00: lo0 <= cpu_d; 5'h01: lo1 <= cpu_d; 5'h02: lo2 <= cpu_d; 5'h03: lo3 <= cpu_d;
                5'h04: hi0 <= cpu_d[0]; 5'h05: hi1 <= cpu_d[0]; 5'h06: hi2 <= cpu_d[0]; 5'h07: hi3 <= cpu_d[0];
                5'h08: lo4 <= cpu_d; 5'h09: lo5 <= cpu_d; 5'h0A: lo6 <= cpu_d; 5'h0B: lo7 <= cpu_d;
                5'h0C: hi4 <= cpu_d[0]; 5'h0D: hi5 <= cpu_d[0]; 5'h0E: hi6 <= cpu_d[0]; 5'h0F: hi7 <= cpu_d[0];
                5'h10: prg <= cpu_d[4:0];
                5'h14: mir <= {1'b0, cpu_d[0]};
                default: ;
            endcase
        end
    end

    wire [4:0] bank16 = cpu_a[14] ? 5'b11111 : prg;
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank16, cpu_a[13:10]};

    reg [8:0] bank1;
    always @(*) begin
        case (ppu_a[12:10])
            3'd0: bank1 = {hi0, lo0}; 3'd1: bank1 = {hi1, lo1}; 3'd2: bank1 = {hi2, lo2}; 3'd3: bank1 = {hi3, lo3};
            3'd4: bank1 = {hi4, lo4}; 3'd5: bank1 = {hi5, lo5}; 3'd6: bank1 = {hi6, lo6}; 3'd7: bank1 = {hi7, lo7};
        endcase
    end
    assign chr_a = cfg[7] ? {6'd0, bank1[2:0]} : bank1;
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : 1'b0;

endmodule
