`timescale 1ns/1ps
// mapper_fds.v — Famicom Disk System (mapper 254 del N8), implementación propia. Diseño: docs/fds-diseno.md.
//
// El disco no se sirve byte a byte por $4031 como en el FDS real: A0-A9 de la SRAM vienen del bus de la consola y
// la FPGA no puede elegir el byte. La BIOS del usuario, parcheada por nuestro OS, lee y escribe el disco por una
// ventana. Además, en el N8 de NES lo que conduce la FPGA no llega a la CPU en $4000-$41FF (medido en la prueba F0,
// 2026-11-20): los registros privados que hay que leer van en $42xx.
//
// SRAM PRG (512 KB): cara k del disco en k * 64 KB (k = 0-6, 65 500 bytes cada una), código del parche en 0x7D000
// (4 KB) y la BIOS en 0x7E000 (8 KB). Todo lo copia el OS antes de lanzar.
//
// CPU: $E000-$FFFF  BIOS (SRAM PRG 0x7E000, solo lectura)
//      $6000-$DFFF  RAM del FDS, 32 KB: PRG-RAM, bancos de 8 KB 0-3
//      $5000-$5FFF  código del parche (SRAM PRG 0x7D000, solo lectura)
//      $4800-$4BFF  ventana del disco (con $4210 D0 = 1): 1 KB de la cara en el banco de la cabeza, SRAM PRG
//                   {cara, cabeza[15:10], A9-A0}, lectura y escritura
//      registros del FDS (NESdev, «Family Computer Disk System»):
//        $4020/$4021 recarga del temporizador (byte bajo/alto)
//        $4022       D0 = repetir, D1 = activar (con $4023 D0): copia la recarga en el contador; con D1 = 0 la
//                    IRQ se reconoce
//        $4023       D0 = registros del disco y temporizador, D1 = sonido; D0 = 0 para el temporizador y reconoce
//        $4025       D3 = mirroring (1 horizontal, 0 vertical); el resto (motor, transferencia, IRQ del disco) no
//                    hace falta: la transferencia la hace la BIOS parcheada por la ventana
//        $4030 (lect.) D0 = IRQ del temporizador, D3 = mirroring (D2 y D5, bus abierto); leerlo reconoce la IRQ
//        $4032 (lect.) D0-D2 = 0: disco dentro, listo y sin protección (D3-D7, bus abierto)
//        $4033 (lect.) D7 = 1: batería bien
//        (en el N8 de NES estas lecturas no llegan: la CPU lee $40, que da lo mismo en $4032; leer $4030 reconoce
//         la IRQ igual, porque la FPGA ve la dirección)
//      registros privados (para la BIOS parcheada):
//        $4210       D0 = ventana del disco activa
//        $4212       D2-D0 = cara (A18-A16), legible
//        $4213/$4214 posición de la cabeza en la cara (byte bajo/alto), legible
//        $4215       (escr.) la cabeza avanza un byte
//        $4216       un byte de apoyo para el parche (que no puede usar la RAM del juego), legible
//        $4230 (lect.) como $4030 (también reconoce la IRQ)
// Temporizador: con la IRQ activa, en cada ciclo de CPU: si el contador vale 0, pide IRQ y recarga (y sin
// «repetir» se para); si no, resta 1. Mismo comportamiento que Mesen2 (leído para los detalles, nada copiado).
// PPU: CHR-RAM de 8 KB en $0000-$1FFF; CIRAM según $4025 D3.
// El sonido del FDS ($4040-$4097) es otra etapa (F6).

module mapper_fds (
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

    // ---------------------------------------------------------------- registros
    reg [15:0] recarga, cuenta;
    reg        t_rep, t_act, t_irq;
    reg        disco_en, sonido_en, mir_h;
    reg        ventana_en;
    reg [15:0] cabeza;
    reg [7:0]  apoyo;
    reg [2:0]  cara;
    initial begin
        recarga = 0; cuenta = 0; t_rep = 0; t_act = 0; t_irq = 0;
        disco_en = 1; sonido_en = 1; mir_h = 0; ventana_en = 0; cabeza = 0; apoyo = 0; cara = 0;
    end

    wire io     = romsel_n && (cpu_a[14:8] == 7'h40);              // $4000-$40FF
    wire priv   = romsel_n && (cpu_a[14:8] == 7'h42);              // $4200-$42FF
    wire es_lee = cpu_rw;
    wire lee_estado = es_lee && ((io && cpu_a[7:0] == 8'h30) || (priv && cpu_a[7:0] == 8'h30));

    reg [15:0] c_cuenta;
    reg        c_act, c_irq;
    always @(negedge m2) begin
        if (rst) begin
            recarga <= 0; cuenta <= 0; t_rep <= 0; t_act <= 0; t_irq <= 0;
            disco_en <= 1; sonido_en <= 1; mir_h <= 0; ventana_en <= 0; cabeza <= 0; apoyo <= 0; cara <= 0;
        end else begin
            // temporizador: un paso por ciclo de CPU
            c_cuenta = cuenta; c_act = t_act; c_irq = t_irq;
            if (c_act) begin
                if (c_cuenta == 16'd0) begin
                    c_irq = 1'b1;
                    c_cuenta = recarga;
                    if (!t_rep) c_act = 1'b0;
                end else
                    c_cuenta = c_cuenta - 16'd1;
            end
            // escrituras y lecturas con efecto
            if (!cpu_rw && io) begin
                case (cpu_a[7:0])
                    8'h20: recarga[7:0]  <= cpu_d;
                    8'h21: recarga[15:8] <= cpu_d;
                    8'h22: begin
                        t_rep <= cpu_d[0];
                        c_act = cpu_d[1] && disco_en;
                        if (c_act) c_cuenta = recarga;
                        else       c_irq = 1'b0;
                    end
                    8'h23: begin
                        disco_en  <= cpu_d[0];
                        sonido_en <= cpu_d[1];
                        if (!cpu_d[0]) begin c_act = 1'b0; c_irq = 1'b0; end
                    end
                    8'h25: if (disco_en) mir_h <= cpu_d[3];
                    default: ;
                endcase
            end
            if (!cpu_rw && priv) begin
                case (cpu_a[7:0])
                    8'h10: ventana_en <= cpu_d[0];
                    8'h12: cara  <= cpu_d[2:0];
                    8'h13: cabeza[7:0]  <= cpu_d;
                    8'h14: cabeza[15:8] <= cpu_d;
                    8'h15: cabeza <= cabeza + 16'd1;
                    8'h16: apoyo <= cpu_d;
                    default: ;
                endcase
            end
            if (lee_estado) c_irq = 1'b0;
            cuenta <= c_cuenta; t_act <= c_act; t_irq <= c_irq;
        end
    end

    // ---------------------------------------------------------------- memoria
    wire bios    = !romsel_n && (cpu_a[14:13] == 2'b11);           // $E000-$FFFF
    wire ram_hi  = !romsel_n && (cpu_a[14:13] != 2'b11);           // $8000-$DFFF
    wire ram_6   = romsel_n && (cpu_a[14:13] == 2'b11);            // $6000-$7FFF
    wire parche  = romsel_n && (cpu_a[14:12] == 3'b101);           // $5000-$5FFF
    wire ventana = romsel_n && (cpu_a[14:10] == 5'b10010) && ventana_en;  // $4800-$4BFF
    wire [1:0] banco_ram = ram_6 ? 2'd0 : (cpu_a[14:13] + 2'd1);   // $6000=0, $8000=1, $A000=2, $C000=3

    assign prg_a = bios    ? {6'b111111, cpu_a[12:10]} :            // 0x7E000
                   parche  ? {7'b1111101, cpu_a[11:10]} :           // 0x7D000
                   ventana ? {cara, cabeza[15:10]} :
                             {4'd0, banco_ram, cpu_a[12:10]};       // PRG-RAM 8 KB * banco_ram
    assign prg_rom_en = bios || ((parche || ventana) && m2);
    assign prg_ram_en = (ram_6 || ram_hi) && m2;
    assign prg_wr     = !cpu_rw && m2 && (ram_6 || ram_hi || ventana);   // con prg_rom_en (ventana): SRAM PRG

    // ---------------------------------------------------------------- lecturas que conduce la FPGA
    wire [7:0] estado = {2'b00, 1'b0, 1'b0, mir_h, 1'b0, 1'b0, t_irq};
    wire r30  = io && cpu_a[7:0] == 8'h30 && disco_en;
    wire r32  = io && cpu_a[7:0] == 8'h32 && disco_en;
    wire r33  = io && cpu_a[7:0] == 8'h33 && disco_en;
    wire p12  = priv && cpu_a[7:0] == 8'h12;
    wire p13  = priv && cpu_a[7:0] == 8'h13;
    wire p14  = priv && cpu_a[7:0] == 8'h14;
    wire p16  = priv && cpu_a[7:0] == 8'h16;
    wire p30  = priv && cpu_a[7:0] == 8'h30;
    assign cpu_doe  = !cpu_rw ? 8'h00 :
                      (r30 || p30) ? 8'hDB :          // D2 y D5: bus abierto
                      r32 ? 8'h07 :
                      r33 ? 8'h80 :
                      (p12 || p13 || p14 || p16) ? 8'hFF : 8'h00;
    assign cpu_dout = (r30 || p30) ? estado :
                      r32 ? 8'h00 :
                      r33 ? 8'h80 :
                      p12 ? {5'b00000, cara} :
                      p13 ? cabeza[7:0] :
                      p14 ? cabeza[15:8] :
                      p16 ? apoyo : 8'h00;

    // ---------------------------------------------------------------- PPU e IRQ
    assign chr_a     = {6'd0, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = mir_h ? ppu_a[11] : ppu_a[10];
    assign irq       = t_irq;

endmodule
