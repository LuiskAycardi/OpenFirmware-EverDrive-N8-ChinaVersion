`timescale 1ns/1ps
// audio_tono.v — Generador de prueba del camino de sonido de expansión (pin 97, cpu_exp).
// Implementación propia. Sirve para comprobar en la Famicom que el audio del cartucho llega a la
// consola (mapper 250 de prueba, ver n8_top.v).
//
// Pitido de 1 kHz, medio segundo sí y medio no. Da un nivel para audio_dac.v (0-1023): NIVEL
// cuando suena (192 = 19 %, volumen moderado) y 0 en silencio.

module audio_tono #(
    parameter CLK_HZ  = 50_000_000,
    parameter TONO_HZ = 1000,
    parameter [9:0] NIVEL = 10'd192
) (
    input  wire       clk,
    input  wire       en,          // 0 = silencio
    output wire [9:0] level
);

    localparam MEDIO_PERIODO = CLK_HZ / (2 * TONO_HZ);   // 25 000 ciclos a 50 MHz
    localparam CAMBIOS       = TONO_HZ;                  // medios periodos del tono en medio segundo

    // Divisores encadenados (optimizado el 2026-11-05): el medio segundo se cuenta en medios periodos
    // del tono (1000) en lugar de en ciclos de clk. 15 + 10 bits en vez de 16 + 26.
    reg [15:0] div    = 16'd0;
    reg        onda   = 1'b0;
    reg [9:0]  cadena = 10'd0;
    reg        suena  = 1'b0;

    always @(posedge clk) begin
        if (div == MEDIO_PERIODO - 1) begin
            div  <= 16'd0;
            onda <= !onda;
            if (cadena == CAMBIOS - 1) begin cadena <= 10'd0; suena <= !suena; end
            else cadena <= cadena + 10'd1;
        end else div <= div + 16'd1;
    end

    assign level = (en && suena && onda) ? NIVEL : 10'd0;

endmodule
