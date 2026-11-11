`timescale 1ns/1ps
// mapper_rambo1.v — Mappers 64 y 158 (Tengen RAMBO-1 / 800037). Implementación propia (clean room).
// Clon ampliado del MMC3. Registros (máscara $E001):
//   $8000 selección: [3:0] registro (0-9, 15), [5] K: CHR de 1 KB en R8/R9, [6] modo PRG,
//         [7] inversión CHR A12          $8001 dato
//   $A000 mirroring D0 (1 = H; el 158 no lo usa)      $C000 valor de recarga
//   $C001 D0 = modo ciclo (si no, pulsos de A12) y recarga en el próximo pulso
//   $E000 desactiva y reconoce           $E001 activa
// CHR (1 KB, tras la inversión): 0 R0, 1 K ? R8 : R0+1, 2 R1, 3 K ? R9 : R1+1, 4-7 R2-R5.
// PRG (8 KB): modo 0 = R6, R7, R15, último; modo 1 = R15, R6, R7, último.
// 158 (Alien Syndrome): como el TxSROM, CIRAM A10 = bit 7 del banco CHR calculado para la
// nametable.
// IRQ (dominio clk, a12_filter.v): en modo A12 la subida cuenta si A12 estuvo bajo > 30 puntos
// (11 bajadas de M2, criterio de Mesen2); en modo ciclo, un pulso cada 4 ciclos de CPU.
// Pulso: con recarga pendiente, contador = recarga + 1 (+ 2 si la recarga es > 1); si vale 0,
// recarga + 1; después se resta 1 y, si queda en 0 y la IRQ está activa, /IRQ baja 2 ciclos de
// CPU después (modo A12) o 1 (modo ciclo). Al pasar de modo ciclo a modo A12 se da un pulso más
// en el siguiente múltiplo de 4 ciclos (Skull & Crossbones). Valores de Mesen2.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_rambo1 (
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

    wire M158 = (map_id == 8'd158);

    reg [7:0] sel;
    reg [7:0] r0, r1, r2, r3, r4, r5, r8, r9;
    reg [5:0] r6, r7, r15;
    reg       mir_h;
    reg [7:0] irq_latch;
    reg       irq_en, cyc_mode, c001_tgl;
    initial begin
        sel = 0; r0 = 0; r1 = 0; r2 = 0; r3 = 0; r4 = 0; r5 = 0; r8 = 0; r9 = 0;
        r6 = 0; r7 = 0; r15 = 0; mir_h = 0; irq_latch = 0; irq_en = 0; cyc_mode = 0; c001_tgl = 0;
    end
    wire rom_wr = !romsel_n && !cpu_rw;
    always @(negedge m2) begin
        if (rst) begin
            sel <= 0; r0 <= 0; r1 <= 0; r2 <= 0; r3 <= 0; r4 <= 0; r5 <= 0; r8 <= 0; r9 <= 0;
            r6 <= 0; r7 <= 0; r15 <= 0; mir_h <= !cfg[0]; irq_latch <= 0; irq_en <= 0; cyc_mode <= 0;
        end else if (rom_wr) begin
            case ({cpu_a[14:13], cpu_a[0]})
                3'b000: sel <= cpu_d;
                3'b001: case (sel[3:0])
                            4'd0: r0 <= cpu_d;   4'd1: r1 <= cpu_d;   4'd2: r2 <= cpu_d;
                            4'd3: r3 <= cpu_d;   4'd4: r4 <= cpu_d;   4'd5: r5 <= cpu_d;
                            4'd6: r6 <= cpu_d[5:0]; 4'd7: r7 <= cpu_d[5:0];
                            4'd8: r8 <= cpu_d;   4'd9: r9 <= cpu_d;
                            4'd15: r15 <= cpu_d[5:0];
                            default: ;
                        endcase
                3'b010: mir_h <= cpu_d[0];
                3'b100: irq_latch <= cpu_d;
                3'b101: begin cyc_mode <= cpu_d[0]; c001_tgl <= ~c001_tgl; end
                3'b110: irq_en <= 1'b0;
                3'b111: irq_en <= 1'b1;
                default: ;
            endcase
        end
    end

    // ------------------------------------------------ PRG
    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = sel[6] ? r15 : r6;
            2'd1: bank8 = sel[6] ? r6  : r7;
            2'd2: bank8 = sel[6] ? r7  : r15;
            2'd3: bank8 = 6'b111111;
        endcase
    end
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};

    // ------------------------------------------------ CHR
    wire [2:0] slot = ppu_a[12:10] ^ {sel[7], 2'b00};
    reg  [7:0] bank1;
    always @(*) begin
        case (slot)
            3'd0: bank1 = r0;
            3'd1: bank1 = sel[5] ? r8 : r0 + 8'd1;
            3'd2: bank1 = r1;
            3'd3: bank1 = sel[5] ? r9 : r1 + 8'd1;
            3'd4: bank1 = r2;
            3'd5: bank1 = r3;
            3'd6: bank1 = r4;
            3'd7: bank1 = r5;
        endcase
    end
    assign chr_a = cfg[7] ? {6'd0, bank1[2:0]} : {1'b0, bank1};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = M158 ? bank1[7] : (mir_h ? ppu_a[11] : ppu_a[10]);

    // ------------------------------------------------ IRQ (dominio clk)
    wire a12_clk, m2_fall;
    a12_filter #(.LOW_M2(11), .W(4)) flt (
        .clk(clk), .m2(m2), .a12(ppu_a[12]), .a12_clk(a12_clk), .m2_fall(m2_fall));

    reg [2:0] c001_s = 3'd0;
    reg [1:0] en_s = 2'd0, cyc_s = 2'd0;
    reg [7:0] counter = 8'd0;
    reg       need_reload = 1'b0, force_clk = 1'b0, pending = 1'b0, mode_q = 1'b0;
    reg [1:0] presc = 2'd0;
    reg [1:0] delay = 2'd0;

    reg [7:0] t_cnt; reg t_rel, t_force; reg [1:0] t_delay, t_presc; reg t_pend;
    always @(posedge clk) begin
        c001_s <= {c001_s[1:0], c001_tgl};
        en_s   <= {en_s[0], irq_en};
        cyc_s  <= {cyc_s[0], cyc_mode};
        if (rst) begin
            counter <= 0; need_reload <= 0; force_clk <= 0; pending <= 0; mode_q <= 0;
            presc <= 0; delay <= 0;
        end else begin
            t_cnt = counter; t_rel = need_reload; t_force = force_clk; t_delay = delay;
            t_presc = presc; t_pend = pending;
            if (c001_s[2] != c001_s[1]) begin                 // escritura en $C001
                if (mode_q && !cyc_s[1]) t_force = 1'b1;       // de ciclo a A12: un pulso más
                if (cyc_s[1]) t_presc = 2'd0;
                t_rel  = 1'b1;
                mode_q <= cyc_s[1];
            end
            if (m2_fall) begin
                if (t_delay != 2'd0) begin
                    t_delay = t_delay - 2'd1;
                    if (t_delay == 2'd0) t_pend = 1'b1;
                end
                if (mode_q || t_force) begin
                    t_presc = t_presc + 2'd1;
                    if (t_presc == 2'd0) begin
                        if (t_rel) begin t_cnt = (irq_latch <= 8'd1) ? irq_latch + 8'd1 : irq_latch + 8'd2; t_rel = 1'b0; end
                        else if (t_cnt == 8'd0) t_cnt = irq_latch + 8'd1;
                        t_cnt = t_cnt - 8'd1;
                        if (t_cnt == 8'd0 && en_s[1]) t_delay = 2'd1;
                        t_force = 1'b0;
                    end
                end
            end
            if (a12_clk && !mode_q) begin
                if (t_rel) begin t_cnt = (irq_latch <= 8'd1) ? irq_latch + 8'd1 : irq_latch + 8'd2; t_rel = 1'b0; end
                else if (t_cnt == 8'd0) t_cnt = irq_latch + 8'd1;
                t_cnt = t_cnt - 8'd1;
                if (t_cnt == 8'd0 && en_s[1]) t_delay = 2'd2;
            end
            if (!en_s[1]) t_pend = 1'b0;                      // $E000: desactiva y reconoce
            counter <= t_cnt; need_reload <= t_rel; force_clk <= t_force; delay <= t_delay;
            presc <= t_presc; pending <= t_pend;
        end
    end
    assign irq = pending;

endmodule
