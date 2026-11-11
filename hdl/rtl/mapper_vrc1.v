`timescale 1ns/1ps
// mapper_vrc1.v — Mapper 75 (Konami VRC1). Implementación propia (clean room).
// $8000/$A000/$C000 PRG de 8 KB (D3-D0; se aceptan 8 bits, como Mesen2); $E000 fijo al último.
// $9000: D0 mirroring (1 = H; se ignora con 4 pantallas), D1 = bit 4 de CHR0, D2 = bit 4 de CHR1
// $E000/$F000: D3-D0 de CHR0/CHR1 (4 KB en $0000/$1000). El VRC1 no tiene PRG-RAM.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_vrc1 (
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

    reg [5:0] p0, p1, p2;
    reg [4:0] ch0, ch1;
    reg       mir_h;
    initial begin p0 = 0; p1 = 0; p2 = 0; ch0 = 0; ch1 = 0; mir_h = 0; end
    wire rom_wr = !romsel_n && !cpu_rw;
    always @(negedge m2) begin
        if (rst) begin
            p0 <= 0; p1 <= 0; p2 <= 0; ch0 <= 0; ch1 <= 0; mir_h <= !cfg[0];
        end else if (rom_wr) begin
            case (cpu_a[14:12])
                3'd0: p0 <= cpu_d[5:0];
                3'd1: begin mir_h <= cpu_d[0]; ch0[4] <= cpu_d[1]; ch1[4] <= cpu_d[2]; end
                3'd2: p1 <= cpu_d[5:0];
                3'd4: p2 <= cpu_d[5:0];
                3'd6: ch0[3:0] <= cpu_d[3:0];
                3'd7: ch1[3:0] <= cpu_d[3:0];
                default: ;
            endcase
        end
    end

    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = p0;
            2'd1: bank8 = p1;
            2'd2: bank8 = p2;
            2'd3: bank8 = 6'b111111;
        endcase
    end
    // sin PRG-RAM: $6000-$7FFF son registros o la placa no la tiene
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {bank8, cpu_a[12:10]};

    wire [4:0] bank4 = ppu_a[12] ? ch1 : ch0;
    assign chr_a = cfg[7] ? {6'd0, bank4[0], ppu_a[11:10]} : {2'd0, bank4, ppu_a[11:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = mir_h ? ppu_a[11] : ppu_a[10];

endmodule
