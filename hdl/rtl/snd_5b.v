`timescale 1ns/1ps
// snd_5b.v — Sonido del Sunsoft 5B (FME-7 con audio, mapper 69: Gimmick!). Implementación propia.
//
// Según la descripción pública (NESdev Wiki "Sunsoft 5B audio"). El 5B es un YM2149F con el divisor
// de reloj activado: tonos y ruido van a la mitad de velocidad que un AY-3-8910 al mismo reloj.
//   $C000-$DFFF  selección de registro (si los bits 7-4 no son 0, $E000 no escribe)
//   $E000-$FFFF  dato
//   R0-R5  periodos de tono A/B/C (12 bits)    R6  periodo de ruido (5 bits)
//   R7     mezclador: bits 2-0 = tono A/B/C apagado, bits 5-3 = ruido apagado (1 = apagado)
//   R8-RA  bit 4 = volumen de la envolvente, bits 3-0 = volumen
//   RB/RC  periodo de la envolvente (16 bits)  RD  forma de la envolvente (escribirla la reinicia)
// Todo cuenta en "ticks" de M2/2 (un ciclo de CPU sí y otro no, como Mesen2):
//   tono:  cada periodo de ticks avanza un paso de 0 a 15; salida 1 en los pasos 0-7
//          (frecuencia = CPU / (32 x periodo); periodo 0 = 1).
//   ruido: LFSR de 17 bits (tomas 16 y 13), un bit nuevo cada 16 x periodo ticks.
//   envolvente: un paso cada 8 x periodo ticks; rampas de 32 niveles; formas del AY (continuar,
//          ataque, alternar, mantener).
// Canal: (tono o tono apagado) y (ruido o ruido apagado); con los dos apagados queda el nivel fijo.
// Nivel de 5 bits: envolvente, o volumen v -> 2v + 1 (0 si v = 0). DAC logarítmico de 1,5 dB por
// paso (niveles 0 y 1 en silencio); la tabla reproduce la de Mesen2 para los niveles impares (los que
// da el registro de volumen). Salida: suma lineal de los tres canales, de 0 a 531.
// Mesen2 no modela el ruido ni la envolvente, y con el tono apagado da 0: Gimmick! no los usa.

module snd_5b (
    input  wire       clk,         // reloj del sistema: lectura de la tabla del DAC (M4K)
    input  wire       m2,
    input  wire       rst,
    input  wire       wr_sel,      // escritura en $C000-$DFFF
    input  wire       wr_dat,      // escritura en $E000-$FFFF
    input  wire [7:0] d,
    output wire [9:0] out
);

    reg [7:0]  sel;
    reg [11:0] per0, per1, per2;
    reg [4:0]  nper;
    reg [5:0]  mix;
    reg [4:0]  vol0, vol1, vol2;     // bit 4 = envolvente
    reg [15:0] eper;
    reg [3:0]  shape;

    reg        tick;
    reg [11:0] t0, t1, t2;
    reg [3:0]  s0, s1, s2;
    reg [3:0]  ndiv;
    reg [4:0]  nt;
    reg [16:0] lfsr;
    reg [2:0]  ediv;
    reg [15:0] et;
    reg [4:0]  ecnt, eatt;
    reg        ehold;

    initial begin
        sel = 0; per0 = 0; per1 = 0; per2 = 0; nper = 0; mix = 0; vol0 = 0; vol1 = 0; vol2 = 0; eper = 0; shape = 0;
        tick = 0; t0 = 0; t1 = 0; t2 = 0; s0 = 0; s1 = 0; s2 = 0; ndiv = 0; nt = 0; lfsr = 17'd1;
        ediv = 0; et = 0; ecnt = 0; eatt = 0; ehold = 1;
    end

    wire w = wr_dat && (sel[7:4] == 4'd0);
    // forma de la envolvente: C = 0 -> una rampa y mantener (alternar = A)
    wire e_hold = shape[3] ? shape[0] : 1'b1;
    wire e_alt  = shape[3] ? shape[1] : shape[2];

    reg [11:0] n_t0, n_t1, n_t2; reg [3:0] n_s0, n_s1, n_s2;
    reg [3:0] n_ndiv; reg [4:0] n_nt; reg [16:0] n_lfsr;
    reg [2:0] n_ediv; reg [15:0] n_et; reg [4:0] n_ecnt, n_eatt; reg n_ehold;

    always @(negedge m2) begin
        if (rst) begin
            sel <= 0; per0 <= 0; per1 <= 0; per2 <= 0; nper <= 0; mix <= 0; vol0 <= 0; vol1 <= 0; vol2 <= 0;
            eper <= 0; shape <= 0;
            tick <= 0; t0 <= 0; t1 <= 0; t2 <= 0; s0 <= 0; s1 <= 0; s2 <= 0; ndiv <= 0; nt <= 0; lfsr <= 17'd1;
            ediv <= 0; et <= 0; ecnt <= 0; eatt <= 0; ehold <= 1;
        end else begin
            n_t0 = t0; n_t1 = t1; n_t2 = t2; n_s0 = s0; n_s1 = s1; n_s2 = s2;
            n_ndiv = ndiv; n_nt = nt; n_lfsr = lfsr; n_ediv = ediv; n_et = et;
            n_ecnt = ecnt; n_eatt = eatt; n_ehold = ehold;
            // 1) escritura de este ciclo
            if (wr_sel) sel <= d;
            if (w) begin
                case (sel[3:0])
                    4'h0: per0[7:0]  <= d;
                    4'h1: per0[11:8] <= d[3:0];
                    4'h2: per1[7:0]  <= d;
                    4'h3: per1[11:8] <= d[3:0];
                    4'h4: per2[7:0]  <= d;
                    4'h5: per2[11:8] <= d[3:0];
                    4'h6: nper <= d[4:0];
                    4'h7: mix  <= d[5:0];
                    4'h8: vol0 <= d[4:0];
                    4'h9: vol1 <= d[4:0];
                    4'hA: vol2 <= d[4:0];
                    4'hB: eper[7:0]  <= d;
                    4'hC: eper[15:8] <= d;
                    4'hD: begin
                        shape <= d[3:0];
                        n_ecnt = 5'd31; n_eatt = d[2] ? 5'd31 : 5'd0; n_ehold = 1'b0; n_ediv = 3'd0; n_et = eper;
                    end
                    default: ;
                endcase
            end
            // 2) reloj del sonido: un tick cada dos ciclos de CPU
            if (tick) begin
                if (n_t0 <= 12'd1) begin n_t0 = per0; n_s0 = n_s0 + 4'd1; end else n_t0 = n_t0 - 12'd1;
                if (n_t1 <= 12'd1) begin n_t1 = per1; n_s1 = n_s1 + 4'd1; end else n_t1 = n_t1 - 12'd1;
                if (n_t2 <= 12'd1) begin n_t2 = per2; n_s2 = n_s2 + 4'd1; end else n_t2 = n_t2 - 12'd1;
                n_ndiv = n_ndiv + 4'd1;
                if (n_ndiv == 4'd0) begin
                    if (n_nt <= 5'd1) begin n_nt = nper; n_lfsr = {n_lfsr[0] ^ n_lfsr[3], n_lfsr[16:1]}; end
                    else n_nt = n_nt - 5'd1;
                end
                n_ediv = n_ediv + 3'd1;
                if (n_ediv == 3'd0) begin
                    if (n_et <= 16'd1) begin
                        n_et = eper;
                        if (!n_ehold) begin
                            if (n_ecnt == 5'd0) begin
                                if (e_alt) n_eatt = ~n_eatt;
                                if (e_hold) n_ehold = 1'b1; else n_ecnt = 5'd31;
                            end else n_ecnt = n_ecnt - 5'd1;
                        end
                    end else n_et = n_et - 16'd1;
                end
            end
            tick <= !tick;
            t0 <= n_t0; t1 <= n_t1; t2 <= n_t2; s0 <= n_s0; s1 <= n_s1; s2 <= n_s2;
            ndiv <= n_ndiv; nt <= n_nt; lfsr <= n_lfsr; ediv <= n_ediv; et <= n_et;
            ecnt <= n_ecnt; eatt <= n_eatt; ehold <= n_ehold;
        end
    end

    // --------------------------------------------------- salida
    wire [4:0] env = ecnt ^ eatt;

    // Nivel de 5 bits de cada canal (0 = en silencio). Función pura (todo por argumentos).
    function [4:0] nivel(input [3:0] step, input tone_off, input noise_off, input [4:0] vol,
                         input [4:0] e, input nz);
        begin
            if ((!step[3] || tone_off) && (nz || noise_off))
                nivel = vol[4] ? e : (vol[3:0] == 4'd0) ? 5'd0 : {vol[3:0], 1'b1};
            else
                nivel = 5'd0;
        end
    endfunction

    function [7:0] dac(input [4:0] l);         // 1,5 dB por paso (tabla de Mesen2 en los impares)
        case (l)
            5'd0, 5'd1: dac = 8'd0;
            5'd2, 5'd3, 5'd4, 5'd5: dac = 8'd1;
            5'd6, 5'd7: dac = 8'd2;
            5'd8, 5'd9: dac = 8'd3;
            5'd10: dac = 8'd4;    5'd11: dac = 8'd5;    5'd12: dac = 8'd6;    5'd13: dac = 8'd7;
            5'd14: dac = 8'd9;    5'd15: dac = 8'd11;   5'd16: dac = 8'd13;   5'd17: dac = 8'd15;
            5'd18: dac = 8'd18;   5'd19: dac = 8'd22;   5'd20: dac = 8'd26;   5'd21: dac = 8'd31;
            5'd22: dac = 8'd37;   5'd23: dac = 8'd44;   5'd24: dac = 8'd53;   5'd25: dac = 8'd63;
            5'd26: dac = 8'd74;   5'd27: dac = 8'd89;   5'd28: dac = 8'd105;  5'd29: dac = 8'd125;
            5'd30: dac = 8'd149;  default: dac = 8'd177;
        endcase
    endfunction

    // Tabla del DAC en ROM (bloques M4K, optimizado el 2026-11-05): con la lógica ocupaba unos 65 LE para
    // los tres canales. Lectura síncrona con clk y suma registrada: la salida cambia 2-3 ciclos de clk
    // (40-60 ns) después de la bajada de M2, y audio_dac solo toma niveles estables: no afecta al sonido.
    // Una copia por canal: un bloque M4K da como mucho dos lecturas por ciclo.
    (* romstyle = "M4K" *) reg [7:0] tabla0 [0:31];
    (* romstyle = "M4K" *) reg [7:0] tabla1 [0:31];
    (* romstyle = "M4K" *) reg [7:0] tabla2 [0:31];
    integer k;
    initial for (k = 0; k < 32; k = k + 1) begin
        tabla0[k] = dac(k[4:0]); tabla1[k] = dac(k[4:0]); tabla2[k] = dac(k[4:0]);
    end

    wire [4:0] n0 = nivel(s0, mix[0], mix[3], vol0, env, lfsr[0]);
    wire [4:0] n1 = nivel(s1, mix[1], mix[4], vol1, env, lfsr[0]);
    wire [4:0] n2 = nivel(s2, mix[2], mix[5], vol2, env, lfsr[0]);
    reg  [7:0] q0 = 8'd0, q1 = 8'd0, q2 = 8'd0;
    always @(posedge clk) begin                 // lectura síncrona: así Quartus usa un bloque M4K
        q0 <= tabla0[n0];
        q1 <= tabla1[n1];
        q2 <= tabla2[n2];
    end

    reg  [9:0] suma = 10'd0;                    // suma registrada: camino corto hasta audio_dac
    always @(posedge clk) suma <= {2'd0, q0} + {2'd0, q1} + {2'd0, q2};
    assign out = suma;

endmodule
