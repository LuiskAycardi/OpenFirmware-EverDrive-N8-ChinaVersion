`timescale 1ns/1ps
// vrc_irq.v — Contador de IRQ de Konami (VRC4, VRC6, VRC7). Implementación propia (clean room).
//
// Según la descripción pública (NESdev Wiki "VRC IRQ"); comportamiento contrastado con Mesen2.
//   recarga ($F000 o nibbles): valor con el que se reinicia el contador
//   control: D0 = activar tras reconocer, D1 = activar, D2 = modo ciclo. Con D1 = 1 se carga
//            el contador con la recarga y el preescalador con 341. Reconoce la IRQ pendiente.
//   reconocimiento: activo = D0 del último control; reconoce la IRQ pendiente.
// Cuenta hacia arriba; al pasar de $FF recarga y dispara. Modo ciclo: un pulso por ciclo de CPU.
// Modo scanline: el preescalador resta 3 por ciclo y da un pulso cuando llega a <= 0 (+341),
// es decir, un pulso cada 113,67 ciclos de CPU.
//
// Todo en el dominio de M2: en la bajada de M2 primero se aplica la escritura del ciclo y después
// el pulso del contador, que equivale al inicio del ciclo siguiente (como el chip, que cuenta con
// M2, y como Mesen2, que cuenta al empezar cada ciclo).
// Las entradas wr_* son decodificaciones combinacionales del ciclo actual (válidas en la bajada).

module vrc_irq (
    input  wire       m2,
    input  wire       rst,
    input  wire       wr_lat_lo,   // nibble bajo de la recarga (VRC4)
    input  wire       wr_lat_hi,   // nibble alto de la recarga (VRC4)
    input  wire       wr_lat,      // byte completo de la recarga (VRC6, VRC7)
    input  wire       wr_ctrl,
    input  wire       wr_ack,
    input  wire [7:0] d,
    output wire       irq
);

    reg [7:0] reload, cnt;
    reg       en, en_ack, cycle, pend;
    reg signed [10:0] presc;
    initial begin reload = 0; cnt = 0; en = 0; en_ack = 0; cycle = 0; pend = 0; presc = 0; end

    reg [7:0] t_cnt; reg t_en, t_pend, t_cycle; reg signed [10:0] t_presc;
    always @(negedge m2) begin
        if (rst) begin
            reload <= 0; cnt <= 0; en <= 0; en_ack <= 0; cycle <= 0; pend <= 0; presc <= 0;
        end else begin
            t_cnt = cnt; t_en = en; t_pend = pend; t_presc = presc; t_cycle = cycle;
            // 1) escritura de este ciclo
            if (wr_lat_lo) reload[3:0] <= d[3:0];
            if (wr_lat_hi) reload[7:4] <= d[3:0];
            if (wr_lat)    reload      <= d;
            if (wr_ctrl) begin
                en_ack  <= d[0];
                t_cycle = d[2];
                t_en    = d[1];
                if (d[1]) begin t_cnt = reload; t_presc = 11'sd341; end
                t_pend  = 1'b0;
            end
            if (wr_ack) begin t_en = en_ack; t_pend = 1'b0; end
            // 2) pulso del contador (inicio del ciclo siguiente). Un solo sumador (optimizado el 2026-11-05):
            //    presc - 3 y, si llega a <= 0 (o en modo ciclo), + 341 a la vez: presc + 338. Misma
            //    aritmética de 11 bits que antes.
            if (t_en) begin
                if (t_cycle || t_presc <= 11'sd3) begin
                    if (t_cnt == 8'hFF) begin t_cnt = reload; t_pend = 1'b1; end
                    else t_cnt = t_cnt + 8'd1;
                    t_presc = t_presc + 11'sd338;
                end else
                    t_presc = t_presc - 11'sd3;
            end
            cnt <= t_cnt; en <= t_en; pend <= t_pend; presc <= t_presc; cycle <= t_cycle;
        end
    end

    assign irq = pend;

endmodule
