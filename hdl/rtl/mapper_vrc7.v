`timescale 1ns/1ps
// mapper_vrc7.v — Mapper 85 (Konami VRC7). Implementación propia (clean room).
// VRC7a usa A4 y VRC7b A3 como línea de registro: se combinan (A4 cuenta como A3, salvo en el
// puerto de sonido $9010). Registros (con A5 = 0):
//   $8000/$8008/$9000 PRG de 8 KB en $8000/$A000/$C000; $E000 fijo al último
//   $A000/$A008 ... $D000/$D008 CHR de 1 KB (8 registros)
//   $E000 D1-D0 mirroring (0 V, 1 H, 2 A, 3 B), D7 PRG-RAM activa, D6 silencio (sonido)
//   $E008 recarga de IRQ, $F000 control, $F008 reconocimiento (vrc_irq.v)
//   $9010/$9030: sonido FM (índice de registro / dato), vrc7_fm.v; con $E000 D6 = 1 se ignoran
//   las escrituras y la salida queda en silencio. Una muestra cada 36 ciclos de M2 (3,58 MHz / 72,
//   49 716 Hz, el reloj del chip real es el doble del de la CPU NTSC). Nivel: 512 + muestra / 16.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_vrc7 (
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
    output wire [9:0]  snd
);

    wire [2:0] page = cpu_a[14:12];
    wire sub = cpu_a[3] | cpu_a[4];
    wire rom_wr = !romsel_n && !cpu_rw && !cpu_a[5] && !(page == 3'd1 && cpu_a[4]);

    reg [5:0] p0, p1, p2;
    reg [7:0] c0, c1, c2, c3, c4, c5, c6, c7, ctl;
    initial begin p0 = 0; p1 = 0; p2 = 0; c0 = 0; c1 = 0; c2 = 0; c3 = 0; c4 = 0; c5 = 0; c6 = 0; c7 = 0; ctl = 0; end
    always @(negedge m2) begin
        if (rst) begin
            p0 <= 0; p1 <= 0; p2 <= 0; c0 <= 0; c1 <= 0; c2 <= 0; c3 <= 0; c4 <= 0; c5 <= 0; c6 <= 0; c7 <= 0;
            ctl <= 8'd0;
        end else if (rom_wr) begin
            case ({page, sub})
                4'b000_0: p0 <= cpu_d[5:0];
                4'b000_1: p1 <= cpu_d[5:0];
                4'b001_0: p2 <= cpu_d[5:0];
                4'b010_0: c0 <= cpu_d;
                4'b010_1: c1 <= cpu_d;
                4'b011_0: c2 <= cpu_d;
                4'b011_1: c3 <= cpu_d;
                4'b100_0: c4 <= cpu_d;
                4'b100_1: c5 <= cpu_d;
                4'b101_0: c6 <= cpu_d;
                4'b101_1: c7 <= cpu_d;
                4'b110_0: ctl <= cpu_d;
                default: ;
            endcase
        end
    end

    vrc_irq virq (
        .m2(m2), .rst(rst), .wr_lat_lo(1'b0), .wr_lat_hi(1'b0),
        .wr_lat (rom_wr && page == 3'd6 && sub),
        .wr_ctrl(rom_wr && page == 3'd7 && !sub),
        .wr_ack (rom_wr && page == 3'd7 && sub),
        .d(cpu_d), .irq(irq));

    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = p0;
            2'd1: bank8 = p1;
            2'd2: bank8 = p2;
            2'd3: bank8 = 6'b111111;
        endcase
    end
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && ctl[7] && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};

    reg [7:0] bank1;
    always @(*) begin
        case (ppu_a[12:10])
            3'd0: bank1 = c0; 3'd1: bank1 = c1; 3'd2: bank1 = c2; 3'd3: bank1 = c3;
            3'd4: bank1 = c4; 3'd5: bank1 = c5; 3'd6: bank1 = c6; 3'd7: bank1 = c7;
        endcase
    end
    assign chr_a = cfg[7] ? {6'd0, bank1[2:0]} : {1'b0, bank1};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    wire [1:0] mir = ctl[1:0];
    // mirroring: 0 vertical, 1 horizontal, 2 pantalla A, 3 pantalla B
    assign ciram_a10 = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : mir[0];

    // ------------------------------------------------ sonido FM
    // Dominio M2: puerto de registros y divisor de muestra; se pasan a clk con un conmutador (toggle)
    // sincronizado, el dato se mantiene estable al menos un ciclo de M2 (~560 ns >> 3 ciclos de clk).
    wire snd_port = !romsel_n && !cpu_rw && page == 3'd1 && cpu_a[4] && !ctl[6];
    reg [7:0] fm_reg = 8'd0, fm_dat = 8'd0;
    reg       wr_t = 1'b0, tk_t = 1'b0;
    reg [5:0] div = 6'd0;
    always @(negedge m2) begin
        if (rst) begin
            fm_reg <= 8'd0; div <= 6'd0;
        end else begin
            if (snd_port && !cpu_a[5]) fm_reg <= cpu_d;
            if (snd_port &&  cpu_a[5]) begin fm_dat <= cpu_d; wr_t <= ~wr_t; end
            if (div == 6'd35) begin div <= 6'd0; tk_t <= ~tk_t; end
            else div <= div + 6'd1;
        end
    end
    reg [2:0] wr_s = 3'd0, tk_s = 3'd0, rst_s = 3'b111;
    always @(posedge clk) begin
        wr_s <= {wr_s[1:0], wr_t}; tk_s <= {tk_s[1:0], tk_t}; rst_s <= {rst_s[1:0], rst};
    end
    wire signed [15:0] fm_out;
    vrc7_fm fm (.clk(clk), .rst(rst_s[2]), .wr(wr_s[2] ^ wr_s[1]), .wreg(fm_reg), .wdata(fm_dat),
                .tick(tk_s[2] ^ tk_s[1]), .sample(fm_out), .valid());
    wire signed [11:0] fm_sc = fm_out[15:4];
    wire signed [12:0] fm_lv = 13'sd512 + fm_sc;
    assign snd = ctl[6] ? 10'd512 : (fm_lv < 0) ? 10'd0 : (fm_lv > 13'sd1023) ? 10'd1023 : fm_lv[9:0];

endmodule
