`timescale 1ns/1ps
// mapper_vrc6.v — Mappers 24 y 26 (Konami VRC6a / VRC6b). Implementación propia (clean room).
// 26 (VRC6b) intercambia A0 y A1. Registros (máscara $F003, tras el intercambio):
//   $8000-$8003 PRG de 16 KB en $8000 (D3-D0)      $C000-$C003 PRG de 8 KB en $C000 (D4-D0)
//   $B003 modo: D1-D0 modo CHR, D4 nametables desde CHR-ROM, D5 bancos CHR de 2 KB con A10,
//         D7 PRG-RAM activa (los demás bits eligen el mirroring)
//   $D000-$D003 / $E000-$E003 registros CHR R0-R3 / R4-R7     $E000-$FFFF: $E000 fijo al último
//   $F000 recarga de IRQ, $F001 control, $F002 reconocimiento (vrc_irq.v)
//   $9000-$B002: sonido del VRC6 (snd_vrc6.v), por el pin 97: se oye en la Famicom.
// CHR: modo 0 = R0-R7 de 1 KB; modo 1 = R0-R3 de 2 KB; modo 2/3 = R0-R3 de 1 KB y R4/R5 de 2 KB.
//   Con D5, un banco de 2 KB usa R & $FE y R | 1; sin D5, R y R (los dos KB iguales).
// Nametables: la tabla de Mesen2/NESdev da un registro por nametable; su bit 0 elige la página
// de la CIRAM y, con D4, el registro entero es el banco de CHR-ROM de 1 KB.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_vrc6 (
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
    output wire        irq,
    output wire [9:0]  snd         // nivel de sonido de expansión (VRC6), 0-488
);

    wire M26 = (map_id == 8'd26);
    wire a0 = M26 ? cpu_a[1] : cpu_a[0];
    wire a1 = M26 ? cpu_a[0] : cpu_a[1];
    wire [2:0] page = cpu_a[14:12];
    wire rom_wr = !romsel_n && !cpu_rw;

    reg [3:0] p16;
    reg [4:0] p8;
    reg [7:0] mode;
    reg [7:0] r0, r1, r2, r3, r4, r5, r6, r7;
    initial begin p16 = 0; p8 = 0; mode = 0; r0 = 0; r1 = 0; r2 = 0; r3 = 0; r4 = 0; r5 = 0; r6 = 0; r7 = 0; end
    always @(negedge m2) begin
        if (rst) begin
            p16 <= 0; p8 <= 0; mode <= 8'hA0 | (cfg[0] ? 8'h00 : 8'h04);   // cabecera, RAM activa
            r0 <= 0; r1 <= 0; r2 <= 0; r3 <= 0; r4 <= 0; r5 <= 0; r6 <= 0; r7 <= 0;
        end else if (rom_wr) begin
            case (page)
                3'd0: p16 <= cpu_d[3:0];
                3'd3: if ({a1, a0} == 2'd3) mode <= cpu_d;
                3'd4: p8 <= cpu_d[4:0];
                3'd5: case ({a1, a0}) 2'd0: r0 <= cpu_d; 2'd1: r1 <= cpu_d; 2'd2: r2 <= cpu_d; 2'd3: r3 <= cpu_d; endcase
                3'd6: case ({a1, a0}) 2'd0: r4 <= cpu_d; 2'd1: r5 <= cpu_d; 2'd2: r6 <= cpu_d; 2'd3: r7 <= cpu_d; endcase
                default: ;
            endcase
        end
    end

    // ------------------------------------------------ sonido ($9000-$B002): snd_vrc6.v; nivel x 8
    wire [5:0] snd_raw;
    snd_vrc6 sv6 (.m2(m2), .rst(rst), .wr(rom_wr), .page(page), .r({a1, a0}), .d(cpu_d), .out(snd_raw));
    assign snd = {1'b0, snd_raw, 3'b000};

    // ------------------------------------------------ IRQ
    wire irq_wr = rom_wr && (page == 3'd7);
    vrc_irq virq (
        .m2(m2), .rst(rst), .wr_lat_lo(1'b0), .wr_lat_hi(1'b0),
        .wr_lat(irq_wr && {a1, a0} == 2'd0), .wr_ctrl(irq_wr && {a1, a0} == 2'd1),
        .wr_ack(irq_wr && {a1, a0} == 2'd2), .d(cpu_d), .irq(irq));

    // ------------------------------------------------ PRG
    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = {1'b0, p16, 1'b0};
            2'd1: bank8 = {1'b0, p16, 1'b1};
            2'd2: bank8 = {1'b0, p8};
            2'd3: bank8 = 6'b111111;
        endcase
    end
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && mode[7] && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};

    // ------------------------------------------------ CHR
    wire [7:0] msk = mode[5] ? 8'hFE : 8'hFF;
    wire [7:0] orb = {7'd0, mode[5]};
    reg  [7:0] bank1;
    always @(*) begin
        case (mode[1:0])
            2'd0: case (ppu_a[12:10])
                      3'd0: bank1 = r0; 3'd1: bank1 = r1; 3'd2: bank1 = r2; 3'd3: bank1 = r3;
                      3'd4: bank1 = r4; 3'd5: bank1 = r5; 3'd6: bank1 = r6; 3'd7: bank1 = r7;
                  endcase
            2'd1: case (ppu_a[12:11])
                      2'd0: bank1 = (r0 & msk) | (ppu_a[10] ? orb : 8'd0);
                      2'd1: bank1 = (r1 & msk) | (ppu_a[10] ? orb : 8'd0);
                      2'd2: bank1 = (r2 & msk) | (ppu_a[10] ? orb : 8'd0);
                      2'd3: bank1 = (r3 & msk) | (ppu_a[10] ? orb : 8'd0);
                  endcase
            default: case (ppu_a[12:10])
                      3'd0: bank1 = r0; 3'd1: bank1 = r1; 3'd2: bank1 = r2; 3'd3: bank1 = r3;
                      3'd4, 3'd5: bank1 = (r4 & msk) | (ppu_a[10] ? orb : 8'd0);
                      default:    bank1 = (r5 & msk) | (ppu_a[10] ? orb : 8'd0);
                  endcase
        endcase
    end

    // ------------------------------------------------ nametables
    wire [1:0] nt = ppu_a[11:10];
    wire [7:0] r6e = r6 & 8'hFE, r7e = r7 & 8'hFE;
    reg  [7:0] ntr;
    always @(*) begin
        case (mode & 8'h2F)
            8'h20, 8'h27: ntr = nt[1] ? (r7e | nt[0]) : (r6e | nt[0]);
            8'h23, 8'h24: ntr = nt[0] ? (r7e | nt[1]) : (r6e | nt[1]);
            8'h28, 8'h2F: ntr = nt[1] ? r7e : r6e;
            8'h2B, 8'h2C: ntr = nt[0] ? (r7e | 8'd1) : (r6e | 8'd1);
            default: case (mode[2:0])
                         3'd1, 3'd5: case (nt) 2'd0: ntr = r4; 2'd1: ntr = r5; 2'd2: ntr = r6; 2'd3: ntr = r7; endcase
                         3'd2, 3'd3, 3'd4: ntr = nt[0] ? r7 : r6;
                         default: ntr = nt[1] ? r7 : r6;          // 0, 6, 7
                     endcase
        endcase
    end
    wire nt_rom = ppu_a[13] && mode[4];
    assign chr_a = nt_rom ? {1'b0, ntr} :
                   cfg[7] ? {6'd0, bank1[2:0]} : {1'b0, bank1};
    assign chr_en    = !ppu_a[13] || nt_rom;
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13] && !mode[4];
    assign ciram_a10 = ntr[0];

endmodule
