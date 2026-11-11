`timescale 1ns/1ps
// mapper_txc.v — Chips TXC y Sachen con registro legible (fase 3d). Implementación propia (clean room).
//   132 (TXC 22211A), 173 (22211C), 172 (22211B, "JV001"), 136 (Sachen 3011), 147 (Sachen TC-U01-1.5M),
//   36 (TXC 01-22000-400) y 143 (Sachen TCA01).
//
// Lógica según la descripción pública (NESdev Wiki "TXC 22211", "INES Mapper 036/132/136/147/172/173");
// comportamiento contrastado con Mesen2, que es la referencia del banco de pruebas.
//
// Núcleo común (chip TXC): acumulador, inversor, registro intermedio, salida y tres indicadores.
//   máscara = 7 (132, 173, 36) o 15 (172, 136, 147: variante JV001, que arranca con "invertir" a 1)
//   $4100 (A & $E103 = $4100): si "incrementar", acumulador + 1; si no, toma los bits bajos del
//         intermedio (y se invierte todo si "invertir")
//   $4101: invertir = D0      $4102: intermedio = D & máscara, inversor = D & ~máscara   $4103: incrementar = D0
//   $8000-$FFFF: salida = acumulador[3:0] y bits del inversor (JV001: [7:4]; el resto: bit 3 -> bit 4)
//   Lectura de $4100 (A & $103 = $100): (acumulador & máscara) | ((inversor ^ invertir) & ~máscara)
//   Y = !invertir || bit 4 del último valor escrito o leído (lo usa el 173 para activar la CHR); a 0
//   al arrancar, como en Mesen2.
// Cada variante pasa los datos por su propio cableado (bits sueltos o en otro orden) y usa la salida
// a su manera; las lecturas solo conducen los bits que conecta su placa (el resto, bus abierto).
// 143: no tiene núcleo; leer $4100-$5FFF devuelve (~A & $3F) | $40 (NROM de 32 KB).
// Ninguna de estas placas tiene PRG-RAM.

module mapper_txc (
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
    input  wire [5:0]  chr_size,   // máscara CHR del OS (0 = 8 KB): la usa el 173

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
    output wire [7:0]  cpu_doe
);

    wire M132 = (map_id == 8'd132), M173 = (map_id == 8'd173), M172 = (map_id == 8'd172),
         M136 = (map_id == 8'd136), M147 = (map_id == 8'd147), M36  = (map_id == 8'd36),
         M143 = (map_id == 8'd143);
    wire JV001 = M172 || M136 || M147;
    wire [7:0] mask = JV001 ? 8'h0F : 8'h07;

    // ------------------------------------------------ cableado de los datos de cada placa
    function [7:0] rev6(input [7:0] v);                  // 172: bits 5-0 al revés
        rev6 = {2'b00, v[0], v[1], v[2], v[3], v[4], v[5]};
    endfunction
    wire [7:0] wv = M172 ? rev6(cpu_d) :
                    M136 ? {2'b00, cpu_d[5:0]} :
                    M147 ? {cpu_d[1:0], cpu_d[7:2]} :
                    M36  ? {6'd0, cpu_d[5:4]} :
                           {4'd0, cpu_d[3:0]};       // 132, 173

    // ------------------------------------------------ zonas
    wire lo      = romsel_n && (cpu_a[14:13] == 2'b10);           // $4000-$5FFF
    wire in_regs = M36 ? (lo && cpu_a[13:8] != 6'd0)               // 36: $4100-$5FFF
                       : (lo && cpu_a[13:5] != 9'd0);              // $4020-$5FFF
    wire txc_lo  = in_regs && cpu_a[8];                            // A & $E103 = $41xx
    wire wr_lo   = in_regs && !cpu_rw;
    wire wr_hi   = !romsel_n && !cpu_rw;
    wire rd_reg  = in_regs && cpu_rw && cpu_a[8] && cpu_a[1:0] == 2'b00;   // A & $103 = $100

    // ------------------------------------------------ núcleo TXC
    reg [7:0] acc, inv, stg, outv, chr36;
    reg       inc, invf, y, started;
    initial begin acc = 0; inv = 0; stg = 0; outv = 0; chr36 = 0; inc = 0; invf = 0; y = 0; started = 0; end

    wire [7:0] rd_val = (acc & mask) | ((inv ^ {8{invf}}) & ~mask);

    reg [7:0] t_acc; reg t_invf;
    always @(negedge m2) begin
        if (rst) begin
            acc <= 0; inv <= 0; stg <= 0; outv <= 0; chr36 <= 0; inc <= 0;
            invf <= 1'b0; y <= 1'b0; started <= 1'b0;
        end else if (!started) begin
            // primer ciclo de juego: map_id ya es el del juego (durante el reset vale $FF, el del OS)
            invf <= JV001; started <= 1'b1;               // el JV001 arranca con "invertir" a 1
        end else if (!M143) begin
            t_acc = acc; t_invf = invf;
            if (wr_lo || wr_hi) begin
                if (wr_lo && txc_lo) begin
                    case (cpu_a[1:0])
                        2'd0: t_acc = inc ? acc + 8'd1 : ((acc & ~mask) | (stg & mask)) ^ {8{invf}};
                        2'd1: t_invf = wv[0];
                        2'd2: begin stg <= wv & mask; inv <= wv & ~mask; end
                        2'd3: inc <= wv[0];
                    endcase
                end
                if (wr_hi)
                    outv <= JV001 ? {inv[7:4], acc[3:0]} : {3'd0, inv[3], acc[3:0]};
                if (M36 && wr_lo && cpu_a[13:12] == 2'b00 && cpu_a[9]) chr36 <= cpu_d;   // A & $F200 = $4200
                y <= !t_invf || wv[4];
                acc <= t_acc; invf <= t_invf;
            end else if (rd_reg) begin
                y <= !invf || rd_val[4];                       // la lectura también fija Y
            end
        end
    end

    // ------------------------------------------------ lecturas
    reg [7:0] dout, doe;
    always @(*) begin
        dout = 8'd0; doe = 8'd0;
        if (M143) begin
            if (lo && cpu_a[13:8] != 6'd0 && cpu_rw) begin dout = {2'b01, ~cpu_a[5:0]}; doe = 8'hFF; end
        end else if (rd_reg) begin
            if (M132 || M173)  begin dout = {4'd0, rd_val[3:0]};               doe = 8'h0F; end
            else if (M172)     begin dout = rev6(rd_val);                       doe = 8'h3F; end
            else if (M136)     begin dout = {2'b00, rd_val[5:0]};               doe = 8'h3F; end
            else if (M147)     begin dout = {rd_val[5:0], rd_val[7:6]};         doe = 8'hFF; end
            else if (M36)      begin dout = {2'b00, rd_val[1:0], 4'd0};         doe = 8'h30; end
        end
    end
    assign cpu_dout = dout;
    assign cpu_doe  = doe;

    // ------------------------------------------------ bancos (PRG de 32 KB, CHR de 8 KB)
    reg [3:0] prg32;
    reg [5:0] chr8;
    reg       chr_on;
    always @(*) begin
        prg32 = 4'd0; chr8 = 6'd0; chr_on = 1'b1;
        if (M132) begin prg32 = {3'd0, outv[2]}; chr8 = {4'd0, outv[1:0]}; end
        else if (M173) begin
            if (chr_size != 6'd0) chr8 = {3'd0, outv[1], y, outv[0]};
            else chr_on = y;
        end
        else if (M172 || M136) chr8 = outv[5:0];
        else if (M147) begin prg32 = {2'd0, outv[5], outv[0]}; chr8 = {2'd0, outv[4:1]}; end
        else if (M36)  begin prg32 = {2'd0, outv[1:0]}; chr8 = chr36[5:0]; end
    end

    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {prg32, cpu_a[14:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {chr8, ppu_a[12:10]};
    assign chr_en   = !ppu_a[13] && chr_on;
    assign chr_wr   = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en = ppu_a[13];
    assign irq      = 1'b0;
    // 172: mirroring = invertir (1 = V); el resto, cabecera
    assign ciram_a10 = M172 ? (invf ? ppu_a[10] : ppu_a[11]) : (cfg[0] ? ppu_a[10] : ppu_a[11]);

endmodule
