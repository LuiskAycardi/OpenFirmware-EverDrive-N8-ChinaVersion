`timescale 1ns/1ps
// snd_fds.v — Sonido del Famicom Disk System (2C33). Implementación propia (clean room).
//
// Según la descripción pública (NESdev Wiki «FDS audio»); comportamiento contrastado con Mesen2, que es la
// referencia del banco de pruebas (leído para los detalles, nada copiado). Un canal de onda de 64 pasos de 6 bits
// con envolvente de volumen y un modulador de frecuencia (tabla de 64 pasos de 3 bits, contador de 7 bits con
// signo y su propia envolvente). Registros ($4040-$408A, con $4023 D1 = 1; los lee y escribe mapper_fds.v):
//   $4040-$407F  tabla de la onda (6 bits; se escribe con $4089 D7 = 1, que además congela la salida)
//   $4080        envolvente de volumen: D7 = apagada (ganancia = D5-D0), D6 = sube, D5-D0 = velocidad
//   $4082/$4083  frecuencia (12 bits); $4083 D7 = onda parada (vuelve al paso 0), D6 = envolventes paradas
//   $4084        envolvente del modulador (como $4080)
//   $4085        contador del modulador (7 bits con signo)
//   $4086/$4087  frecuencia del modulador; $4087 D7 = modulador parado (y se puede escribir su tabla)
//   $4088        tabla del modulador: cada escritura llena dos pasos
//   $4089        D7 = escribir la onda, D1-D0 = volumen general (2/2, 2/3, 2/4, 2/5)
//   $408A        velocidad general de las envolventes (la BIOS pone $E8)
//   $4090/$4092  (lectura) ganancia del volumen / del modulador
// Envolvente: con D7 = 0 y velocidad general > 0, cada 8 x (velocidad + 1) x general ciclos la ganancia sube o baja
// en 1 (sube hasta 32). Modulador: cada vez que su acumulador de 16 bits se desborda al sumar su frecuencia, lee el
// paso de la tabla (0, +1, +2, +4, poner a 0, -4, -2, -1) y lo suma al contador. Desvío de la frecuencia: contador x
// ganancia / 16 con el redondeo raro del chip, recortado a -64..191, x frecuencia / 64 redondeado. La onda avanza un
// paso cada vez que su acumulador de 16 bits se desborda al sumar frecuencia + desvío.
// Salida: onda x min(ganancia, 32) x {36, 24, 17, 14}[volumen] / 1152, de 0 a 63 (se calcula antes de avanzar la
// onda, como en Mesen2). Dominio de M2: en la bajada de M2 primero la escritura del ciclo y después el reloj.

module snd_fds (
    input  wire       m2,
    input  wire       rst,
    input  wire       wr,          // escritura en $4040-$40FF con el sonido activo ($4023 D1)
    input  wire [7:0] a,           // A7-A0
    input  wire [7:0] d,
    output reg  [5:0] out,
    output wire [5:0] lee          // lo que se lee en a: $4040-$407F (onda), $4090 y $4092 (ganancias)
);

    reg [5:0]  onda [0:63];
    reg [2:0]  tmod [0:63];

    reg [5:0]  v_vel, v_gan, m_vel, m_gan;
    reg        v_off, v_sube, m_off, m_sube;
    reg [16:0] v_t, m_t;                       // hasta 8 x 64 x 255
    reg [11:0] frec, m_frec;
    reg [6:0]  cont;                           // contador del modulador, 7 bits con signo
    reg        m_parado, env_parada, onda_parada, escribe_onda;
    reg [5:0]  m_pos, o_pos;
    reg [15:0] m_acc, o_acc;
    reg [1:0]  mvol;
    reg [7:0]  general;

    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1) begin onda[i] = 0; tmod[i] = 0; end
        v_vel = 0; v_gan = 0; m_vel = 0; m_gan = 0; v_off = 0; v_sube = 0; m_off = 0; m_sube = 0;
        v_t = 0; m_t = 0; frec = 0; m_frec = 0; cont = 0; m_parado = 0; env_parada = 0; onda_parada = 0;
        escribe_onda = 0; m_pos = 0; o_pos = 0; m_acc = 0; o_acc = 0; mvol = 0; general = 8'hE8; out = 0;
    end

    // ---------------------------------------------------------------- funciones
    function [16:0] periodo(input [5:0] vel, input [7:0] gen);   // 8 x (vel + 1) x gen
        periodo = {({1'b0, vel} + 7'd1) * gen, 3'b000};
    endfunction

    // Desvío de la frecuencia de la onda: f(contador, ganancia del modulador, frecuencia), con signo.
    function signed [15:0] desvio(input [6:0] c, input [5:0] g, input [11:0] p);
        reg signed [13:0] t;
        reg signed [9:0]  u;
        reg signed [22:0] w;
        reg signed [16:0] r;
        begin
            t = $signed(c) * $signed({1'b0, g});
            u = t >>> 4;
            if (t[3:0] != 4'd0 && !u[7]) u = u + (c[6] ? -10'sd1 : 10'sd2);
            if (u >= 10'sd192) u = u - 10'sd256;
            else if (u < -10'sd64) u = u + 10'sd256;
            w = $signed({1'b0, p}) * u;
            r = w >>> 6;
            if (w[5:0] >= 6'd32) r = r + 17'sd1;
            desvio = r[15:0];
        end
    endfunction

    function signed [6:0] paso_mod(input [2:0] v);
        case (v)
            3'd0: paso_mod = 7'sd0;
            3'd1: paso_mod = 7'sd1;
            3'd2: paso_mod = 7'sd2;
            3'd3: paso_mod = 7'sd4;
            3'd5: paso_mod = -7'sd4;
            3'd6: paso_mod = -7'sd2;
            3'd7: paso_mod = -7'sd1;
            default: paso_mod = 7'sd0;
        endcase
    endfunction

    // nivel = onda x min(ganancia, 32) x tabla / 1152 = ((x >> 7) x 911) >> 13 (exacto para x < 72 704)
    function [5:0] nivel(input [5:0] w, input [5:0] g, input [1:0] mv);
        reg [5:0]  g32, tv;
        reg [16:0] x;
        reg [22:0] q;
        begin
            g32 = (g > 6'd32) ? 6'd32 : g;
            tv  = (mv == 2'd0) ? 6'd36 : (mv == 2'd1) ? 6'd24 : (mv == 2'd2) ? 6'd17 : 6'd14;
            x   = w * g32 * tv;
            q   = x[16:7] * 13'd911;
            nivel = q[18:13];
        end
    endfunction

    assign lee = (a[7:6] == 2'b01) ? (escribe_onda ? onda[a[5:0]] : onda[o_pos]) :
                 (a == 8'h90) ? v_gan : (a == 8'h92) ? m_gan : 6'd0;

    // ---------------------------------------------------------------- un ciclo de CPU
    // Asignaciones bloqueantes: primero la escritura y después el reloj ven el mismo estado, como en Mesen2.
    reg [16:0] suma_m, suma_o;
    reg signed [16:0] f_total;

    always @(negedge m2) begin
        if (rst) begin
            v_vel = 0; v_gan = 0; m_vel = 0; m_gan = 0; v_off = 0; v_sube = 0; m_off = 0; m_sube = 0;
            v_t = 0; m_t = 0; frec = 0; m_frec = 0; cont = 0; m_parado = 0; env_parada = 0;
            onda_parada = 0; escribe_onda = 0; m_pos = 0; o_pos = 0; m_acc = 0; o_acc = 0; mvol = 0;
            general = 8'hE8; out = 0;
        end else begin
            // 1) la escritura del ciclo
            if (wr) begin
                if (a[7:6] == 2'b01) begin
                    if (escribe_onda) onda[a[5:0]] = d[5:0];
                end else case (a)
                    8'h80: begin
                        v_vel = d[5:0]; v_sube = d[6]; v_off = d[7];
                        v_t = periodo(d[5:0], general);
                        if (d[7]) v_gan = d[5:0];
                    end
                    8'h82: frec[7:0] = d;
                    8'h83: begin
                        env_parada = d[6]; onda_parada = d[7];
                        if (d[7]) o_pos = 6'd0;
                        if (d[6]) begin v_t = periodo(v_vel, general); m_t = periodo(m_vel, general); end
                        frec[11:8] = d[3:0];
                    end
                    8'h84: begin
                        m_vel = d[5:0]; m_sube = d[6]; m_off = d[7];
                        m_t = periodo(d[5:0], general);
                        if (d[7]) m_gan = d[5:0];
                    end
                    8'h85: cont = d[6:0];
                    8'h86: m_frec[7:0] = d;
                    8'h87: begin
                        m_frec[11:8] = d[3:0]; m_parado = d[7];
                        if (d[7]) m_acc = 16'd0;
                    end
                    8'h88: if (m_parado) begin
                        tmod[m_pos] = d[2:0];
                        tmod[m_pos + 6'd1] = d[2:0];
                        m_pos = m_pos + 6'd2;
                    end
                    8'h89: begin mvol = d[1:0]; escribe_onda = d[7]; end
                    8'h8A: general = d;
                    default: ;
                endcase
            end
            // 2) el reloj
            if (!onda_parada && !env_parada) begin
                if (!v_off && general != 8'd0 && v_t != 17'd0) begin
                    v_t = v_t - 17'd1;
                    if (v_t == 17'd0) begin
                        v_t = periodo(v_vel, general);
                        if (v_sube && v_gan < 6'd32) v_gan = v_gan + 6'd1;
                        else if (!v_sube && v_gan != 6'd0) v_gan = v_gan - 6'd1;
                    end
                end
                if (!m_off && general != 8'd0 && m_t != 17'd0) begin
                    m_t = m_t - 17'd1;
                    if (m_t == 17'd0) begin
                        m_t = periodo(m_vel, general);
                        if (m_sube && m_gan < 6'd32) m_gan = m_gan + 6'd1;
                        else if (!m_sube && m_gan != 6'd0) m_gan = m_gan - 6'd1;
                    end
                end
            end
            if (!m_parado && m_frec != 12'd0) begin
                suma_m = {1'b0, m_acc} + {5'd0, m_frec};
                m_acc = suma_m[15:0];
                if (suma_m[16]) begin
                    cont = (tmod[m_pos] == 3'd4) ? 7'd0 : cont + paso_mod(tmod[m_pos]);
                    m_pos = m_pos + 6'd1;
                end
            end
            if (!escribe_onda) out = nivel(onda[o_pos], v_gan, mvol);
            f_total = $signed({5'd0, frec}) + desvio(cont, m_gan, frec);
            if (!onda_parada && f_total > 17'sd0) begin
                suma_o = {1'b0, o_acc} + {1'b0, f_total[15:0]};
                o_acc = suma_o[15:0];
                if (suma_o[16]) o_pos = o_pos + 6'd1;
            end
        end
    end

endmodule
