`timescale 1ns/1ps
// audio_dac.v — Convertidor de 1 bit para el sonido de expansión (pin 97, cpu_exp). Implementación propia.
//
// Modulador sigma-delta de primer orden a la frecuencia de clk (50 MHz): la proporción de ciclos con la
// salida baja es la del nivel sobre su fondo de escala. Convención de polaridad del kit de Krikzz (hecho
// leído, no código): en silencio la salida está alta y el sonido son pulsos bajos. Frente a un PWM de 5 bits
// (el del MMC5 de Krikzz) lleva el ruido de cuantificación a frecuencias altas, que el filtro de la placa
// elimina.
//
// El nivel llega del dominio de M2 (los chips de sonido cuentan ciclos de CPU): se copia solo cuando
// dos muestras seguidas coinciden, para no usar nunca un valor a medio cambiar.
//
// Etapa de ganancia (control de volumen, 2026-11-24; ver docs/sonido-volumen.md):
//   salida = centro_sal + (nivel - centro_ent) x ganancia / 256, saturada al fondo de escala (1023)
// calculada a 14 bits (x16) para no perder resolución con ganancias pequeñas: el modulador trabaja a 14 bits,
// así que con ganancia 256 la densidad de pulsos es nivel / 1024, igual que antes. centro_ent/centro_sal son los
// niveles de reposo de los chips bipolares (N163, VRC7): la ganancia se aplica alrededor de ese punto para que
// no recorte por un lado antes que por el otro. Ganancia y centros cambian solo en el modo OS (son constantes
// mientras suena el juego); los dos registros de la etapa añaden 40 ns de retardo, inapreciables.

module audio_dac (
    input  wire        clk,
    input  wire [9:0]  level,
    input  wire [12:0] gain,        // en 1/256 (256 = x1)
    input  wire [9:0]  c_in,        // nivel de reposo del chip
    input  wire [9:0]  c_out,       // nivel de reposo a la salida
    output wire        pwm
);

    reg [9:0]  l1 = 10'd0, l2 = 10'd0;
    reg signed [24:0] prod = 25'sd0;
    reg [13:0] l3 = 14'd0;
    reg [14:0] acc = 15'd0;

    wire signed [10:0] dif  = $signed({1'b0, l2}) - $signed({1'b0, c_in});
    wire signed [24:0] suma = $signed({1'b0, c_out, 4'b0000}) + (prod >>> 4);

    always @(posedge clk) begin
        l1 <= level;
        if (l1 == level) l2 <= l1;
        prod <= dif * $signed({1'b0, gain});
        l3   <= (suma < 0) ? 14'd0 : (suma > 25'sd16383) ? 14'd16383 : suma[13:0];
        acc  <= {1'b0, acc[13:0]} + {1'b0, l3};
    end

    assign pwm = !acc[14];

endmodule
