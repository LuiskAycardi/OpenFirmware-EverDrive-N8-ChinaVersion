`timescale 1ns/1ps
// mapper_taitox1017.v — Mapper 82 (Taito X1-017). Implementación propia (clean room).
// Registros en $7EF0-$7EFF:
//   $7EF0/$7EF1 CHR de 2 KB (bit bajo ignorado)    $7EF2-$7EF5 CHR de 1 KB
//   $7EF6 D0 mirroring (1 = V), D1 modo CHR: 0 = 2 KB en $0000, 1 KB en $1000; 1 = al revés
//   $7EF7/$7EF8/$7EF9 permisos de la RAM: $CA -> $6000-$67FF, $69 -> $6800-$6FFF, $84 -> $7000-$73FF
//   $7EFA/$7EFB/$7EFC PRG de 8 KB en $8000/$A000/$C000 = D >> 2; $E000 fijo al último.
// RAM interna (5 KB con pila) en la PRG-RAM del N8, banco 0.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_taitox1017 (
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

    reg [7:0] c0, c1, c2, c3, c4, c5, perm0, perm1, perm2;
    reg [5:0] p0, p1, p2;
    reg       mir_v, chr_mode;
    initial begin
        c0 = 0; c1 = 0; c2 = 0; c3 = 0; c4 = 0; c5 = 0; perm0 = 0; perm1 = 0; perm2 = 0;
        p0 = 0; p1 = 0; p2 = 0; mir_v = 0; chr_mode = 0;
    end
    wire reg_wr = romsel_n && !cpu_rw && (cpu_a[14:4] == 11'h7EF);
    always @(negedge m2) begin
        if (rst) begin
            c0 <= 0; c1 <= 0; c2 <= 0; c3 <= 0; c4 <= 0; c5 <= 0; perm0 <= 0; perm1 <= 0; perm2 <= 0;
            p0 <= 0; p1 <= 0; p2 <= 0; mir_v <= cfg[0]; chr_mode <= 0;
        end else if (reg_wr) begin
            case (cpu_a[3:0])
                4'h0: c0 <= cpu_d;
                4'h1: c1 <= cpu_d;
                4'h2: c2 <= cpu_d;
                4'h3: c3 <= cpu_d;
                4'h4: c4 <= cpu_d;
                4'h5: c5 <= cpu_d;
                4'h6: begin mir_v <= cpu_d[0]; chr_mode <= cpu_d[1]; end
                4'h7: perm0 <= cpu_d;
                4'h8: perm1 <= cpu_d;
                4'h9: perm2 <= cpu_d;
                4'hA: p0 <= cpu_d[7:2];
                4'hB: p1 <= cpu_d[7:2];
                4'hC: p2 <= cpu_d[7:2];
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
    // $6000-$73FF en tres zonas con permiso propio
    wire in_6000 = romsel_n && (cpu_a[14:13] == 2'b11);
    wire ram_ok  = (cpu_a[12:11] == 2'b00) ? (perm0 == 8'hCA) :
                   (cpu_a[12:11] == 2'b01) ? (perm1 == 8'h69) :
                   (cpu_a[12:10] == 3'b100) ? (perm2 == 8'h84) : 1'b0;
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = in_6000 && ram_ok && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};

    // CHR: la mitad de 2 KB y la de 1 KB se intercambian con chr_mode
    wire [2:0] slot = ppu_a[12:10] ^ {chr_mode, 2'b00};
    reg [7:0] bank1;
    always @(*) begin
        case (slot)
            3'd0: bank1 = {c0[7:1], 1'b0};
            3'd1: bank1 = {c0[7:1], 1'b1};
            3'd2: bank1 = {c1[7:1], 1'b0};
            3'd3: bank1 = {c1[7:1], 1'b1};
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
    assign ciram_a10 = mir_v ? ppu_a[10] : ppu_a[11];

endmodule
