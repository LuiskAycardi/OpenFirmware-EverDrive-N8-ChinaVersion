`timescale 1ns/1ps
// mmc5_exram.v — ExRAM MMC5: 1024x8, dos puertos síncronos a 50 MHz.
// Plantilla de RAM doble puerto con dato nuevo al escribir en el mismo puerto.
// Inicialización determinista para el banco; reset del mapper no borra ExRAM.

module mmc5_exram (
    input  wire       clk,
    input  wire       we_a,
    input  wire [9:0] addr_a,
    input  wire [7:0] d_a,
    output reg  [7:0] q_a,
    input  wire       we_b,
    input  wire [9:0] addr_b,
    input  wire [7:0] d_b,
    output reg  [7:0] q_b
);

    reg [7:0] ram [0:1023];

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) ram[i] = 8'd0;
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
