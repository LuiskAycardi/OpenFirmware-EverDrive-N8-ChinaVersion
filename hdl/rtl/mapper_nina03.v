`timescale 1ns/1ps
// mapper_nina03.v — Mappers 79 y 146 (AVE NINA-03/06, Sachen 3015). Implementación propia (clean room).
// Registro en $4100-$5FFF con A8 = 1 (dirección & $E100 == $4100): ....PCCC
//   P = PRG de 32 KB, C = CHR de 8 KB. El 146 (Sachen 3015) es la misma lógica.
//
// Lógica según la descripción pública (NESdev Wiki); casos límite contrastados leyendo la
// referencia MIT de Krikzz (N8 PRO) solo para entenderlos. Todas las salidas son activo-alto.

module mapper_nina03 (
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

    reg       prg;
    reg [2:0] chr;
    initial begin prg = 0; chr = 0; end
    wire reg_wr = romsel_n && (cpu_a[14:13] == 2'b10) && cpu_a[8] && !cpu_rw;   // $4100 (A15=0)
    always @(negedge m2) begin
        if (rst)         begin prg <= 0; chr <= 0; end
        else if (reg_wr) begin prg <= cpu_d[3]; chr <= cpu_d[2:0]; end
    end

    // La placa real no tiene PRG-RAM (y $6000-$7FFF son registros): no se habilita.
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {3'd0, prg, cpu_a[14:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {3'd0, chr, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq       = 1'b0;
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];   // mirroring de la cabecera

endmodule
