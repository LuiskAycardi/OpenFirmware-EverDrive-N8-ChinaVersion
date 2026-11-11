`timescale 1ns/1ps
// mapper_cnrom.v — Mapper 3 (CNROM). Implementación propia.
//
// PRG: 16/32 KB fijos, como NROM. Escritura en $8000-$FFFF: banco CHR de 8 KB
// (6 bits -> hasta 512 KB; la máscara CHR_SIZE del OS recorta al tamaño real).
// Mirroring fijo (cfg[0]). Se ignoran los conflictos de bus y los bits de "protección"
// de algunos cartuchos.

module mapper_cnrom (
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

    // 185 (CNROM con protección): CHR de 8 KB que el juego activa o desactiva con el valor escrito.
    // La placa compara D0/D1 (y D4/D5) con diodos distintos en cada juego; sin el submapper NES 2.0
    // se usa la regla de NESdev para submapper 0: activa si (D & $0F) != 0 y D != $13.
    // Desactivada, la PPU lee el bus abierto: en el N8, las resistencias de pull-up de ppu_d (QSF)
    // dan $FF (Mighty Bomb Jack necesita D0 = 1).
    wire M185 = (map_id == 8'd185);

    reg [5:0] chr_bank;
    reg       chr_on;
    initial begin chr_bank = 6'd0; chr_on = 1'b1; end

    always @(negedge m2) begin
        if (rst) begin
            chr_bank <= 6'd0;
            chr_on   <= 1'b1;
        end else if (!romsel_n && !cpu_rw) begin
            chr_bank <= M185 ? 6'd0 : cpu_d[5:0];
            chr_on   <= (cpu_d[3:0] != 4'd0) && (cpu_d != 8'h13);
        end
    end

    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);

    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]} : {4'd0, cpu_a[14:10]};
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;

    assign chr_a      = {chr_bank, ppu_a[12:10]};
    assign chr_en     = !ppu_a[13] && (chr_on || !M185);
    assign chr_wr     = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en   = ppu_a[13];
    assign ciram_a10  = cfg[0] ? ppu_a[10] : ppu_a[11];
    assign irq        = 1'b0;

endmodule
