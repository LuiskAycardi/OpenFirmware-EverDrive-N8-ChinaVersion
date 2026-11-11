// n8_sim_top.v — Envoltorio de n8_top para Verilator (banco de pruebas con Mesen2).
// No cambia nada del diseño: solo separa los buses bidireccionales en entrada/salida
// para poder conducirlos desde C++.
//   - cpu_d: la CPU conduce el bus en escrituras; en lecturas de registros (fase 3d) lo conduce la FPGA:
//     cpu_dout/cpu_doe dicen qué bits y con qué valor (el resto, bus abierto).
//   - /IRQ: se lee la petición interna del top (s_irq) en lugar del pin en colector abierto.
`timescale 1ns/1ps

module n8_sim_top (
    input  wire        clk,
    input  wire        bios_off,

    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_din,
    input  wire        cpu_romsel_n,
    input  wire        cpu_rw,
    input  wire        cpu_m2,
    output wire        cpu_irq,          // 1 = /IRQ activo

    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,
    input  wire        ppu_wr_n,
    output wire        ciram_ce_n,
    output wire        ciram_a10,

    output wire [8:0]  prg_map,
    output wire        prg_ce_n,
    output wire        prg_we_n,
    output wire [8:0]  chr_map,
    output wire        chr_ce_n,
    output wire        chr_we_n,
    output wire        ram_ce,
    output wire        ram_we_n,

    output wire        os_mode,          // depuración: 1 = menú
    output wire [9:0]  snd_level,        // nivel de sonido de expansión que entra a audio_dac
    output wire        snd_on,           // 1 = el pin 97 se conduce
    output wire [7:0]  cpu_dout,         // dato que conduce la FPGA en una lectura de registro
    output wire [7:0]  cpu_doe,
    input wire [7:0] ppu_din,
    output wire [7:0] ppu_dout, ppu_doe
);

    wire [7:0] cpu_d;
    assign cpu_d = cpu_din;
    wire [7:0] ppu_d;
    assign ppu_d = ppu_rd_n ? ppu_din : 8'hzz;
    wire       irq_n, exp, ppu_dir, ppu_ex, prg_oe_n, chr_oe_n, ram_oe_n, mode0, mode1;

    n8_top dut (
        .cpu_d(cpu_d), .cpu_a(cpu_a), .cpu_romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw),
        .cpu_m2(cpu_m2), .cpu_m2_gclk(cpu_m2), .cpu_irq_n(irq_n), .cpu_exp(exp),
        .ppu_d(ppu_d), .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n),
        .ciram_ce_n(ciram_ce_n), .ciram_a10(ciram_a10), .ppu_dir(ppu_dir), .ppu_ex(ppu_ex),
        .prg_map(prg_map), .prg_ce_n(prg_ce_n), .prg_oe_n(prg_oe_n), .prg_we_n(prg_we_n),
        .chr_map(chr_map), .chr_ce_n(chr_ce_n), .chr_oe_n(chr_oe_n), .chr_we_n(chr_we_n),
        .ram_ce(ram_ce), .ram_oe_n(ram_oe_n), .ram_we_n(ram_we_n),
        .clk(clk), .cpld_bios_off(bios_off), .cpld_mode0(mode0), .cpld_mode1(mode1)
    );

    assign ppu_dout=dut.g_ppudo;
    assign ppu_doe=dut.ppu_drive ? dut.g_ppudoe : 0;
    assign cpu_irq = dut.s_irq;
    assign os_mode = dut.os_mode;
    assign snd_level = dut.snd_level;
    assign snd_on    = dut.snd_on;
    assign cpu_dout  = dut.g_dout;
    assign cpu_doe   = dut.cpu_drive ? dut.g_doe : 8'h00;

endmodule
