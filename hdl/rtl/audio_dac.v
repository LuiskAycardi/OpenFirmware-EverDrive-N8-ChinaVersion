`timescale 1ns/1ps
// audio_dac.v — Convertidor de 1 bit para el sonido de expansión (pin 97, cpu_exp). Implementación propia.
//
// Modulador sigma-delta de primer orden a la frecuencia de clk (50 MHz): la proporción de ciclos con la
// salida baja es nivel / 1024. Convención de polaridad del kit de Krikzz (hecho leído, no código): en
// silencio la salida está alta y el sonido son pulsos bajos. Frente a un PWM de 5 bits (el del MMC5 de
// Krikzz) da 10 bits de resolución y lleva el ruido de cuantificación a frecuencias altas, que el
// filtro de la placa elimina.
//
// El nivel llega del dominio de M2 (los chips de sonido cuentan ciclos de CPU): se copia solo cuando
// dos muestras seguidas coinciden, para no usar nunca un valor a medio cambiar.

module audio_dac (
    input  wire       clk,
    input  wire [9:0] level,
    output wire       pwm
);

    reg [9:0]  l1 = 10'd0, l2 = 10'd0;
    reg [10:0] acc = 11'd0;

    always @(posedge clk) begin
        l1 <= level;
        if (l1 == level) l2 <= l1;
        acc <= {1'b0, acc[9:0]} + {1'b0, l2};
    end

    assign pwm = !acc[10];

endmodule
