`timescale 1ns/1ps
// mapper_bnrom.v — Mapper 34 (BNROM / AVE NINA-001). Implementación propia (clean room).
// Dos placas con el mismo número; se distinguen como en el hardware: BNROM lleva CHR-RAM,
// NINA-001 lleva CHR-ROM (cfg[7]).
//   BNROM:    escritura en $8000-$FFFF -> PRG de 32 KB (D3-D0).
//   NINA-001: $7FFD -> PRG de 32 KB, $7FFE -> CHR 4 KB en $0000, $7FFF -> CHR 4 KB en $1000;
//             8 KB de PRG-RAM en $6000-$7FFF (los registros también se guardan en la RAM).
//
// Lógica según la descripción pública (NESdev Wiki); casos límite contrastados leyendo la
// referencia MIT de Krikzz (N8 PRO) solo para entenderlos. Todas las salidas son activo-alto.

module mapper_bnrom (
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

    reg [3:0] prg;
    reg [4:0] chr0, chr1;
    initial begin prg = 0; chr0 = 0; chr1 = 0; end
    wire bnrom   = cfg[7];
    wire rom_wr  = !romsel_n && !cpu_rw;
    wire nina_wr = romsel_n && !cpu_rw && (cpu_a[14:0] >= 15'h7FFD);
    always @(negedge m2) begin
        if (rst) begin prg <= 0; chr0 <= 0; chr1 <= 0; end
        else if (bnrom) begin
            if (rom_wr) prg <= cpu_d[3:0];
        end else if (nina_wr) begin
            case (cpu_a[1:0])
                2'd1: prg  <= cpu_d[3:0];
                2'd2: chr0 <= cpu_d[4:0];
                2'd3: chr1 <= cpu_d[4:0];
                default: ;
            endcase
        end
    end

    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {prg, cpu_a[14:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]}
                          : {2'd0, ppu_a[12] ? chr1 : chr0, ppu_a[11:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq       = 1'b0;
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];   // mirroring de la cabecera

endmodule
