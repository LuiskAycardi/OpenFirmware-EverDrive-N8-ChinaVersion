`timescale 1ns/1ps
// mapper_taitox1005.v — Mappers 80 y 207 (Taito X1-005). Implementación propia (clean room).
// Registros en $7EF0-$7EFF:
//   $7EF0/$7EF1 CHR de 2 KB en $0000/$0800 (banco y banco + 1 en unidades de 1 KB)
//   $7EF2-$7EF5 CHR de 1 KB en $1000-$1C00     $7EF6/7 mirroring D0 (1 = V)
//   $7EF8/9 permiso de la RAM interna: $A3 la habilita   $7EFA/B, $7EFC/D, $7EFE/F PRG de 8 KB
//   en $8000, $A000 y $C000; $E000 fijo al último.
// RAM interna del chip (128 bytes con espejo, $7F00-$7FFF): va a la PRG-RAM del N8, banco 0, en
// 0x1F00-0x1FFF (A12-A10 directos de la CPU, como en todos los mappers; antes del 2026-11-05 iba en
// 0x0300-0x03FF). A7 llega directa a la SRAM, así que aquí son 256 bytes sin espejo: no afecta a los
// juegos, que no dependen del espejo.
// 207 (Fudou Myouou Den): sin $7EF6; nametables $2000/$2400 = $7EF0 bit 7, $2800/$2C00 = $7EF1 bit 7.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_taitox1005 (
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

    wire M207 = (map_id == 8'd207);

    reg [7:0] c0, c1, c2, c3, c4, c5, perm;
    reg [5:0] p0, p1, p2;
    reg       mir_v;
    initial begin c0 = 0; c1 = 0; c2 = 0; c3 = 0; c4 = 0; c5 = 0; perm = 0; p0 = 0; p1 = 0; p2 = 0; mir_v = 0; end
    wire reg_wr = romsel_n && !cpu_rw && (cpu_a[14:4] == 11'h7EF);
    always @(negedge m2) begin
        if (rst) begin
            c0 <= 0; c1 <= 0; c2 <= 0; c3 <= 0; c4 <= 0; c5 <= 0; perm <= 0;
            p0 <= 0; p1 <= 0; p2 <= 0; mir_v <= cfg[0];
        end else if (reg_wr) begin
            case (cpu_a[3:0])
                4'h0: c0 <= cpu_d;
                4'h1: c1 <= cpu_d;
                4'h2: c2 <= cpu_d;
                4'h3: c3 <= cpu_d;
                4'h4: c4 <= cpu_d;
                4'h5: c5 <= cpu_d;
                4'h6, 4'h7: mir_v <= cpu_d[0];
                4'h8, 4'h9: perm <= cpu_d;
                4'hA, 4'hB: p0 <= cpu_d[5:0];
                4'hC, 4'hD: p1 <= cpu_d[5:0];
                4'hE, 4'hF: p2 <= cpu_d[5:0];
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
    wire ram_win = romsel_n && (cpu_a[14:8] == 7'h7F) && (perm == 8'hA3);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = ram_win && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};

    reg [7:0] bank1;
    always @(*) begin
        case (ppu_a[12:10])
            3'd0: bank1 = c0;
            3'd1: bank1 = c0 + 8'd1;
            3'd2: bank1 = c1;
            3'd3: bank1 = c1 + 8'd1;
            3'd4: bank1 = c2;
            3'd5: bank1 = c3;
            3'd6: bank1 = c4;
            3'd7: bank1 = c5;
        endcase
    end
    assign chr_a = cfg[7] ? {6'd0, bank1[2:0]} : {1'b0, bank1};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    assign ciram_a10 = M207 ? (ppu_a[11] ? c1[7] : c0[7]) : (mir_v ? ppu_a[10] : ppu_a[11]);

endmodule
