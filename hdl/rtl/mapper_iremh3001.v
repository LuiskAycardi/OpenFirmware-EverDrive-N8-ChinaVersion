`timescale 1ns/1ps
// mapper_iremh3001.v — Mapper 65 (Irem H3001). Implementación propia (clean room).
// $8000 PRG0, $A000 PRG1, $C000 PRG2 (8 KB); $E000 fijo al último. Al arrancar: 0, 1, penúltimo.
// $9001 mirroring D7 (1 = H)   $9003 D7 = IRQ activa (reconoce)   $9004 recarga el contador (reconoce)
// $9005/$9006 byte alto/bajo del valor de recarga     $B000-$B007 CHR de 1 KB
// Se decodifican A14-A12 y A2-A0. IRQ: contador de 16 bits que baja en cada ciclo de CPU con la
// IRQ activa; al llegar a 0 se desactiva y /IRQ baja.
// IRQ por ciclos de CPU en el dominio de M2: en la bajada de M2 primero se aplica la escritura del
// ciclo y después el pulso del contador, que equivale al inicio del ciclo siguiente (como el chip,
// que cuenta con M2, y como Mesen2, que cuenta al empezar cada ciclo).
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_iremh3001 (
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
    reg       mir_h, irq_en, pend;
    reg [15:0] latch, cnt;
    reg [7:0] c0, c1, c2, c3, c4, c5, c6, c7;
    initial begin
        p0 = 0; p1 = 1; p2 = 6'b111110; mir_h = 0; irq_en = 0; pend = 0; latch = 0; cnt = 0;
        c0 = 0; c1 = 0; c2 = 0; c3 = 0; c4 = 0; c5 = 0; c6 = 0; c7 = 0;
    end
    wire rom_wr = !romsel_n && !cpu_rw;
    reg [15:0] t_cnt; reg t_en, t_pend;
    always @(negedge m2) begin
        if (rst) begin
            p0 <= 0; p1 <= 1; p2 <= 6'b111110; mir_h <= !cfg[0]; irq_en <= 0; pend <= 0; latch <= 0; cnt <= 0;
            c0 <= 0; c1 <= 0; c2 <= 0; c3 <= 0; c4 <= 0; c5 <= 0; c6 <= 0; c7 <= 0;
        end else begin
            t_cnt = cnt; t_en = irq_en; t_pend = pend;
            if (rom_wr) begin
                case (cpu_a[14:12])
                    3'd0: if (cpu_a[2:0] == 3'd0) p0 <= cpu_d[5:0];
                    3'd1: case (cpu_a[2:0])
                              3'd1: mir_h <= cpu_d[7];
                              3'd3: begin t_en = cpu_d[7]; t_pend = 1'b0; end
                              3'd4: begin t_cnt = latch; t_pend = 1'b0; end
                              3'd5: latch[15:8] <= cpu_d;
                              3'd6: latch[7:0]  <= cpu_d;
                              default: ;
                          endcase
                    3'd2: if (cpu_a[2:0] == 3'd0) p1 <= cpu_d[5:0];
                    3'd3: case (cpu_a[2:0])
                              3'd0: c0 <= cpu_d; 3'd1: c1 <= cpu_d; 3'd2: c2 <= cpu_d; 3'd3: c3 <= cpu_d;
                              3'd4: c4 <= cpu_d; 3'd5: c5 <= cpu_d; 3'd6: c6 <= cpu_d; 3'd7: c7 <= cpu_d;
                          endcase
                    3'd4: if (cpu_a[2:0] == 3'd0) p2 <= cpu_d[5:0];
                    default: ;
                endcase
            end
            if (t_en) begin
                t_cnt = t_cnt - 16'd1;
                if (t_cnt == 16'd0) begin t_en = 1'b0; t_pend = 1'b1; end
            end
            cnt <= t_cnt; irq_en <= t_en; pend <= t_pend;
        end
    end
    assign irq = pend;

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
    assign prg_ram_en = win_6000 && m2;
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
    assign ciram_a10 = mir_h ? ppu_a[11] : ppu_a[10];

endmodule
