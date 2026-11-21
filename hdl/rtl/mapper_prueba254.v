`timescale 1ns/1ps
// mapper_prueba254.v — Prueba F0 del soporte FDS (docs/fds-diseno.md), implementación propia. Solo en el 254.RBF
// hasta que llegue el mapper FDS de verdad.
//
// Comprueba en la consola dos cosas que el FDS necesita y ningún mapper había hecho:
//   1. escribir la SRAM PRG (la de la ROM del juego) en modo juego, por una ventana de 2 KB;
//   2. que la FPGA conduzca lecturas en $40xx.
//
// CPU: $8000-$FFFF  32 KB de PRG (banco 0-15 de 2 KB), como un NROM
//      $40F0 (escr.) banco de la ventana: A18-A11 de la SRAM PRG
//      $40F2 (lect.) el banco escrito en $40F0
//      resto de $4020-$7FFF (lect.), salvo $4400-$45FF (registros del CPLD) y la ventana: $A5 (constante)
//      (2026-11-20: en la NES, $40F1-$40F7 se leen como bus abierto aunque se active el /CE de una memoria; la
//       ventana $4800 sí llega. Esta versión sirve para ver qué rangos deja pasar el CPLD hacia la consola.)
//      $4800-$4FFF   ventana de lectura y escritura a la SRAM PRG: {banco, A10}
//      $6000-$7FFF   nada (no toca la PRG-RAM con pila: el OS guarda ahí sus marcas)
// PPU: CHR de 8 KB (ROM o RAM según cfg[7]) y mirroring de la cabecera, como el NROM.
// El top-level no aplica la máscara PRG_SIZE a este mapper (la ventana llega a los 512 KB) y deja escribir la
// SRAM PRG cuando prg_rom_en y prg_wr van juntos.

module mapper_prueba254 (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,
    input  wire        ppu_wr_n,
    input  wire [7:0]  cfg,
    input  wire        rst,
    input  wire        clk,
    input  wire [7:0]  map_id,
    input  wire [5:0]  chr_size,

    output wire [18:10] prg_a,
    output wire        prg_rom_en,
    output wire        prg_ram_en,
    output wire        prg_wr,
    output wire [18:10] chr_a,
    output wire        chr_en,
    output wire        chr_wr,
    output wire        ciram_en,
    output wire        ciram_a10,
    output wire        irq,
    output wire [7:0]  cpu_dout,
    output wire [7:0]  cpu_doe
);

    reg [7:0] banco;
    initial banco = 8'd0;

    wire reg_40f = romsel_n && (cpu_a[14:4] == 11'h40F);           // $40F0-$40FF
    wire ventana = romsel_n && (cpu_a[14:11] == 4'b1001);          // $4800-$4FFF

    always @(negedge m2) begin
        if (rst) banco <= 8'd0;
        else if (!cpu_rw && reg_40f && cpu_a[3:0] == 4'h0) banco <= cpu_d;
    end

    wire cpld = romsel_n && (cpu_a[14:9] == 6'b100010);           // $4400-$45FF
    wire apu  = romsel_n && (cpu_a[14:5] == 10'b1000000000);      // $4000-$401F (dentro de la consola)
    wire eco  = reg_40f && cpu_a[3:0] == 4'h2;
    wire zona = romsel_n && cpu_a[14] && !apu && !cpld && !ventana; // $4020-$7FFF menos lo de arriba

    assign prg_a      = ventana ? {banco, cpu_a[10]} : {4'd0, cpu_a[14:10]};
    assign prg_rom_en = !romsel_n || (ventana && m2);
    assign prg_ram_en = 1'b0;
    assign prg_wr     = !cpu_rw && ventana && m2;                   // con prg_rom_en: escribe la SRAM PRG

    assign cpu_doe  = (cpu_rw && zona) ? 8'hFF : 8'h00;
    assign cpu_dout = eco ? banco : 8'hA5;

    assign chr_a     = {6'd0, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = cfg[0] ? ppu_a[10] : ppu_a[11];
    assign irq       = 1'b0;

endmodule
