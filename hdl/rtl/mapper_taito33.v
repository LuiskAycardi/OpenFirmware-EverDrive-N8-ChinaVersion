`timescale 1ns/1ps
// mapper_taito33.v — Mappers 33 (Taito TC0190 / TC0350) y 48 (TC0690). Implementación propia (clean room).
// Registros (A14-A13 y A1-A0, máscara $E003):
//   $8000: PRG de 8 KB en $8000 (D5-D0) y mirroring en D6 (0 = vertical, 1 = horizontal)
//   $8001: PRG de 8 KB en $A000          $8002/$8003: CHR de 2 KB en $0000/$0800
//   $A000-$A003: CHR de 1 KB en $1000/$1400/$1800/$1C00
//   $C000-$FFFF fijo a los 16 KB finales.
// 48 (TC0690, por map_id): $8000 sin mirroring (D5-D0 = PRG); mirroring en $E000 D6 (1 = H).
//   IRQ como la del MMC3 (pulsos de A12 filtrados, a12_filter.v), con estas diferencias:
//   $C000 = recarga invertida (D xor $FF), $C001 = recargar en el próximo pulso, $C002 = activar,
//   $C003 = desactivar. $C000, $C001 y $C003 reconocen la IRQ pendiente (The Flintstones lo
//   necesita). La IRQ llega más tarde que en el MMC3: ~4 ciclos según NESdev; Mesen2 usa 22
//   ciclos de CPU, que quitan el temblor de The Jetsons y Flintstones. Aquí también 22.
//
// Lógica según la descripción pública (NESdev Wiki); casos límite contrastados leyendo la
// referencia MIT de Krikzz (N8 PRO) solo para entenderlos. Todas las salidas son activo-alto.

module mapper_taito33 (
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

    wire M48 = (map_id == 8'd48);

    reg [5:0] p0, p1;
    reg [7:0] c0, c1, c2, c3, c4, c5;
    reg       mir_h;
    reg [7:0] irq_latch;
    reg       irq_en, reload_tgl, ack_tgl;
    initial begin
        p0 = 0; p1 = 0; c0 = 0; c1 = 0; c2 = 0; c3 = 0; c4 = 0; c5 = 0; mir_h = 0;
        irq_latch = 0; irq_en = 0; reload_tgl = 0; ack_tgl = 0;
    end
    wire rom_wr = !romsel_n && !cpu_rw;
    always @(negedge m2) begin
        if (rst) begin
            p0 <= 0; p1 <= 0; c0 <= 0; c1 <= 0; c2 <= 0; c3 <= 0; c4 <= 0; c5 <= 0;
            mir_h <= !cfg[0];
            irq_latch <= 0; irq_en <= 0;
        end else if (M48 && rom_wr && cpu_a[14]) begin          // 48: $C000-$FFFF
            if (cpu_a[13]) mir_h <= cpu_d[6];                     // $E000
            else case (cpu_a[1:0])
                2'd0: begin irq_latch <= ~cpu_d; ack_tgl <= ~ack_tgl; end
                2'd1: begin reload_tgl <= ~reload_tgl; ack_tgl <= ~ack_tgl; end
                2'd2: irq_en <= 1'b1;
                2'd3: begin irq_en <= 1'b0; ack_tgl <= ~ack_tgl; end
            endcase
        end else if (rom_wr && !cpu_a[14]) begin
            case ({cpu_a[13], cpu_a[1:0]})
                3'b000: begin p0 <= cpu_d[5:0]; if (!M48) mir_h <= cpu_d[6]; end
                3'b001: p1 <= cpu_d[5:0];
                3'b010: c0 <= cpu_d;
                3'b011: c1 <= cpu_d;
                3'b100: c2 <= cpu_d;
                3'b101: c3 <= cpu_d;
                3'b110: c4 <= cpu_d;
                3'b111: c5 <= cpu_d;
            endcase
        end
    end

    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = p0;
            2'd1: bank8 = p1;
            2'd2: bank8 = 6'b111110;
            2'd3: bank8 = 6'b111111;
        endcase
    end

    reg [8:0] bank1;
    always @(*) begin
        case (ppu_a[12:10])
            3'd0, 3'd1: bank1 = {c0, ppu_a[10]};
            3'd2, 3'd3: bank1 = {c1, ppu_a[10]};
            3'd4:       bank1 = {1'b0, c2};
            3'd5:       bank1 = {1'b0, c3};
            3'd6:       bank1 = {1'b0, c4};
            default:    bank1 = {1'b0, c5};
        endcase
    end

    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};
    assign chr_a = cfg[7] ? {6'd0, bank1[2:0]} : bank1;
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = mir_h ? ppu_a[11] : ppu_a[10];

    // ------------------------------------------------ IRQ del 48 (dominio clk)
    wire a12_clk, m2_fall;
    a12_filter #(.LOW_M2(4), .W(3)) flt (
        .clk(clk), .m2(m2), .a12(ppu_a[12]), .a12_clk(a12_clk), .m2_fall(m2_fall));

    localparam [4:0] IRQ_DELAY = 5'd22;
    reg [2:0] rel_s = 3'd0, ack_s = 3'd0;
    reg [1:0] en_s  = 2'd0;
    reg [7:0] counter = 8'd0;
    reg       reload = 1'b0, pending = 1'b0;
    reg [4:0] delay = 5'd0;
    wire [7:0] next = (counter == 8'd0 || reload) ? irq_latch : counter - 8'd1;

    always @(posedge clk) begin
        rel_s <= {rel_s[1:0], reload_tgl};
        ack_s <= {ack_s[1:0], ack_tgl};
        en_s  <= {en_s[0], irq_en};
        if (rst || !M48) begin
            counter <= 8'd0; reload <= 1'b0; pending <= 1'b0; delay <= 5'd0;
        end else begin
            if (rel_s[2] != rel_s[1]) begin
                counter <= 8'd0;
                reload  <= 1'b1;
            end else if (a12_clk) begin
                counter <= next;
                reload  <= 1'b0;
                if (next == 8'd0 && en_s[1]) delay <= IRQ_DELAY;
            end
            if (m2_fall && delay != 5'd0) begin
                delay <= delay - 5'd1;
                if (delay == 5'd1) pending <= 1'b1;
            end
            if (ack_s[2] != ack_s[1]) pending <= 1'b0;
        end
    end

    assign irq = pending;

endmodule
