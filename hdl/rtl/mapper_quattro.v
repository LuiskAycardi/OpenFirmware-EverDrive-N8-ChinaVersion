`timescale 1ns/1ps
// mapper_quattro.v — Mapper 232 (Camerica BF9096 / Quattro). Implementación propia (clean room).
// Escritura en $8000-$BFFF: ...BB... -> bloque de 64 KB; en $C000-$FFFF: ......PP -> página.
//   $8000 = bloque*4 + página, $C000 = bloque*4 + 3 (bancos de 16 KB).
// (Los cartuchos Aladdin, submapper 1, invierten los bits del bloque: no se distinguen con iNES.)
//
// Lógica según la descripción pública (NESdev Wiki); casos límite contrastados leyendo la
// referencia MIT de Krikzz (N8 PRO) solo para entenderlos. Todas las salidas son activo-alto.

module mapper_quattro (
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

    reg [1:0] blk, page;
    initial begin blk = 0; page = 0; end
    wire rom_wr = !romsel_n && !cpu_rw;
    always @(negedge m2) begin
        if (rst) begin blk <= 0; page <= 0; end
        else if (rom_wr) begin
            if (!cpu_a[14]) blk  <= cpu_d[4:3];
            else            page <= cpu_d[1:0];
        end
    end

    // La placa real no tiene PRG-RAM (y $6000-$7FFF son registros): no se habilita.
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {1'b0, blk, cpu_a[14] ? 2'b11 : page, cpu_a[13:10]};
    assign chr_a = {6'd0, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq       = 1'b0;
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];   // mirroring de la cabecera

endmodule
