`timescale 1ns/1ps
// n8_top.v — Top-level para el EverDrive N8 (original / clon). Implementación propia.
// Pines y polaridades: docs/hardware-fpga.md.
//
// Selecciona entre el mapa del OS (mapper_id = 0xFF) y el del juego, aplica las
// máscaras de tamaño y genera las señales de las memorias.
// El bus de datos de la CPU solo se conduce en lecturas de registros de mapper (fase 3d, ver abajo).
// MMC5 conduce la PPU para ExRAM/fill/atributos; el resto queda en Z. Los pines ppu_d llevan
// pull-up débil (QSF): cuando nadie conduce el bus (CHR desactivada en los mappers 93 y 185) la
// PPU lee $FF.

`ifndef N8_RBF_100
`ifndef N8_RBF_101
`ifndef N8_RBF_102
`ifndef N8_RBF_103
`ifndef N8_RBF_104
`ifndef N8_RBF_105
`ifndef N8_RBF_106
`define N8_RBF_100
`define N8_RBF_101
`define N8_RBF_102
`define N8_RBF_103
`define N8_RBF_104
`define N8_RBF_105
`define N8_RBF_106
`endif
`endif
`endif
`endif
`endif
`endif
`endif

module n8_top (
    // bus CPU
    inout  wire [7:0]  cpu_d,
    input  wire [14:0] cpu_a,
    input  wire        cpu_romsel_n,
    input  wire        cpu_rw,
    input  wire        cpu_m2,        // pin 27 (no usado en la lógica)
    input  wire        cpu_m2_gclk,   // pin 21: M2 en entrada de reloj global
    output wire        cpu_irq_n,
    output wire        cpu_exp,

    // bus PPU
    inout  wire [7:0]  ppu_d,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,
    input  wire        ppu_wr_n,
    output wire        ciram_ce_n,
    output wire        ciram_a10,
    output wire        ppu_dir,
    output wire        ppu_ex,

    // SRAM PRG (juego)
    output wire [8:0]  prg_map,       // A10..A18
    output wire        prg_ce_n,
    output wire        prg_oe_n,
    output wire        prg_we_n,

    // SRAM CHR
    output wire [8:0]  chr_map,       // A10..A18
    output wire        chr_ce_n,
    output wire        chr_oe_n,
    output wire        chr_we_n,

    // PRG-RAM (batería)
    output wire        ram_ce,        // activo-alto
    output wire        ram_oe_n,
    output wire        ram_we_n,

    // sistema / CPLD
    input  wire        clk,
    input  wire        cpld_bios_off,
    output wire        cpld_mode0,
    output wire        cpld_mode1
);

    wire m2 = cpu_m2_gclk;

    // ------------------------------------------------------------ interfaz OS
    wire [7:0]  mapper_id, cfg;
    wire [4:0]  prg_size;
    wire [5:0]  chr_size;
    wire        os_mode, m2_ok, mem_off, map_reset;

    wire [18:10] os_prg_a, os_chr_a;
    wire        os_prg_rom_en, os_prg_ram_en, os_prg_wr;
    wire        os_chr_en, os_chr_wr, os_ciram_en, os_ciram_a10;

    n8_os_iface os (
        .clk(clk), .m2(m2), .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n),
        .cpu_rw(cpu_rw), .bios_off(cpld_bios_off), .ppu_a(ppu_a), .ppu_wr_n(ppu_wr_n),
        .mapper_id(mapper_id), .os_mode(os_mode), .cfg(cfg),
        .prg_size(prg_size), .chr_size(chr_size),
        .m2_ok(m2_ok), .mem_off(mem_off), .map_reset(map_reset),
        .prg_a(os_prg_a), .prg_rom_en(os_prg_rom_en), .prg_ram_en(os_prg_ram_en),
        .prg_wr(os_prg_wr), .chr_a(os_chr_a), .chr_en(os_chr_en), .chr_wr(os_chr_wr),
        .ciram_en(os_ciram_en), .ciram_a10(os_ciram_a10)
    );

    // ------------------------------------------------------------ mappers del juego
    // Cada mapper entrega un bus de 26 bits:
    //   {prg_a[18:10], chr_a[18:10], prg_rom_en, prg_ram_en, prg_wr,
    //    chr_en, chr_wr, ciram_en, ciram_a10, irq}
    // Los registros de los mappers se mantienen en reset mientras el OS está activo.
`define N8_MAPPER(MOD, INST, BUS) \
    wire [26:0] BUS; \
    assign BUS[26] = 1'b0; \
    MOD INST ( \
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw), .m2(m2), \
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(os_mode), .clk(clk), .map_id(mapper_id), \
        .prg_a(BUS[25:17]), .chr_a(BUS[16:8]), .prg_rom_en(BUS[7]), .prg_ram_en(BUS[6]), \
        .prg_wr(BUS[5]), .chr_en(BUS[4]), .chr_wr(BUS[3]), .ciram_en(BUS[2]), \
        .ciram_a10(BUS[1]), .irq(BUS[0]) );

    // Igual, para módulos con sonido de expansión: salida snd (nivel 0-1023 para audio_dac.v).
`define N8_MAPPER_S(MOD, INST, BUS, SND) \
    wire [26:0] BUS; \
    wire [9:0]  SND; \
    assign BUS[26] = 1'b0; \
    MOD INST ( \
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw), .m2(m2), \
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(os_mode), .clk(clk), .map_id(mapper_id), \
        .prg_a(BUS[25:17]), .chr_a(BUS[16:8]), .prg_rom_en(BUS[7]), .prg_ram_en(BUS[6]), \
        .prg_wr(BUS[5]), .chr_en(BUS[4]), .chr_wr(BUS[3]), .ciram_en(BUS[2]), \
        .ciram_a10(BUS[1]), .irq(BUS[0]), .snd(SND) );

    // Igual, para módulos que responden lecturas de la CPU (fase 3d): salidas cpu_dout y cpu_doe (bits que
    // conduce el chip real; el resto queda en bus abierto) y entrada chr_size (máscara CHR del OS).
`define N8_MAPPER_D(MOD, INST, BUS, DO, DOE) \
    wire [26:0] BUS; \
    wire [7:0]  DO, DOE; \
    assign BUS[26] = 1'b0; \
    MOD INST ( \
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw), .m2(m2), \
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(os_mode), .clk(clk), .map_id(mapper_id), \
        .chr_size(chr_size), \
        .prg_a(BUS[25:17]), .chr_a(BUS[16:8]), .prg_rom_en(BUS[7]), .prg_ram_en(BUS[6]), \
        .prg_wr(BUS[5]), .chr_en(BUS[4]), .chr_wr(BUS[3]), .ciram_en(BUS[2]), \
        .ciram_a10(BUS[1]), .irq(BUS[0]), .cpu_dout(DO), .cpu_doe(DOE) );

    // Lectura + sonido (Namco 163).
`define N8_MAPPER_DS(MOD, INST, BUS, DO, DOE, SND) \
    wire [26:0] BUS; \
    wire [7:0]  DO, DOE; \
    wire [9:0]  SND; \
    assign BUS[26] = 1'b0; \
    MOD INST ( \
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw), .m2(m2), \
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(os_mode), .clk(clk), .map_id(mapper_id), \
        .chr_size(chr_size), \
        .prg_a(BUS[25:17]), .chr_a(BUS[16:8]), .prg_rom_en(BUS[7]), .prg_ram_en(BUS[6]), \
        .prg_wr(BUS[5]), .chr_en(BUS[4]), .chr_wr(BUS[3]), .ciram_en(BUS[2]), \
        .ciram_a10(BUS[1]), .irq(BUS[0]), .cpu_dout(DO), .cpu_doe(DOE), .snd(SND) );

    // Lectura + chr_raw (MMC3: CHR-RAM del TQROM y protección del 115).
`define N8_MAPPER_XD(MOD, INST, BUS, DO, DOE) \
    wire [26:0] BUS; \
    wire [7:0]  DO, DOE; \
    MOD INST ( \
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw), .m2(m2), \
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(os_mode), .clk(clk), .map_id(mapper_id), \
        .chr_size(chr_size), \
        .prg_a(BUS[25:17]), .chr_a(BUS[16:8]), .prg_rom_en(BUS[7]), .prg_ram_en(BUS[6]), \
        .prg_wr(BUS[5]), .chr_en(BUS[4]), .chr_wr(BUS[3]), .ciram_en(BUS[2]), \
        .ciram_a10(BUS[1]), .irq(BUS[0]), .chr_raw(BUS[26]), .cpu_dout(DO), .cpu_doe(DOE) );

    // Igual, para módulos con la salida chr_raw (dirección CHR sin la máscara del OS).
`define N8_MAPPER_X(MOD, INST, BUS) \
    wire [26:0] BUS; \
    MOD INST ( \
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw), .m2(m2), \
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(os_mode), .clk(clk), .map_id(mapper_id), \
        .prg_a(BUS[25:17]), .chr_a(BUS[16:8]), .prg_rom_en(BUS[7]), .prg_ram_en(BUS[6]), \
        .prg_wr(BUS[5]), .chr_en(BUS[4]), .chr_wr(BUS[3]), .ciram_en(BUS[2]), \
        .ciram_a10(BUS[1]), .irq(BUS[0]), .chr_raw(BUS[26]) );

    // Lectura + chr_raw + bus de datos de la PPU (CHR-RAM interna del 253).
`define N8_MAPPER_XDP(MOD, INST, BUS, DO, DOE, PDO, PDOE) \
    wire [26:0] BUS; \
    wire [7:0]  DO, DOE, PDO, PDOE; \
    MOD INST ( \
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw), .m2(m2), \
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(os_mode), .clk(clk), .map_id(mapper_id), \
        .chr_size(chr_size), \
        .prg_a(BUS[25:17]), .chr_a(BUS[16:8]), .prg_rom_en(BUS[7]), .prg_ram_en(BUS[6]), \
        .prg_wr(BUS[5]), .chr_en(BUS[4]), .chr_wr(BUS[3]), .ciram_en(BUS[2]), \
        .ciram_a10(BUS[1]), .irq(BUS[0]), .chr_raw(BUS[26]), .cpu_dout(DO), .cpu_doe(DOE), \
        .ppu_din(ppu_d), .ppu_dout(PDO), .ppu_doe(PDOE) );

    // MMC5 (RBF 103): lectura de registros (DO/DOE) + sonido (SND) + conducción futura del bus PPU (PDO/PDOE).
`define N8_MAPPER_M5(MOD, INST, BUS, DO, DOE, SND, PDO, PDOE) \
    wire [7:0] PDO, PDOE; \
    wire [26:0] BUS; \
    wire [7:0]  DO, DOE; \
    wire [9:0]  SND; \
    MOD INST ( \
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(cpu_romsel_n), .cpu_rw(cpu_rw), .m2(m2), \
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(os_mode), .clk(clk), \
        .map_id(mapper_id), .chr_size(chr_size), \
        .prg_a(BUS[25:17]), .chr_a(BUS[16:8]), .prg_rom_en(BUS[7]), .prg_ram_en(BUS[6]), \
        .prg_wr(BUS[5]), .chr_en(BUS[4]), .chr_wr(BUS[3]), .ciram_en(BUS[2]), \
        .ciram_a10(BUS[1]), .irq(BUS[0]), .chr_raw(BUS[26]), \
        .cpu_dout(DO), .cpu_doe(DOE), .snd(SND), .ppu_din(ppu_d), .ppu_dout(PDO), .ppu_doe(PDOE) );

    // Reparto en dos RBF (el EP2C5 no admite todos con holgura). La macro la pone el proyecto de
    // Quartus de cada RBF; sin ninguna (simulación y banco de pruebas) se incluyen los dos.
    //   N8_RBF_100: fases 1-3b y las variantes de esas mismas instancias (fase 3c)
    //   N8_RBF_101: chips nuevos de la fase 3c y lecturas sencillas de la 3d
    //   N8_RBF_102: Namco 163 (con sonido) y, desde la fase 4, mapper_latch, mapper_mmc3b y mapper_irqcpu
    // MAPROUT.BIN dirige cada número de mapper a su RBF.
    `N8_MAPPER(mapper_nrom,  m000, bus_000)
`ifdef N8_RBF_100
    `N8_MAPPER(mapper_mmc1,  m001, bus_001)     // también 155
    `N8_MAPPER(mapper_uxrom, m002, bus_002)     // también 180
    `N8_MAPPER(mapper_cnrom, m003, bus_003)     // también 185
    `N8_MAPPER_XD(mapper_mmc3, m004, bus_004, do_004, doe_004)   // también 37, 47, 115, 118, 119, 189
    `N8_MAPPER(mapper_axrom, m007, bus_007)
    // fase 3a: discretos y similares
    `N8_MAPPER(mapper_colordreams, m011, bus_011)
    `N8_MAPPER(mapper_taito33,     m033, bus_033)   // también 48
    `N8_MAPPER(mapper_bnrom,       m034, bus_034)
    `N8_MAPPER(mapper_gxrom,       m066, bus_066)
    `N8_MAPPER(mapper_bandai70,    m070, bus_070)
    `N8_MAPPER(mapper_camerica,    m071, bus_071)
    `N8_MAPPER(mapper_nina03,      m079, bus_079)   // también 146
    `N8_MAPPER(mapper_jaleco86,    m086, bus_086)
    `N8_MAPPER(mapper_jaleco87,    m087, bus_087)
    `N8_MAPPER(mapper_hes,         m113, bus_113)
    `N8_MAPPER(mapper_jaleco140,   m140, bus_140)
    `N8_MAPPER(mapper_sachen148,   m148, bus_148)
    `N8_MAPPER(mapper_bandai152,   m152, bus_152)
    `N8_MAPPER(mapper_sunsoft1,    m184, bus_184)
    `N8_MAPPER(mapper_namco108,    m206, bus_206)   // también 76, 88, 95, 154
    `N8_MAPPER(mapper_quattro,     m232, bus_232)
    // fase 3b: complejos (solo escrituras). Una instancia por familia: la variante sale de map_id.
    `N8_MAPPER(mapper_mmc2,        m009, bus_009)   // 9 y 10
    `N8_MAPPER_X(mapper_vrc24,     m021, bus_021)   // 21, 22, 23, 25; 27, 183, 252
    `N8_MAPPER_D(mapper_bandaifcg, m016, bus_016, do_016, doe_016)   // 16, 153, 157 y 159 (EEPROM serie)
    `N8_MAPPER(mapper_ss88006,     m018, bus_018)
    `N8_MAPPER_S(mapper_fme7,      m069, bus_069, snd_069)   // con el sonido Sunsoft 5B
    `N8_MAPPER(mapper_namco210,    m210, bus_210)
`endif
`ifdef N8_RBF_101
    // fase 3c: chips nuevos
    `N8_MAPPER(mapper_rambo1,      m064, bus_064)   // 64 y 158
    `N8_MAPPER(mapper_taitox1005,  m080, bus_080)   // 80 y 207
    `N8_MAPPER(mapper_taitox1017,  m082, bus_082)
    `N8_MAPPER(mapper_sunsoft4,    m068, bus_068)
    `N8_MAPPER(mapper_iremg101,    m032, bus_032)
    `N8_MAPPER(mapper_ntdec112,    m112, bus_112)
    `N8_MAPPER(mapper_vrc1,        m075, bus_075)
    `N8_MAPPER(mapper_sachen8259,  m141, bus_141)   // 137, 138, 139, 141
    `N8_MAPPER(mapper_daou156,     m156, bus_156)
    `N8_MAPPER_S(mapper_vrc6,      m024, bus_024, snd_024)   // 24 y 26, con su sonido
    `N8_MAPPER(mapper_iremh3001,   m065, bus_065)
    `N8_MAPPER(mapper_sunsoft2,    m089, bus_089)   // 89 y 93
    `N8_MAPPER_D(mapper_sachen243, m243, bus_243, do_243, doe_243)   // 243 y 150
    `N8_MAPPER_D(mapper_txc,       m132, bus_132, do_132, doe_132)   // 36, 132, 136, 143, 147, 172, 173
    `N8_MAPPER(mapper_jaleco72,    m072, bus_072)   // 72 y 92
    `N8_MAPPER(mapper_sachen133,   m133, bus_133)
    `N8_MAPPER(mapper_sunsoft3,    m067, bus_067)
    `N8_MAPPER(mapper_jaleco78,    m078, bus_078)
    `N8_MAPPER(mapper_ntdec193,    m193, bus_193)
    `N8_MAPPER(mapper_multi_b,     m041, bus_041)   // 41, 46, 228, 241
`endif
`ifdef N8_RBF_102
    `N8_MAPPER_DS(mapper_n163, m019, bus_019, do_019, doe_019, snd_019)
    // fase 4, lote 1: mappers de un solo registro (mapper_latch.v)
    `N8_MAPPER_XD(mapper_latch, m400, bus_400, do_400, doe_400)
    // fase 4, lote 2: variantes del MMC3 (segunda instancia, GRUPO 1)
    `N8_MAPPER_XD(mapper_mmc3b, m404, bus_404, do_404, doe_404)
    // fase 4, lote 4: IRQ por ciclos de CPU (mapper_irqcpu.v)
    `N8_MAPPER(mapper_irqcpu, m408, bus_408)
`endif
`ifdef N8_RBF_103
    // MMC5 (RBF propio). PPU-data (fill/ExRAM) y split/audio: iteraciones posteriores.
    `N8_MAPPER_M5(mapper_mmc5, m005, bus_005, do_005, doe_005, snd_005, ppudo_005, ppudoe_005)
`endif

    // Un número de mapper no implementado (o de otro RBF) se comporta como NROM.
`ifdef N8_RBF_104
    `N8_MAPPER(mapper_kaiser56, m456, bus_456)
    `N8_MAPPER(mapper_scan4, m491, bus_491)
    `N8_MAPPER(mapper_nwc105, m405, bus_405)
    `N8_MAPPER_XD(mapper_misc4, m499, bus_499, do_499, doe_499)
`endif
`ifdef N8_RBF_105
    `N8_MAPPER_XD(mapper_jy, m590, bus_590, do_590, doe_590)
    `N8_MAPPER_XD(mapper_mmc3c, m504, bus_504, do_504, doe_504)
    `N8_MAPPER(mapper35, m535, bus_535)
    `N8_MAPPER_X(mapper_fk23c, m176, bus_176)
    `N8_MAPPER_XDP(mapper_pirate, m559, bus_559, do_559, doe_559, ppudo_559, ppudoe_559)   // 59, 83, 253
    `N8_MAPPER(mapper116, m116, bus_116)
`endif
`ifdef N8_RBF_106
    `N8_MAPPER_S(mapper_vrc7,      m085, bus_085, snd_085)   // VRC7 con su sonido FM (vrc7_fm.v)
`endif
    reg [26:0] g;
    always @(*) begin
        case (mapper_id)
`ifdef N8_RBF_100
            8'd1, 8'd155:                     g = bus_001;
            8'd2, 8'd180:                     g = bus_002;
            8'd3, 8'd185:                     g = bus_003;
            8'd4, 8'd37, 8'd47, 8'd115,
            8'd118, 8'd119, 8'd189, 8'd220:   g = bus_004; // 220: legacy N8 debug alias, not a new chip
            8'd7:                             g = bus_007;
            8'd9, 8'd10:                      g = bus_009;
            8'd11, 8'd144:                    g = bus_011;
            8'd16, 8'd153, 8'd157, 8'd159:   g = bus_016;
            8'd18:                            g = bus_018;
            8'd21, 8'd22, 8'd23, 8'd25,
            8'd27, 8'd183, 8'd252:            g = bus_021;
            8'd33, 8'd48:                     g = bus_033;
            8'd34:                            g = bus_034;
            8'd66:                            g = bus_066;
            8'd69:                            g = bus_069;
            8'd70:                            g = bus_070;
            8'd71:                            g = bus_071;
            8'd79, 8'd146:                    g = bus_079;
            8'd86:                            g = bus_086;
            8'd87:                            g = bus_087;
            8'd113:                           g = bus_113;
            8'd140:                           g = bus_140;
            8'd148:                           g = bus_148;
            8'd152:                           g = bus_152;
            8'd184:                           g = bus_184;
            8'd206, 8'd76, 8'd88, 8'd95,
            8'd154:                           g = bus_206;
            8'd210:                           g = bus_210;
            8'd232:                           g = bus_232;
`endif
`ifdef N8_RBF_101
            8'd24, 8'd26:                     g = bus_024;
            8'd32:                            g = bus_032;
            8'd41, 8'd46, 8'd228, 8'd241:     g = bus_041;
            8'd64, 8'd158:                    g = bus_064;
            8'd65:                            g = bus_065;
            8'd67:                            g = bus_067;
            8'd68:                            g = bus_068;
            8'd72, 8'd92:                     g = bus_072;
            8'd75, 8'd151:                    g = bus_075;   // 151 = VRC1 (versión VS)
            8'd78:                            g = bus_078;
            8'd80, 8'd207:                    g = bus_080;
            8'd82:                            g = bus_082;
            8'd89, 8'd93:                     g = bus_089;
            8'd112:                           g = bus_112;
            8'd133:                           g = bus_133;
            8'd137, 8'd138, 8'd139, 8'd141:   g = bus_141;
            8'd156:                           g = bus_156;
            8'd193:                           g = bus_193;
            8'd243, 8'd150:                   g = bus_243;
            8'd36, 8'd132, 8'd136, 8'd143,
            8'd147, 8'd172, 8'd173:           g = bus_132;
`endif
`ifdef N8_RBF_102
            8'd19:                            g = bus_019;
            8'd13, 8'd15, 8'd38, 8'd57, 8'd58, 8'd61, 8'd94, 8'd97,
            8'd101, 8'd107, 8'd145, 8'd149, 8'd177, 8'd200, 8'd201,
            8'd202, 8'd203, 8'd212, 8'd213, 8'd214, 8'd216, 8'd227,
            8'd229, 8'd231, 8'd240, 8'd242, 8'd244, 8'd246,
            8'd28, 8'd30, 8'd31, 8'd51, 8'd60, 8'd77, 8'd96, 8'd103,
            8'd108, 8'd164, 8'd168, 8'd171, 8'd175, 8'd178, 8'd188,
            8'd190, 8'd221:                   g = bus_400;
            8'd12, 8'd44, 8'd45, 8'd49, 8'd52, 8'd74, 8'd134, 8'd182,
            8'd187, 8'd191, 8'd196, 8'd197, 8'd198, 8'd199, 8'd205,
            8'd238, 8'd245, 8'd249, 8'd250:   g = bus_404;
            8'd40, 8'd42, 8'd50, 8'd73, 8'd106,
            8'd142:                           g = bus_408;
`endif
`ifdef N8_RBF_103
            8'd5:                             g = bus_005;
`endif
`ifdef N8_RBF_104
            8'd56:                            g = bus_456;
            8'd91,8'd117,8'd222:               g = bus_491;
            8'd105:                           g = bus_405;
            8'd99,8'd111,8'd186,8'd234:        g = bus_499;
`endif
`ifdef N8_RBF_105
            8'd90,8'd209,8'd211:               g = bus_590;
            8'd35:                             g = bus_535;
            8'd176:                            g = bus_176;
            8'd59,8'd83,8'd253:                g = bus_559;
            8'd116:                            g = bus_116;
            8'd114,8'd121,8'd165,8'd192,8'd194,
            8'd195,8'd215,8'd219,8'd248:       g = bus_504;
`endif
`ifdef N8_RBF_106
            8'd85:                             g = bus_085;
`endif
            default:                          g = bus_000;
        endcase
    end

    // Lecturas de registros (fase 3d): dato y bits que conduce cada mapper. 0 = no conduce.
    reg [7:0] g_dout, g_doe;
    always @(*) begin
        g_dout = 8'd0; g_doe = 8'd0;
        case (mapper_id)
`ifdef N8_RBF_100
            8'd115:                                 begin g_dout = do_004; g_doe = doe_004; end
            8'd16, 8'd157, 8'd159:                  begin g_dout = do_016; g_doe = doe_016; end
`endif
`ifdef N8_RBF_101
            8'd243, 8'd150:                         begin g_dout = do_243; g_doe = doe_243; end
            8'd36, 8'd132, 8'd136, 8'd143,
            8'd147, 8'd172, 8'd173:                 begin g_dout = do_132; g_doe = doe_132; end
`endif
`ifdef N8_RBF_102
            8'd19:                                  begin g_dout = do_019; g_doe = doe_019; end
            8'd212, 8'd188:                         begin g_dout = do_400; g_doe = doe_400; end
            8'd187, 8'd238:                         begin g_dout = do_404; g_doe = doe_404; end
`endif
`ifdef N8_RBF_103
            8'd5:                                   begin g_dout = do_005; g_doe = doe_005; end
`endif
`ifdef N8_RBF_104
            8'd186: begin g_dout=do_499; g_doe=doe_499; end
`endif
`ifdef N8_RBF_105
            8'd90,8'd209,8'd211: begin g_dout=do_590; g_doe=doe_590; end
            8'd121,8'd165,8'd219,8'd248: begin g_dout=do_504; g_doe=doe_504; end
            8'd59,8'd83: begin g_dout=do_559; g_doe=doe_559; end
`endif
            default: ;
        endcase
    end

    wire [18:10] g_prg_a = g[25:17];
    wire [18:10] g_chr_a = g[16:8];
    wire g_prg_rom_en = g[7], g_prg_ram_en = g[6], g_prg_wr = g[5];
    wire g_chr_en = g[4], g_chr_wr = g[3], g_ciram_en = g[2], g_ciram_a10 = g[1], g_irq = g[0];
    wire g_chr_raw = g[26];

    // ------------------------------------------------------------ 4 pantallas
    // MAP_CFG bit 3 = 4 pantallas (mismo bit que el byte 6 de la cabecera iNES; el OS v13
    // guarda cabecera[6] & $1B, que lo conserva). Vale para cualquier mapper: $2000-$3EFF
    // deja de ir a la CIRAM de la consola (2 KB) y va a 4 KB de la SRAM CHR, como la RAM extra
    // de los cartuchos TVROM/TR1ROM (Rad Racer II). $3000-$3EFF es espejo de $2000-$2EFF.
    // Zona: CHR 0x7E000-0x7EFFF, fuera de la CHR de cualquier juego de <= 504 KB y sin tocar
    // 0x7F000-0x7FFFF, que el menú del OS usa (registro 130 = 0 -> ventana $0000 = banco 127).
    // Nuestro OS futuro debe poner este bit cuando la cabecera lo pida.
    localparam [18:12] NT_RAM_BANK = 7'b1111110;
    // Excepción: 78 (Holy Diver), 137 (The Great Wall) y 154 (Devil Man) llevan el bit 3 como marca
    // de "mirroring controlado por el mapper" (convención iNES de NESdev), no como RAM extra.
    // 30 (UNROM 512) con los bits 3 y 0 = 1 y 0: pantalla única elegida por el mapper, no 4 pantallas.
    wire mir_flag = (mapper_id == 8'd78) || (mapper_id == 8'd137) || (mapper_id == 8'd154) ||
                    (mapper_id == 8'd30 && !cfg[0]);
    wire nt_ram = !os_mode && cfg[3] && !mir_flag && ppu_a[13];

    // ------------------------------------------------------------ selección
    // PRG A12-A10 van siempre directos de la CPU en el juego: ningún mapper tiene bancos de PRG de menos de
    // 8 KB (comprobado en todos los módulos el 2026-11-05). Así el selector no los multiplexa (en el OS no:
    // su ventana de $4800 es de 2 KB).
    // Excepciones: 31 (bancos de 4 KB) y 103 (página de RAM en $B800-$D7FF, desplazada) dan A12-A10 ellos mismos.
    wire prg_low_map = (mapper_id == 8'd31) || (mapper_id == 8'd103);
    wire [18:10] s_prg_a  = os_mode ? os_prg_a      : prg_low_map ? g_prg_a : {g_prg_a[18:13], cpu_a[12:10]};
    wire [18:10] s_chr_a  = os_mode ? os_chr_a      :
                            nt_ram  ? {NT_RAM_BANK, ppu_a[11:10]} : g_chr_a;
    // 188 (Karaoke Studio): con la ROM del casete elegida ($8000-$BFFF en los bancos 8-15) y una PRG de menos de
    // 256 KB no hay casete: bus abierto (si no, la ROM interna repetida parece un casete y el juego lista canciones
    // de más).
    wire no_cas188 = (mapper_id == 8'd188) && !prg_size[3] && !cpu_romsel_n && !cpu_a[14] && g_prg_a[17];
    wire s_prg_rom_en     = os_mode ? os_prg_rom_en : (g_prg_rom_en && !no_cas188);
    wire s_prg_ram_en     = os_mode ? os_prg_ram_en : g_prg_ram_en;
    wire s_prg_wr         = os_mode ? os_prg_wr     : g_prg_wr;
    wire s_chr_en         = os_mode ? os_chr_en     : nt_ram ? 1'b1       : g_chr_en;
    wire s_chr_wr         = os_mode ? os_chr_wr     : nt_ram ? !ppu_wr_n  : g_chr_wr;
    wire s_ciram_en       = os_mode ? os_ciram_en   : nt_ram ? 1'b0       : g_ciram_en;
    wire s_ciram_a10      = os_mode ? os_ciram_a10  : g_ciram_a10;
    wire s_irq            = os_mode ? 1'b0          : g_irq;

    wire [4:0] prg_mask = os_mode ? 5'b11111  : prg_size;
    wire [5:0] chr_mask = (os_mode || nt_ram || g_chr_raw) ? 6'b111111 : chr_size;   // RAM de 4 pantallas y CHR-RAM extra: sin máscara

    // ------------------------------------------------------------ pines
    assign prg_map = {s_prg_a[18:14] & prg_mask, s_prg_a[13:10]};
    assign chr_map = {s_chr_a[18:13] & chr_mask, s_chr_a[12:10]};

    wire cpu_mem_on = !mem_off && m2_ok;

    assign prg_ce_n = !(cpu_mem_on && s_prg_rom_en);
    assign ram_ce   =   cpu_mem_on && s_prg_ram_en && !s_prg_rom_en;
    // ------------------------------------------------------------ la FPGA conduce el bus de datos de la CPU
    // Solo en lecturas, con M2 alto, fuera del OS, y con la habilitación estable dos ciclos de clk (40 ns).
    // /ROMSEL baja 15-30 ns después de subir M2: en ese hueco una lectura de ROM en $C101 o $D000 se parece
    // a una de $4101 o $5000; con 40 ns de espera ese instante nunca conduce. Quedan > 200 ns de M2 alto
    // para el dato. Se suelta en cuanto baja M2. Mientras tanto
    // las SRAM no sacan datos (prg_oe/ram_oe apagados). Solo los bits que conduce el chip real; los demás
    // quedan en Z y la CPU ve el bus abierto. Mismo esquema que el MMC5 del kit de Krikzz (hecho leído).
    // En el N8 de Famicom no hay transceptores: la FPGA llega al bus por 100 ohmios.
    wire cpu_oe_now = !os_mode && cpu_rw && m2 && (g_doe != 8'd0);
    reg  cpu_oe_q1 = 1'b0, cpu_oe_q2 = 1'b0;
    always @(posedge clk) begin cpu_oe_q1 <= cpu_oe_now; cpu_oe_q2 <= cpu_oe_q1 && cpu_oe_now; end
    wire cpu_drive = cpu_oe_now && cpu_oe_q1 && cpu_oe_q2;

    assign prg_oe_n = !cpu_rw || cpu_drive;
    assign ram_oe_n = !cpu_rw || cpu_drive;
    assign prg_we_n = !(os_mode && s_prg_wr);   // la ROM del juego solo se escribe desde el OS
    assign ram_we_n = !s_prg_wr;

    assign chr_ce_n = !(!mem_off && s_chr_en);
    // Conducción del bus de datos de la PPU: MMC5 (ExRAM, RBF 103) y 253 (CHR-RAM interna, RBF 105).
    reg [7:0] g_ppudo,g_ppudoe;
    always @(*) begin
        g_ppudo = 8'd0; g_ppudoe = 8'd0;
`ifdef N8_RBF_103
        if (!os_mode && mapper_id==5)   begin g_ppudo = ppudo_005; g_ppudoe = ppudoe_005; end
`endif
`ifdef N8_RBF_105
        if (!os_mode && mapper_id==253) begin g_ppudo = ppudo_559; g_ppudoe = ppudoe_559; end
`endif
    end
    wire ppu_drive=!mem_off && !ppu_rd_n && ppu_wr_n && (|g_ppudoe);
    assign chr_oe_n = ppu_rd_n || ppu_drive;
    assign chr_we_n = !s_chr_wr;

    assign ciram_ce_n = !s_ciram_en || ppu_drive;
    assign ciram_a10  = s_ciram_a10;
    assign ppu_ex     = s_ciram_en;
    assign ppu_dir    = ppu_rd_n;

    assign cpu_irq_n = s_irq ? 1'b0 : 1'bz;
    // ------------------------------------------------------------ sonido de expansión (pin 97)
    // En la Famicom el cartucho devuelve audio a la consola; el N8 lo saca de la FPGA como señal de
    // 1 bit por este pin (en el NES va al pin EXP, que no está conectado a nada sin modificar).
    // Cada chip de sonido da un nivel 0-1023 (escala común: el VRC6 llega a 488 y el 5B a 531, ~50 %);
    // audio_dac.v lo convierte. Con un mapper sin sonido el pin queda en Z, como hasta ahora.
    // Mapper 247 (número sin juegos ni uso oficial): NROM + tono de prueba (audio_tono.v), en 100.RBF. Hasta el
    // 2026-11-08 era el 250, que es oficial (Time Diver Avenger, MMC3 de Nitra) y ahora va al RBF 102.
    reg  [9:0] snd_level;
    reg        snd_on;
`ifdef N8_RBF_100
    wire [9:0] tono_level;
    audio_tono tono (.clk(clk), .en(!os_mode && mapper_id == 8'd247), .level(tono_level));
`endif
    always @(*) begin
        snd_on = 1'b0; snd_level = 10'd0;
        if (!os_mode) case (mapper_id)
`ifdef N8_RBF_100
            8'd69:        begin snd_on = 1'b1; snd_level = snd_069;    end
            8'd247:       begin snd_on = 1'b1; snd_level = tono_level; end
`endif
`ifdef N8_RBF_101
            8'd24, 8'd26: begin snd_on = 1'b1; snd_level = snd_024;    end
`endif
`ifdef N8_RBF_102
            8'd19:        begin snd_on = 1'b1; snd_level = snd_019;    end
`endif
`ifdef N8_RBF_103
            8'd5:         begin snd_on = 1'b1; snd_level = snd_005;    end
`endif
`ifdef N8_RBF_106
            8'd85:        begin snd_on = 1'b1; snd_level = snd_085;    end
`endif
            default: ;
        endcase
    end
    wire snd_pwm;
    audio_dac dac (.clk(clk), .level(snd_level), .pwm(snd_pwm));
    assign cpu_exp   = snd_on ? snd_pwm : 1'bz;
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : dbus
            assign cpu_d[gi] = (cpu_drive && g_doe[gi]) ? g_dout[gi] : 1'bz;
        end
    endgenerate
    generate for(gi=0;gi<8;gi=gi+1) begin : ppudbus
        assign ppu_d[gi]=(ppu_drive && g_ppudoe[gi]) ? g_ppudo[gi] : 1'bz;
    end endgenerate

    assign {cpld_mode1, cpld_mode0} = os_mode ? 2'b11 : 2'b01;

endmodule
