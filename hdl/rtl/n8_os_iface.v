`timescale 1ns/1ps
// n8_os_iface.v — Interfaz OS <-> FPGA del N8 (implementación propia, clean room).
// Comportamiento según docs/hardware-fpga.md, "Protocolo OS <-> FPGA".
//
// - Registros: $4400 = selección de registro (cualquier modo), $4401 = dato (solo modo OS).
// - mapper_id = 0xFF => modo OS (menú). Escribir otro valor en el reg 131 arranca el juego.
// - Vigilancia de M2: si M2 deja de oscilar se apagan las memorias y, pasado el umbral,
//   se vuelve al modo OS (reset de la consola => menú).
// - En modo OS también genera el mapa de memoria que usa el menú para cargar la ROM.
// Game Genie (reg 135) no implementado: las escrituras se ignoran.

module n8_os_iface (
    input  wire        clk,         // reloj del sistema (pin 17)
    input  wire        m2,          // M2 de la CPU (pin de reloj global)
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,    // /ROMSEL
    input  wire        cpu_rw,
    input  wire        bios_off,    // desde el CPLD: 1 = el OS corre desde PRG-RAM
    input  wire [13:0] ppu_a,
    input  wire        ppu_wr_n,

    // configuración para el juego
    output reg  [7:0]  mapper_id,
    output wire        os_mode,
    output reg  [7:0]  cfg,         // bit 0 = mirroring vertical, bit 7 = CHR-RAM
    output reg  [4:0]  prg_size,    // máscara para PRG A18..A14
    output reg  [5:0]  chr_size,    // máscara para CHR A18..A13

    // estado de M2 / reset
    output wire        m2_ok,       // M2 alto y estable
    output reg         mem_off,     // M2 parado: deshabilitar memorias
    output reg         map_reset,   // reset del mapper (volver al menú)

    // mapa de memoria en modo OS (mismo formato que un mapper)
    output wire [18:10] prg_a,
    output wire        prg_rom_en,
    output wire        prg_ram_en,
    output wire        prg_wr,
    output wire [18:10] chr_a,
    output wire        chr_en,
    output wire        chr_wr,
    output wire        ciram_en,
    output wire        ciram_a10
);

    localparam R_PRG_BANK = 8'd128;
    localparam R_RAM_BANK = 8'd129;
    localparam R_CHR_BANK = 8'd130;
    localparam R_MAPPER   = 8'd131;
    localparam R_PRG_SIZE = 8'd132;
    localparam R_CHR_SIZE = 8'd133;
    localparam R_CFG      = 8'd134;
    localparam R_CART_CFG = 8'd136;

    localparam SHORT_IDLE = 26'd128;          // ciclos de clk sin M2
    localparam LONG_IDLE  = 26'h2000000;      // 2^25

    assign os_mode = (mapper_id == 8'hFF);

    // ---------------------------------------------------------------- registros
    reg [7:0] reg_sel;
    reg [7:0] prg_bank;     // ventana de 2 KB en $4800
    reg [5:0] ram_bank;     // ventana de 8 KB en $6000
    reg [6:0] chr_bank;     // bancos de 4 KB
    reg       long_reset;
    reg       m2_toggle;

    reg [3:0]  m2_hist;
    reg [2:0]  tog_sync;
    reg [25:0] idle;

    // valores tras la configuración de la FPGA
    initial begin
        mapper_id  = 8'hFF;
        cfg        = 8'd0;
        prg_size   = 5'd0;
        chr_size   = 6'd0;
        reg_sel    = 8'd0;
        prg_bank   = 8'd0;
        ram_bank   = 6'd0;
        chr_bank   = 7'd0;
        long_reset = 1'b0;
        m2_toggle  = 1'b0;
        m2_hist    = 4'd0;
        tog_sync   = 3'd0;
        idle       = 26'd0;
        mem_off    = 1'b0;
        map_reset  = 1'b0;
    end

    wire reg_win = romsel_n && (cpu_a[14:9] == 6'b100010);   // $4400-$45FF
    wire wr      = !cpu_rw;

    always @(negedge m2) begin
        m2_toggle <= ~m2_toggle;

        if (reg_win && wr && cpu_a[1:0] == 2'd0)
            reg_sel <= cpu_d;

        if (map_reset) begin
            mapper_id <= 8'hFF;
        end else if (reg_win && wr && cpu_a[1:0] == 2'd1 && os_mode) begin
            case (reg_sel)
                R_PRG_BANK: prg_bank  <= cpu_d;
                R_RAM_BANK: ram_bank  <= cpu_d[5:0];
                R_CHR_BANK: chr_bank  <= cpu_d[6:0];
                R_MAPPER:   mapper_id <= cpu_d;
                R_PRG_SIZE: prg_size  <= cpu_d[4:0];
                R_CHR_SIZE: begin chr_size <= cpu_d[5:0]; cfg[7] <= cpu_d[7]; end
                R_CFG:      cfg[6:0]  <= cpu_d[6:0];
                R_CART_CFG: long_reset <= cpu_d[0];
                default: ;
            endcase
        end
    end

    // ---------------------------------------------------------------- vigilancia de M2
    assign m2_ok = m2 && (m2_hist == 4'b1111);

    always @(posedge clk) begin
        m2_hist  <= {m2_hist[2:0], m2};
        tog_sync <= {tog_sync[1:0], m2_toggle};

        if (tog_sync[2] != tog_sync[1]) begin
            idle      <= 26'd0;
            mem_off   <= 1'b0;
            map_reset <= 1'b0;
        end else begin
            if (idle != LONG_IDLE) idle <= idle + 26'd1;
            if (idle >= SHORT_IDLE) mem_off <= 1'b1;
            map_reset <= long_reset ? (idle == LONG_IDLE) : (idle >= SHORT_IDLE);
        end
    end

    // ---------------------------------------------------------------- mapa en modo OS
    wire win_4800 = romsel_n && (cpu_a[14:11] == 4'b1001);   // $4800-$4FFF
    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);     // $6000-$7FFF
    wire win_8000 = !romsel_n;                               // $8000-$FFFF

    assign prg_a = win_8000 ? {4'b0011, cpu_a[14:10]} :
                   win_6000 ? {ram_bank, cpu_a[12:10]} :
                              {prg_bank, cpu_a[10]};

    assign prg_rom_en = win_4800 && m2;
    assign prg_ram_en = m2 && (win_6000 || (bios_off && win_8000));
    assign prg_wr     = wr && m2;

    wire [6:0] chr_bank_lo = chr_bank - 7'd1;
    assign chr_a     = {ppu_a[12] ? chr_bank : chr_bank_lo, ppu_a[11:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = 1'b0;

endmodule
