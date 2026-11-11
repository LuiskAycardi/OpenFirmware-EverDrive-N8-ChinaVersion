`timescale 1ns/1ps
// mapper_sunsoft3.v — Mapper 67 (Sunsoft-3). Implementación propia (clean room).
// Registros (máscara $F800): $8800/$9800/$A800/$B800 CHR de 2 KB; $C800 contador de IRQ (dos
// escrituras: byte alto y después bajo); $D800 D4 = IRQ activa (reinicia el orden de bytes y
// reconoce); $E800 mirroring D1-D0 (0 V, 1 H, 2 A, 3 B); $F800 PRG de 16 KB en $8000.
// IRQ: contador de 16 bits que baja en cada ciclo de CPU con la IRQ activa; al pasar de 0 a
// $FFFF se desactiva y /IRQ baja.
// IRQ por ciclos de CPU en el dominio de M2: en la bajada de M2 primero se aplica la escritura del
// ciclo y después el pulso del contador, que equivale al inicio del ciclo siguiente (como el chip,
// que cuenta con M2, y como Mesen2, que cuenta al empezar cada ciclo).
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_sunsoft3 (
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

    reg [7:0] c0, c1, c2, c3;
    reg [4:0] prg;
    reg [1:0] mir;
    reg [15:0] cnt;
    reg       hi_next, irq_en, pend;
    initial begin c0 = 0; c1 = 0; c2 = 0; c3 = 0; prg = 0; mir = 0; cnt = 0; hi_next = 1; irq_en = 0; pend = 0; end
    wire rom_wr = !romsel_n && !cpu_rw && cpu_a[11];
    reg [15:0] t_cnt; reg t_en, t_pend;
    always @(negedge m2) begin
        if (rst) begin
            c0 <= 0; c1 <= 0; c2 <= 0; c3 <= 0; prg <= 0; mir <= cfg[0] ? 2'd0 : 2'd1;
            cnt <= 0; hi_next <= 1; irq_en <= 0; pend <= 0;
        end else begin
            t_cnt = cnt; t_en = irq_en; t_pend = pend;
            if (rom_wr) begin
                case (cpu_a[14:12])
                    3'd0: c0 <= cpu_d;
                    3'd1: c1 <= cpu_d;
                    3'd2: c2 <= cpu_d;
                    3'd3: c3 <= cpu_d;
                    3'd4: begin
                        if (hi_next) t_cnt[15:8] = cpu_d; else t_cnt[7:0] = cpu_d;
                        hi_next <= !hi_next;
                    end
                    3'd5: begin t_en = cpu_d[4]; hi_next <= 1'b1; t_pend = 1'b0; end
                    3'd6: mir <= cpu_d[1:0];
                    3'd7: prg <= cpu_d[4:0];
                endcase
            end
            if (t_en) begin
                t_cnt = t_cnt - 16'd1;
                if (t_cnt == 16'hFFFF) begin t_en = 1'b0; t_pend = 1'b1; end
            end
            cnt <= t_cnt; irq_en <= t_en; pend <= t_pend;
        end
    end
    assign irq = pend;

    wire [4:0] bank16 = cpu_a[14] ? 5'b11111 : prg;
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank16, cpu_a[13:10]};

    reg [7:0] bank2;
    always @(*) begin
        case (ppu_a[12:11])
            2'd0: bank2 = c0; 2'd1: bank2 = c1; 2'd2: bank2 = c2; 2'd3: bank2 = c3;
        endcase
    end
    assign chr_a = cfg[7] ? {6'd0, bank2[1:0], ppu_a[10]} : {bank2, ppu_a[10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    // mirroring: 0 vertical, 1 horizontal, 2 pantalla A, 3 pantalla B
    assign ciram_a10 = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : mir[0];

endmodule
