`timescale 1ns/1ps
// mapper_colordreams.v — Mappers 11 y 144 (Color Dreams). Implementación propia (clean room).
// Escritura en $8000-$FFFF: CCCC ..PP -> P = PRG de 32 KB, C = CHR de 8 KB.
// (Los bits 3-2 del chip de bloqueo CIC no afectan al N8.)
//
// Lógica según la descripción pública (NESdev Wiki); casos límite contrastados leyendo la
// referencia MIT de Krikzz (N8 PRO) solo para entenderlos. Todas las salidas son activo-alto.

module mapper_colordreams (
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

    reg [1:0] prg;
    reg [3:0] chr;
    initial begin prg = 0; chr = 0; end
    // 144 (AGCI 50282, Death Race): como Color Dreams, pero en la placa D0 lo pone siempre la ROM (conflicto de
    // bus). El N8 no ve el byte de la ROM durante una escritura: se ignoran las escrituras en $8000 (lo que
    // hace FCEUX con este juego; NESdev). Añadido el 2026-11-08.
    wire rom_wr = !romsel_n && !cpu_rw && !(map_id == 8'd144 && cpu_a == 15'h0000);
    always @(negedge m2) begin
        if (rst)         begin prg <= 0; chr <= 0; end
        else if (rom_wr) begin prg <= cpu_d[1:0]; chr <= cpu_d[7:4]; end
    end

    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {2'd0, prg, cpu_a[14:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {2'd0, chr, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq       = 1'b0;
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];   // mirroring de la cabecera

endmodule
