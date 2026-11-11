`timescale 1ns/1ps
// ram_dp128.v — RAM de 128 x 8 de doble puerto verdadero (dos puertos de lectura/escritura, un reloj).
// Escrita según la plantilla de Quartus para que se infiera en un bloque M4K del Cyclone II. Lectura
// simultánea a una escritura en el mismo puerto = dato nuevo (es lo que admite el M4K en este modo).
// La usa el Namco 163 (RAM interna de sonido).

module ram_dp128 (
    input  wire       clk,
    input  wire       we_a,
    input  wire [6:0] addr_a,
    input  wire [7:0] d_a,
    output reg  [7:0] q_a,
    input  wire       we_b,
    input  wire [6:0] addr_b,
    input  wire [7:0] d_b,
    output reg  [7:0] q_b
);

    reg [7:0] ram [0:127];

    integer i;
    initial begin
        for (i = 0; i < 128; i = i + 1) ram[i] = 8'd0;
        q_a = 8'd0; q_b = 8'd0;
    end

    always @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= d_a;
            q_a <= d_a;
        end else
            q_a <= ram[addr_a];
    end

    always @(posedge clk) begin
        if (we_b) begin
            ram[addr_b] <= d_b;
            q_b <= d_b;
        end else
            q_b <= ram[addr_b];
    end

endmodule
