`timescale 1ns/1ps
// mapper_mmc3b.v — Segunda instancia del MMC3 para las variantes de la fase 4 (GRUPO 1, RBF 102).
// Solo cambia el parámetro: así el RBF 100 no carga con estas variantes ni este RBF con las antiguas.
module mapper_mmc3b (
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
    output wire        chr_raw,
    output wire [7:0]  cpu_dout,
    output wire [7:0]  cpu_doe
);
    mapper_mmc3 #(.GRUPO(1)) u (
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(romsel_n), .cpu_rw(cpu_rw), .m2(m2), .ppu_a(ppu_a),
        .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(rst), .clk(clk), .map_id(map_id),
        .chr_size(chr_size), .prg_a(prg_a), .prg_rom_en(prg_rom_en), .prg_ram_en(prg_ram_en), .prg_wr(prg_wr),
        .chr_a(chr_a), .chr_en(chr_en), .chr_wr(chr_wr), .ciram_en(ciram_en), .ciram_a10(ciram_a10), .irq(irq),
        .chr_raw(chr_raw), .cpu_dout(cpu_dout), .cpu_doe(cpu_doe));
endmodule
