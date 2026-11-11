`timescale 1ns/1ps
// mapper_n163.v — Mapper 19 (Namco 163), con su sonido. Implementación propia (clean room).
//
// Según la descripción pública (NESdev Wiki "Namco 163", "Namco 163 audio"); comportamiento contrastado
// con Mesen2, que es la referencia del banco de pruebas. Va en su propio RBF (102).
//
// Registros (máscara $F800):
//   $4800  puerto de la RAM interna de 128 bytes (lectura y escritura; avanza si "autoincremento")
//   $5000  contador de IRQ, bits 7-0 (lectura y escritura; escribir reconoce la IRQ)
//   $5800  contador de IRQ, bit 15 = activo, bits 14-8 (lectura y escritura; reconoce)
//   $8000-$B800  8 bancos CHR de 1 KB ($0000-$1FFF). Un valor >= $E0 elige la CIRAM (página = D0) en vez de
//          la CHR-ROM, salvo que $E800 lo impida (D6 para $0000-$0FFF, D7 para $1000-$1FFF).
//   $C000-$D800  4 nametables: >= $E0 = CIRAM (página D0); si no, un banco de 1 KB de CHR-ROM.
//          Hasta que se escribe cada uno, la nametable sigue el mirroring de la cabecera (como Mesen2).
//   $E000  D5-D0 PRG de 8 KB en $8000; D6 = sonido apagado
//   $E800  D5-D0 PRG en $A000; D6/D7 = sin CIRAM en $0000-$0FFF / $1000-$1FFF
//   $F000  D5-D0 PRG en $C000; $E000-$FFFF fijo al último
//   $F800  D6 = PRG-RAM escribible; D3-D0 = protección de cada 2 KB de $6000-$7FFF (1 = solo lectura);
//          a la vez, D6-D0 = dirección del puerto $4800 y D7 = autoincremento
// IRQ: con el bit 15 a 1, el contador sube en cada ciclo de CPU hasta que los 15 bits bajos valen $7FFF;
//   entonces /IRQ baja (y se queda ahí hasta escribir $5000 o $5800).
// Lecturas de $4800, $5000 y $5800: la FPGA conduce los 8 bits (fase 3d).
//
// Sonido (8 canales de tabla de ondas en la RAM interna; $7F D6-D4 = canales activos - 1):
//   cada 15 ciclos de CPU se actualiza un canal, del 7 hacia abajo: fase += frecuencia (módulo largo x 2^16),
//   muestra de 4 bits en la posición (fase >> 16) + desplazamiento; salida del canal = (muestra - 8) x volumen.
//   La salida es la media de los canales activos (como Mesen2; el chip real los alterna cada 15 ciclos).
//   Nivel para el DAC = (media + 120) x 2 (0-450).
// En la FPGA la RAM es de doble puerto: la CPU por un lado y un motor secuencial a 50 MHz por el otro (tiene
// 15 ciclos de CPU = 420 ciclos de clk para cada actualización).
// Dominio de M2: en la bajada de M2 primero la escritura del ciclo y después el pulso (IRQ y sonido).
// No implementado: guardar la RAM interna con la pila (es memoria de la FPGA; ningún juego de la colección
// guarda ahí, usan la PRG-RAM de $6000).

module mapper_n163 (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,
    input  wire        ppu_wr_n,
    input  wire [7:0]  cfg,
    input  wire        rst,
    input  wire        clk,
    input  wire [7:0]  map_id,
    input  wire [5:0]  chr_size,

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
    output wire [7:0]  cpu_dout,
    output wire [7:0]  cpu_doe,
    output wire [9:0]  snd
);

    // ================================================================ registros (dominio M2)
    reg [7:0]  chr0, chr1, chr2, chr3, chr4, chr5, chr6, chr7;
    reg [7:0]  nt0, nt1, nt2, nt3;
    reg [3:0]  nt_set;
    reg [5:0]  p0, p1, p2;
    reg        snd_off, lo_nt_off, hi_nt_off;
    reg [7:0]  wp;
    reg [6:0]  ram_pos;
    reg        autoinc;
    reg [15:0] cnt;
    reg        irq_pend;
    reg [3:0]  upd_div;
    reg        upd_tgl;            // cambia en cada actualización de canal (cada 15 ciclos)
    reg [6:0]  wr_addr;
    reg [7:0]  wr_data;
    reg        wr_tgl;             // cambia en cada escritura en $4800
    integer    k;

    initial begin
        chr0 = 0; chr1 = 0; chr2 = 0; chr3 = 0; chr4 = 0; chr5 = 0; chr6 = 0; chr7 = 0;
        nt0 = 0; nt1 = 0; nt2 = 0; nt3 = 0; nt_set = 0; p0 = 0; p1 = 0; p2 = 0;
        snd_off = 0; lo_nt_off = 0; hi_nt_off = 0; wp = 0; ram_pos = 0; autoinc = 0;
        cnt = 0; irq_pend = 0; upd_div = 0; upd_tgl = 0; wr_addr = 0; wr_data = 0; wr_tgl = 0;
    end

    wire       half    = cpu_a[11];                          // $x800
    wire       lo_area = romsel_n && cpu_a[14:13] == 2'b10;  // $4000-$5FFF
    wire w4800 = lo_area && !cpu_rw && cpu_a[12:11] == 2'b01;
    wire w5000 = lo_area && !cpu_rw && cpu_a[12:11] == 2'b10;
    wire w5800 = lo_area && !cpu_rw && cpu_a[12:11] == 2'b11;
    wire r4800 = lo_area &&  cpu_rw && cpu_a[12:11] == 2'b01;
    wire r5000 = lo_area &&  cpu_rw && cpu_a[12:11] == 2'b10;
    wire r5800 = lo_area &&  cpu_rw && cpu_a[12:11] == 2'b11;
    wire rom_wr = !romsel_n && !cpu_rw;

    reg [15:0] t_cnt; reg t_pend;
    always @(negedge m2) begin
        if (rst) begin
            chr0 <= 0; chr1 <= 0; chr2 <= 0; chr3 <= 0; chr4 <= 0; chr5 <= 0; chr6 <= 0; chr7 <= 0;
            nt0 <= 0; nt1 <= 0; nt2 <= 0; nt3 <= 0; nt_set <= 0; p0 <= 0; p1 <= 0; p2 <= 0;
            snd_off <= 0; lo_nt_off <= 0; hi_nt_off <= 0; wp <= 0; ram_pos <= 0; autoinc <= 0;
            cnt <= 0; irq_pend <= 0; upd_div <= 0;
        end else begin
            t_cnt = cnt; t_pend = irq_pend;
            // 1) acceso de este ciclo
            if (w4800) begin
                wr_addr <= ram_pos; wr_data <= cpu_d; wr_tgl <= ~wr_tgl;
                if (autoinc) ram_pos <= ram_pos + 7'd1;
            end
            if (r4800 && autoinc) ram_pos <= ram_pos + 7'd1;
            if (w5000) begin t_cnt[7:0]  = cpu_d; t_pend = 1'b0; end
            if (w5800) begin t_cnt[15:8] = cpu_d; t_pend = 1'b0; end
            if (rom_wr) begin
                case ({cpu_a[14:12], half})
                    4'b000_0: chr0 <= cpu_d;   4'b000_1: chr1 <= cpu_d;
                    4'b001_0: chr2 <= cpu_d;   4'b001_1: chr3 <= cpu_d;
                    4'b010_0: chr4 <= cpu_d;   4'b010_1: chr5 <= cpu_d;
                    4'b011_0: chr6 <= cpu_d;   4'b011_1: chr7 <= cpu_d;
                    4'b100_0: begin nt0 <= cpu_d; nt_set[0] <= 1'b1; end
                    4'b100_1: begin nt1 <= cpu_d; nt_set[1] <= 1'b1; end
                    4'b101_0: begin nt2 <= cpu_d; nt_set[2] <= 1'b1; end
                    4'b101_1: begin nt3 <= cpu_d; nt_set[3] <= 1'b1; end
                    4'b110_0: begin p0 <= cpu_d[5:0]; snd_off <= cpu_d[6]; end
                    4'b110_1: begin p1 <= cpu_d[5:0]; lo_nt_off <= cpu_d[6]; hi_nt_off <= cpu_d[7]; end
                    4'b111_0: p2 <= cpu_d[5:0];
                    4'b111_1: begin wp <= cpu_d; ram_pos <= cpu_d[6:0]; autoinc <= cpu_d[7]; end
                endcase
            end
            // 2) pulso (inicio del ciclo siguiente)
            if (t_cnt[15] && t_cnt[14:0] != 15'h7FFF) begin
                t_cnt = t_cnt + 16'd1;
                if (t_cnt[14:0] == 15'h7FFF) t_pend = 1'b1;
            end
            if (!snd_off) begin
                if (upd_div == 4'd14) begin upd_div <= 4'd0; upd_tgl <= ~upd_tgl; end
                else upd_div <= upd_div + 4'd1;
            end
            cnt <= t_cnt; irq_pend <= t_pend;
        end
    end
    assign irq = irq_pend;

    // ================================================================ RAM interna (doble puerto, clk)
    // puerto A: CPU (escrituras de $4800 y lectura continua de la posición actual); puerto B: motor de sonido
    reg [2:0] wr_s = 3'd0;
    always @(posedge clk) wr_s <= {wr_s[1:0], wr_tgl};
    wire       a_we   = (wr_s[2] != wr_s[1]);
    wire [6:0] a_addr = a_we ? wr_addr : ram_pos;
    wire [7:0] a_rd, b_rd;
    reg        b_we = 1'b0;
    reg  [6:0] b_addr = 7'd0;
    reg  [7:0] b_wd = 8'd0;
    ram_dp128 aram (.clk(clk),
        .we_a(a_we), .addr_a(a_addr), .d_a(wr_data), .q_a(a_rd),
        .we_b(b_we), .addr_b(b_addr), .d_b(b_wd), .q_b(b_rd));

    // ================================================================ motor de sonido (clk)
    reg [2:0]  upd_s = 3'd0;
    always @(posedge clk) upd_s <= {upd_s[1:0], upd_tgl};
    wire upd_go = (upd_s[2] != upd_s[1]);

    localparam S_IDLE = 4'd0, S_RD = 4'd1, S_MOD = 4'd2, S_SAMP = 4'd3, S_SAMP2 = 4'd4,
               S_WR0 = 4'd5, S_WR1 = 4'd6, S_WR2 = 4'd7, S_SUM = 4'd8, S_DIV = 4'd9, S_OUT = 4'd10;
    reg [3:0]  st = S_IDLE;
    reg [3:0]  rd_i = 4'd0;            // lecturas pendientes: $7F y los 8 registros del canal
    reg [2:0]  ch = 3'd7;              // canal en curso
    reg [2:0]  nch = 3'd0;             // canales activos - 1
    reg [7:0]  r0, r1, r2, r3, r4, r5, r6, r7;
    reg [24:0] ph;
    reg [24:0] lim;
    reg [7:0]  spos;
    reg signed [7:0] chout [0:7];
    reg signed [11:0] sum = 12'sd0;
    reg [3:0]  si = 4'd0;
    reg [10:0] mag = 11'd0, q = 11'd0;
    reg        neg = 1'b0;
    reg [3:0]  div_n = 4'd0;
    reg [9:0]  level = 10'd240;
    reg [6:0]  clr = 7'd0;             // borrado de la RAM interna durante el menú (Mesen2 la arranca a 0)
    initial for (k = 0; k < 8; k = k + 1) chout[k] = 8'sd0;

    wire [6:0] base = {1'b1, ch, 3'b000};          // $40 + canal x 8
    wire [3:0] nib  = spos[0] ? b_rd[7:4] : b_rd[3:0];
    wire [7:0] samp_pos = ph[23:16] + r6;                    // posición en la tabla de ondas (nibbles)

    always @(posedge clk) begin
        b_we <= 1'b0;
        if (rst) begin
            st <= S_IDLE; ch <= 3'd7; level <= 10'd240; sum <= 12'sd0;
            for (k = 0; k < 8; k = k + 1) chout[k] <= 8'sd0;
            b_we <= 1'b1; b_addr <= clr; b_wd <= 8'd0; clr <= clr + 7'd1;
        end else case (st)
            S_IDLE: if (upd_go) begin
                        b_addr <= 7'h7F; rd_i <= 4'd0; st <= S_RD;
                    end
            // lee $7F y después los 8 bytes del canal (un ciclo de retraso en la RAM)
            S_RD: begin
                    rd_i <= rd_i + 4'd1;
                    b_addr <= base + {3'd0, rd_i};
                    case (rd_i)
                        4'd1: nch <= b_rd[6:4];
                        4'd2: r0 <= b_rd;  4'd3: r1 <= b_rd;  4'd4: r2 <= b_rd;  4'd5: r3 <= b_rd;
                        4'd6: r4 <= b_rd;  4'd7: r5 <= b_rd;  4'd8: r6 <= b_rd;
                        4'd9: begin
                            r7 <= b_rd;
                            // fase + frecuencia; límite = largo << 16, largo = 256 - (R4 & $FC)
                            ph  <= {1'b0, r5, r3, r1} + {7'd0, r4[1:0], r2, r0};
                            lim <= {(9'd256 - {1'b0, r4 & 8'hFC}), 16'd0};
                            st  <= S_MOD;
                        end
                        default: ;
                    endcase
                  end
            S_MOD: if (ph >= lim) ph <= ph - lim;
                   else begin
                       spos <= samp_pos;
                       b_addr <= samp_pos[7:1];
                       st <= S_SAMP;
                   end
            S_SAMP:  st <= S_SAMP2;                    // espera al dato de la RAM
            S_SAMP2: begin
                       chout[ch] <= ($signed({4'd0, nib}) - 8'sd8) * $signed({4'd0, r7[3:0]});
                       b_addr <= base + 7'd1; b_wd <= ph[7:0];   b_we <= 1'b1; st <= S_WR0;
                     end
            S_WR0: begin b_addr <= base + 7'd3; b_wd <= ph[15:8];  b_we <= 1'b1; st <= S_WR1; end
            S_WR1: begin b_addr <= base + 7'd5; b_wd <= ph[23:16]; b_we <= 1'b1; st <= S_WR2; end
            S_WR2: begin sum <= 12'sd0; si <= 4'd7; st <= S_SUM; end
            // suma de los canales 7 .. 7 - nch
            S_SUM: begin
                     sum <= sum + {{4{chout[si[2:0]][7]}}, chout[si[2:0]]};
                     if (si[2:0] == 3'd7 - nch) st <= S_DIV;
                     else si <= si - 4'd1;
                     // preparar la división (en S_DIV, con la suma ya completa)
                   end
            S_DIV: begin
                     // media truncando hacia cero (como el / de C++): resta sucesiva
                     neg <= sum[11];
                     mag <= sum[11] ? -sum[10:0] : sum[10:0];
                     q <= 11'd0; div_n <= {1'b0, nch} + 4'd1;
                     st <= S_OUT;
                   end
            S_OUT: if (mag >= {7'd0, div_n}) begin mag <= mag - {7'd0, div_n}; q <= q + 11'd1; end
                   else begin
                       level <= neg ? (10'd240 - {q[8:0], 1'b0}) : (10'd240 + {q[8:0], 1'b0});
                       // siguiente canal: del 7 hacia abajo, y vuelta al 7 tras el último activo
                       ch <= (ch == 3'd7 - nch) ? 3'd7 : ch - 3'd1;
                       st <= S_IDLE;
                   end
            default: st <= S_IDLE;
        endcase
    end
    assign snd = level;

    // ================================================================ lecturas
    assign cpu_dout = r4800 ? a_rd : r5000 ? cnt[7:0] : cnt[15:8];
    assign cpu_doe  = (r4800 || r5000 || r5800) ? 8'hFF : 8'h00;

    // ================================================================ PRG
    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = p0;
            2'd1: bank8 = p1;
            2'd2: bank8 = p2;
            2'd3: bank8 = 6'b111111;
        endcase
    end
    wire win_6000  = romsel_n && (cpu_a[14:13] == 2'b11);
    wire ram_wr_ok = wp[6] && !wp[{1'b0, cpu_a[12:11]}];
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2 && (cpu_rw || ram_wr_ok);
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};

    // ================================================================ CHR y nametables
    reg [7:0] v;
    always @(*) begin
        if (ppu_a[13])
            case (ppu_a[11:10]) 2'd0: v = nt0; 2'd1: v = nt1; 2'd2: v = nt2; 2'd3: v = nt3; endcase
        else
            case (ppu_a[12:10])
                3'd0: v = chr0; 3'd1: v = chr1; 3'd2: v = chr2; 3'd3: v = chr3;
                3'd4: v = chr4; 3'd5: v = chr5; 3'd6: v = chr6; 3'd7: v = chr7;
            endcase
    end
    wire nt_hdr = ppu_a[13] && !nt_set[ppu_a[11:10]];       // nametable sin escribir: cabecera
    wire use_ciram = nt_hdr ||
                     (v >= 8'hE0 && (ppu_a[13] || (ppu_a[12] ? !hi_nt_off : !lo_nt_off)));
    assign ciram_en  = use_ciram;
    assign ciram_a10 = nt_hdr ? (cfg[0] ? ppu_a[10] : ppu_a[11]) : v[0];
    assign chr_en    = !use_ciram;
    assign chr_a     = cfg[7] ? {6'd0, v[2:0]} : {1'b0, v};
    assign chr_wr    = cfg[7] && !ppu_wr_n && !use_ciram;

endmodule
