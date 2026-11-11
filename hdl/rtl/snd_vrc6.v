`timescale 1ns/1ps
// snd_vrc6.v — Sonido del Konami VRC6 (mappers 24 y 26). Implementación propia (clean room).
//
// Según la descripción pública (NESdev Wiki "VRC6 audio"); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas.
//   $9000/$A000  pulso 1/2: D7 = modo (ignora el ciclo de trabajo), D6-D4 = ciclo (0-7), D3-D0 = volumen
//   $9001/$A001  periodo, bits 7-0          $9002/$A002  D7 = activo, D3-D0 = periodo, bits 11-8
//   $9003        D0 = detener los tres canales, D1 = periodo / 16, D2 = periodo / 256 (D2 manda)
//   $B000        sierra: D5-D0 = paso del acumulador
//   $B001/$B002  periodo de la sierra, como los pulsos
// Pulso: un divisor de 12 bits (cuenta de periodo a 0: periodo + 1 ciclos; optimizado el 2026-11-05,
// antes contaba de periodo + 1 a 1 con 13 bits y tres sumadores más) avanza un paso de 0 a 15; la salida es el volumen
// mientras el paso <= ciclo (o siempre en modo D7). Al desactivarlo, el paso vuelve a 0.
// Sierra: cada vez que el divisor llega a 0 avanza un paso de 0 a 13; en los pasos pares suma el
// paso al acumulador de 8 bits y en el 0 lo pone a 0. Sale el acumulador >> 3 (5 bits).
// Salida: pulso 1 + pulso 2 + sierra, de 0 a 61.
// Dominio de M2: en la bajada de M2 primero se aplica la escritura del ciclo y después el pulso de
// reloj del sonido, que equivale al inicio del ciclo siguiente (igual que la IRQ de los VRC).

module snd_vrc6 (
    input  wire       m2,
    input  wire       rst,
    input  wire       wr,          // escritura en $8000-$FFFF en este ciclo
    input  wire [2:0] page,        // A14-A12 ($9000 = 1, $A000 = 2, $B000 = 3)
    input  wire [1:0] r,           // registro (A1:A0 ya traducidos para el VRC6b)
    input  wire [7:0] d,
    output wire [5:0] out
);

    // --------------------------------------------------- registros
    reg [3:0]  vol1, vol2;
    reg [2:0]  duty1, duty2;
    reg        mode1, mode2, en1, en2, ens;
    reg [11:0] per1, per2, pers;
    reg [5:0]  rate;
    reg        halt;
    reg [3:0]  shift;              // 0, 4 u 8

    // --------------------------------------------------- estado
    reg [11:0] t1, t2, ts;         // divisores: cuentan de periodo a 0 (periodo + 1 ciclos por paso)
    reg [3:0]  s1, s2, ss;
    reg [7:0]  acc;

    initial begin
        vol1 = 0; vol2 = 0; duty1 = 0; duty2 = 0; mode1 = 0; mode2 = 0; en1 = 0; en2 = 0; ens = 0;
        per1 = 1; per2 = 1; pers = 1; rate = 0; halt = 0; shift = 0;
        t1 = 0; t2 = 0; ts = 0; s1 = 0; s2 = 0; ss = 0; acc = 0;
    end

    reg [11:0] n_t1, n_t2, n_ts;
    reg [3:0]  n_s1, n_s2, n_ss;
    reg [7:0]  n_acc;
    reg        n_en1, n_en2, n_ens;
    reg [11:0] n_per1, n_per2, n_pers;
    reg [3:0]  n_shift;
    reg        n_halt;

    always @(negedge m2) begin
        if (rst) begin
            vol1 <= 0; vol2 <= 0; duty1 <= 0; duty2 <= 0; mode1 <= 0; mode2 <= 0;
            en1 <= 0; en2 <= 0; ens <= 0; per1 <= 1; per2 <= 1; pers <= 1; rate <= 0; halt <= 0; shift <= 0;
            t1 <= 0; t2 <= 0; ts <= 0; s1 <= 0; s2 <= 0; ss <= 0; acc <= 0;
        end else begin
            n_t1 = t1; n_t2 = t2; n_ts = ts; n_s1 = s1; n_s2 = s2; n_ss = ss; n_acc = acc;
            n_en1 = en1; n_en2 = en2; n_ens = ens; n_per1 = per1; n_per2 = per2; n_pers = pers;
            n_shift = shift; n_halt = halt;
            // 1) escritura de este ciclo
            if (wr) begin
                case ({page, r})
                    5'b001_00: begin vol1 <= d[3:0]; duty1 <= d[6:4]; mode1 <= d[7]; end
                    5'b001_01: n_per1[7:0] = d;
                    5'b001_10: begin n_per1[11:8] = d[3:0]; n_en1 = d[7]; if (!d[7]) n_s1 = 4'd0; end
                    5'b001_11: begin n_halt = d[0]; n_shift = d[2] ? 4'd8 : d[1] ? 4'd4 : 4'd0; end
                    5'b010_00: begin vol2 <= d[3:0]; duty2 <= d[6:4]; mode2 <= d[7]; end
                    5'b010_01: n_per2[7:0] = d;
                    5'b010_10: begin n_per2[11:8] = d[3:0]; n_en2 = d[7]; if (!d[7]) n_s2 = 4'd0; end
                    5'b011_00: rate <= d[5:0];
                    5'b011_01: n_pers[7:0] = d;
                    5'b011_10: begin n_pers[11:8] = d[3:0]; n_ens = d[7]; if (!d[7]) begin n_acc = 8'd0; n_ss = 4'd0; end end
                    default: ;
                endcase
            end
            // 2) reloj del sonido (inicio del ciclo siguiente)
            if (!n_halt) begin
                if (n_en1) begin
                    if (n_t1 == 12'd0) begin n_s1 = n_s1 + 4'd1; n_t1 = n_per1 >> n_shift; end
                    else n_t1 = n_t1 - 12'd1;
                end
                if (n_en2) begin
                    if (n_t2 == 12'd0) begin n_s2 = n_s2 + 4'd1; n_t2 = n_per2 >> n_shift; end
                    else n_t2 = n_t2 - 12'd1;
                end
                if (n_ens) begin
                    if (n_ts == 12'd0) begin
                        n_ss = (n_ss == 4'd13) ? 4'd0 : n_ss + 4'd1;
                        n_ts = n_pers >> n_shift;
                        if (n_ss == 4'd0)     n_acc = 8'd0;
                        else if (!n_ss[0])    n_acc = n_acc + {2'd0, rate};
                    end else n_ts = n_ts - 12'd1;
                end
            end
            t1 <= n_t1; t2 <= n_t2; ts <= n_ts; s1 <= n_s1; s2 <= n_s2; ss <= n_ss; acc <= n_acc;
            en1 <= n_en1; en2 <= n_en2; ens <= n_ens; per1 <= n_per1; per2 <= n_per2; pers <= n_pers;
            shift <= n_shift; halt <= n_halt;
        end
    end

    // --------------------------------------------------- salida
    wire [3:0] o1 = !en1 ? 4'd0 : (mode1 || s1 <= {1'b0, duty1}) ? vol1 : 4'd0;
    wire [3:0] o2 = !en2 ? 4'd0 : (mode2 || s2 <= {1'b0, duty2}) ? vol2 : 4'd0;
    wire [4:0] os = !ens ? 5'd0 : acc[7:3];
    assign out = {2'd0, o1} + {2'd0, o2} + {1'b0, os};

endmodule
