`timescale 1ns/1ps
// mapper_ss88006.v — Mapper 18 (Jaleco SS88006). Implementación propia (clean room).
// Registros por nibbles, decodificados con A14-A12 y A1-A0 (A0 = nibble alto):
//   $8000/1 PRG 8 KB en $8000   $8002/3 en $A000   $9000/1 en $C000   ($E000 fijo al último)
//   $A000-$D003: CHR de 1 KB (8 registros: $A000/1, $A002/3, $B000/1 ... $D002/3)
//   $E000-$E003: recarga de IRQ (4 nibbles)   $F000: recarga el contador y reconoce
//   $F001: D0 = IRQ, tamaño del contador (D3: 4 bits, D2: 8, D1: 12, si no 16); reconoce
//   $F002: mirroring (0 H, 1 V, 2 A, 3 B)
// La IRQ decrementa la parte del contador del tamaño elegido cada ciclo y dispara al llegar a 0.
// IRQ por ciclos de CPU: en la bajada de M2 primero se aplica la escritura del ciclo y después
// se da el pulso del contador, que equivale al inicio del ciclo siguiente (igual que el chip, que
// cuenta con M2, y que Mesen2, que cuenta al empezar cada ciclo).
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_ss88006 (
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

    reg [7:0]  prg0, prg1, prg2;
    reg [7:0]  chr [0:7];
    reg [3:0]  rl [0:3];
    reg [15:0] cnt;
    reg [1:0]  size;            // 0: 16 bits, 1: 12, 2: 8, 3: 4
    reg        irq_en, irq_pend;
    reg [1:0]  mir_raw;
    integer i;
    initial begin
        prg0 = 0; prg1 = 0; prg2 = 0;
        for (i = 0; i < 8; i = i + 1) chr[i] = 0;
        for (i = 0; i < 4; i = i + 1) rl[i] = 0;
        cnt = 0; size = 0; irq_en = 0; irq_pend = 0; mir_raw = 0;
    end

    wire rom_wr = !romsel_n && !cpu_rw;
    wire [2:0] pg = cpu_a[14:12];
    wire [3:0] v  = cpu_d[3:0];
    reg [15:0] t_cnt, m; reg t_pend, t_en; reg [1:0] t_size;
    always @(negedge m2) begin
        if (rst) begin
            prg0 <= 0; prg1 <= 0; prg2 <= 0;
            for (i = 0; i < 8; i = i + 1) chr[i] <= 0;
            for (i = 0; i < 4; i = i + 1) rl[i] <= 0;
            cnt <= 0; size <= 0; irq_en <= 0; irq_pend <= 0; mir_raw <= cfg[0] ? 2'd1 : 2'd0;
        end else begin
            t_cnt = cnt; t_pend = irq_pend; t_en = irq_en; t_size = size;
            if (rom_wr) begin
                case (pg)
                    3'd0: if (!cpu_a[1]) begin if (cpu_a[0]) prg0[7:4] <= v; else prg0[3:0] <= v; end
                          else           begin if (cpu_a[0]) prg1[7:4] <= v; else prg1[3:0] <= v; end
                    3'd1: if (!cpu_a[1]) begin if (cpu_a[0]) prg2[7:4] <= v; else prg2[3:0] <= v; end
                    3'd6: rl[cpu_a[1:0]] <= v;
                    3'd7: case (cpu_a[1:0])
                              2'd0: begin t_cnt = {rl[3], rl[2], rl[1], rl[0]}; t_pend = 1'b0; end
                              2'd1: begin
                                  t_pend = 1'b0; t_en = cpu_d[0];
                                  t_size = cpu_d[3] ? 2'd3 : cpu_d[2] ? 2'd2 : cpu_d[1] ? 2'd1 : 2'd0;
                              end
                              2'd2: mir_raw <= cpu_d[1:0];
                              default: ;
                          endcase
                    default: begin   // $A000-$D003: CHR
                        if (cpu_a[0]) chr[{pg[2:0] - 3'd2, 1'b0} | cpu_a[1]][7:4] <= v;
                        else          chr[{pg[2:0] - 3'd2, 1'b0} | cpu_a[1]][3:0] <= v;
                    end
                endcase
            end
            if (t_en) begin
                m = (t_size == 2'd3) ? 16'h000F : (t_size == 2'd2) ? 16'h00FF :
                    (t_size == 2'd1) ? 16'h0FFF : 16'hFFFF;
                if (((t_cnt & m) - 16'd1 & m) == 16'd0) t_pend = 1'b1;
                t_cnt = (t_cnt & ~m) | (((t_cnt & m) - 16'd1) & m);
            end
            cnt <= t_cnt; irq_pend <= t_pend; irq_en <= t_en; size <= t_size;
        end
    end

    reg [7:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = prg0;
            2'd1: bank8 = prg1;
            2'd2: bank8 = prg2;
            2'd3: bank8 = 8'hFF;
        endcase
    end
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8[5:0], cpu_a[12:10]};

    wire [7:0] cb = chr[ppu_a[12:10]];
    assign chr_a = cfg[7] ? {6'd0, cb[2:0]} : {1'b0, cb};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    // mirroring: 0 horizontal, 1 vertical, 2 pantalla A, 3 pantalla B
    assign ciram_a10 = (mir_raw == 2'd0) ? ppu_a[11] : (mir_raw == 2'd1) ? ppu_a[10] : mir_raw[0];
    assign irq = irq_pend;

endmodule
