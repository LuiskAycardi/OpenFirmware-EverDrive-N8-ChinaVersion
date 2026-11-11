`timescale 1ns/1ps
// mapper_fme7.v — Mapper 69 (Sunsoft FME-7 / 5A / 5B). Implementación propia (clean room).
// $8000-$9FFF: número de comando (D3-D0); $A000-$BFFF: dato del comando.
//   0-7: CHR de 1 KB   8: $6000-$7FFF (D6 = RAM, D7 = RAM habilitada, D5-D0 = banco ROM/RAM)
//   9-B: PRG de 8 KB en $8000/$A000/$C000 ($E000 fijo al último)
//   C: mirroring (0 V, 1 H, 2 A, 3 B)   D: IRQ (D0 = IRQ, D7 = contador; reconoce la IRQ)
//   E/F: contador de 16 bits (byte bajo/alto). Cuenta hacia abajo cada ciclo de CPU y dispara al
//   pasar de $0000 a $FFFF.
// PRG-RAM de 32 KB (bancos 0-3). Sin el audio del 5B ($C000/$E000 se ignoran).
// IRQ por ciclos de CPU: en la bajada de M2 primero se aplica la escritura del ciclo y después
// se da el pulso del contador, que equivale al inicio del ciclo siguiente (igual que el chip, que
// cuenta con M2, y que Mesen2, que cuenta al empezar cada ciclo).
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_fme7 (
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
    input  wire        clk,        // reloj del sistema (solo la tabla del DAC del 5B)
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
    output wire [9:0]  snd         // nivel de sonido de expansión (Sunsoft 5B), 0-531
);

    reg [3:0]  cmd;
    reg [7:0]  chr [0:7];
    reg [7:0]  w6000;
    reg [5:0]  p0, p1, p2;
    reg [1:0]  mir;
    reg        irq_en, cnt_en, irq_pend;
    reg [15:0] cnt;
    integer i;
    initial begin
        cmd = 0; w6000 = 0; p0 = 0; p1 = 0; p2 = 0; mir = 0;
        irq_en = 0; cnt_en = 0; irq_pend = 0; cnt = 0;
        for (i = 0; i < 8; i = i + 1) chr[i] = 0;
    end

    wire rom_wr = !romsel_n && !cpu_rw;
    reg [15:0] t_cnt; reg t_pend, t_cnt_en, t_irq_en;
    always @(negedge m2) begin
        if (rst) begin
            cmd <= 0; w6000 <= 0; p0 <= 0; p1 <= 0; p2 <= 0; mir <= cfg[0] ? 2'd0 : 2'd1;
            irq_en <= 0; cnt_en <= 0; irq_pend <= 0; cnt <= 0;
            for (i = 0; i < 8; i = i + 1) chr[i] <= 0;
        end else begin
            t_cnt = cnt; t_pend = irq_pend; t_cnt_en = cnt_en; t_irq_en = irq_en;
            if (rom_wr && cpu_a[14:13] == 2'd0) cmd <= cpu_d[3:0];
            if (rom_wr && cpu_a[14:13] == 2'd1) begin
                case (cmd)
                    4'h8: w6000 <= cpu_d;
                    4'h9: p0 <= cpu_d[5:0];
                    4'hA: p1 <= cpu_d[5:0];
                    4'hB: p2 <= cpu_d[5:0];
                    4'hC: mir <= cpu_d[1:0];
                    4'hD: begin t_irq_en = cpu_d[0]; t_cnt_en = cpu_d[7]; t_pend = 1'b0; end
                    4'hE: t_cnt[7:0]  = cpu_d;
                    4'hF: t_cnt[15:8] = cpu_d;
                    default: chr[cmd[2:0]] <= cpu_d;
                endcase
            end
            if (t_cnt_en) begin
                t_cnt = t_cnt - 16'd1;
                if (t_cnt == 16'hFFFF && t_irq_en) t_pend = 1'b1;
            end
            cnt <= t_cnt; irq_pend <= t_pend; cnt_en <= t_cnt_en; irq_en <= t_irq_en;
        end
    end

    // ------------------------------------------------ sonido Sunsoft 5B ($C000 selección, $E000 dato)
    snd_5b s5b (
        .clk(clk), .m2(m2), .rst(rst),
        .wr_sel(rom_wr && cpu_a[14:13] == 2'd2), .wr_dat(rom_wr && cpu_a[14:13] == 2'd3),
        .d(cpu_d), .out(snd));

    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);
    wire ram_sel  = w6000[6];
    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = p0;
            2'd1: bank8 = p1;
            2'd2: bank8 = p2;
            2'd3: bank8 = 6'b111111;
        endcase
    end
    assign prg_rom_en = !romsel_n || (win_6000 && !ram_sel && m2);           // $6000 puede ser ROM
    assign prg_ram_en = win_6000 && ram_sel && w6000[7] && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = !romsel_n ? {bank8, cpu_a[12:10]} :
                   ram_sel   ? {4'd0, w6000[1:0], cpu_a[12:10]} :           // 32 KB de PRG-RAM
                               {w6000[5:0], cpu_a[12:10]};                  // ROM en $6000

    wire [7:0] cb = chr[ppu_a[12:10]];
    assign chr_a = cfg[7] ? {6'd0, cb[2:0]} : {1'b0, cb};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    // mirroring: 0 vertical, 1 horizontal, 2 pantalla A, 3 pantalla B
    assign ciram_a10 = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : mir[0];
    assign irq = irq_pend;

endmodule
