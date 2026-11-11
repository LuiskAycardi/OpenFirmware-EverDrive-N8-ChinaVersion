`timescale 1ns/1ps
// a12_filter.v — Filtro de PPU A12 para los contadores de scanline (MMC3, TC0690, RAMBO-1).
// Implementación propia. Corre con clk (pin 17); A12 y M2 se sincronizan aquí.
//
// En los cartuchos originales hay un condensador en A12. En el N8 llegan picos cortos a la FPGA:
// sin filtro, un pico con A12 bajo durante el fondo contaba como una scanline más (la barra de
// estado de SMB3 saltaba en la consola).
//   - a12_sh[0] es la etapa de sincronización (puede ser metaestable). A12 filtrado (a12d) solo
//     cambia cuando a12_sh[3:1] tiene 3 muestras iguales: se descartan los pulsos de menos de
//     ~2 ciclos de clk (40 ns a 50 MHz). Un pulso real de A12 dura >= 373 ns.
//   - Una subida de A12 cuenta (a12_clk) solo si antes A12 estuvo bajo durante LOW_M2 bajadas
//     de M2: así se ignoran las subidas cortas de las búsquedas de sprites.
//   - La bajada de M2 se detecta como 1100 (2 muestras altas y 2 bajas): inmune a un pico.
// m2_fall sale también, para los mappers que cuentan ciclos de CPU en este dominio de reloj.

module a12_filter #(
    parameter LOW_M2 = 4,   // bajadas de M2 con A12 bajo necesarias (MMC3: 4 = >= 9 puntos de PPU)
    parameter W      = 3    // ancho del contador (debe poder contar hasta LOW_M2)
) (
    input  wire clk,
    input  wire m2,
    input  wire a12,
    output wire a12_clk,    // pulso de un clk: subida de A12 válida
    output wire m2_fall     // pulso de un clk por cada bajada de M2
);

    reg [3:0]   a12_sh  = 4'd0;
    reg         a12d    = 1'b0;
    reg [4:0]   m2_s    = 5'd0;
    reg [W-1:0] low_cnt = {W{1'b0}};

    wire a12_hi   = (a12_sh[3:1] == 3'b111);
    wire a12_lo   = (a12_sh[3:1] == 3'b000);
    wire a12_rise = a12_hi && !a12d;
    assign m2_fall = (m2_s[4:1] == 4'b1100);
    assign a12_clk = a12_rise && (low_cnt == LOW_M2);

    always @(posedge clk) begin
        a12_sh <= {a12_sh[2:0], a12};
        m2_s   <= {m2_s[3:0], m2};

        if (a12_hi)      a12d <= 1'b1;
        else if (a12_lo) a12d <= 1'b0;

        if (a12d || a12_hi)
            low_cnt <= {W{1'b0}};
        else if (m2_fall && low_cnt != LOW_M2)
            low_cnt <= low_cnt + 1'b1;
    end

endmodule
