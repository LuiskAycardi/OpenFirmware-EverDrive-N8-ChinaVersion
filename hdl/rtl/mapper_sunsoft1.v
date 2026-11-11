`timescale 1ns/1ps
// mapper_sunsoft1.v — Mapper 184 (Sunsoft-1). Implementación propia (clean room).
// Escritura en $6000-$7FFF: .HHH.LLL -> L = CHR de 4 KB en $0000, H = CHR de 4 KB en $1000.
// PRG fijo de 32 KB.
//
// Lógica según la descripción pública (NESdev Wiki); casos límite contrastados leyendo la
// referencia MIT de Krikzz (N8 PRO) solo para entenderlos. Todas las salidas son activo-alto.

module mapper_sunsoft1 (
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

    reg [2:0] lo, hi;
    initial begin lo = 0; hi = 0; end
    wire w6000  = romsel_n && (cpu_a[14:13] == 2'b11) && !cpu_rw;
    always @(negedge m2) begin
        if (rst)        begin lo <= 0; hi <= 0; end
        else if (w6000) begin lo <= cpu_d[2:0]; hi <= cpu_d[6:4]; end
    end

    // La placa real no tiene PRG-RAM (y $6000-$7FFF son registros): no se habilita.
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {4'd0, cpu_a[14:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]}
                          : {4'd0, ppu_a[12] ? hi : lo, ppu_a[11:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq       = 1'b0;
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];   // mirroring de la cabecera

endmodule
