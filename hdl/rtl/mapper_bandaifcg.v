`timescale 1ns/1ps
// mapper_bandaifcg.v — Mappers 16 (Bandai FCG-1/2 y LZ93D50 + 24C02), 159 (LZ93D50 + 24C01),
// 153 (LZ93D50 con 8 KiB de SRAM en $6000, CHR-RAM y PRG de 512 KiB) y 157 (Datach Joint ROM System:
// LZ93D50, CHR-RAM, 24C02 de la base y, en Battle Rush, otra 24C01 en el cartucho).
// Implementación propia (clean room).
// Registros, decodificados por A3-A0: en el 16 (iNES 1.0) responden $6000-$7FFF y $8000-$FFFF;
// en el 159 solo $8000-$FFFF.
//   0-7: CHR de 1 KB   8: PRG de 16 KB en $8000 ($C000 fijo al último)
//   9: mirroring (0 V, 1 H, 2 A, 3 B)   A: D0 = IRQ y reconoce   B/C: 16 bits (bajo/alto)
//   D: EEPROM serie (D5 = SCL, D6 = SDA), solo en $8000-$FFFF
// Por rango: en $6000-$7FFF (FCG-1/2) B/C son el contador y A no recarga; en $8000-$FFFF
// (LZ93D50) B/C son un latch que A copia al contador.
// Lectura en $6000-$7FFF: D4 = salida de la EEPROM, D3 = 0, el resto queda en bus abierto.
// EEPROM: eeprom_24c0x.v (24C02 de 256 bytes en el 16, 24C01 de 128 bytes en el 159). Las
// partidas duran mientras el juego sigue cargado (ver la nota del módulo).
// IRQ: cada ciclo, si está activa: si el contador vale 0 dispara; después decrementa.
// 157: registros solo en $8000-$FFFF; la 24C02 de la base va como en el 16. La 24C01 del cartucho
// (solo Battle Rush, el único con pila en la cabecera: cfg[1]) toma SCL del bit 3 de las escrituras en
// $8000-$8003 y SDA del bit 6 de $800D; en la lectura, D4 = AND de las dos salidas. D3 (lector de
// códigos de barras) = 0: el N8 no tiene lector, los juegos se juegan sin él.
// 153: $6000-$7FFF es SRAM (activa al encender; $800D D5 la activa/desactiva) que el OS guarda en la SD
// si la cabecera lleva pila; el bit de PRG exterior es el OR del bit 0 de los registros de CHR.
// IRQ por ciclos de CPU: en la bajada de M2 primero se aplica la escritura del ciclo y después
// se da el pulso del contador, que equivale al inicio del ciclo siguiente (igual que el chip, que
// cuenta con M2, y que Mesen2, que cuenta al empezar cada ciclo).
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_bandaifcg (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,   // PPU /RD (solo lo usa el MMC2/MMC4)
    input  wire        ppu_wr_n,
    input  wire [7:0]  cfg,
    input  wire        rst,
    input  wire        clk,        // reloj del sistema (sin uso en este mapper)
    input  wire [7:0]  map_id,     // número de mapper (variantes de una misma familia)
    input  wire [5:0]  chr_size,   // (sin uso)

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

    reg [7:0]  chr [0:7];
    reg [3:0]  prg;
    reg [1:0]  mir;
    reg [15:0] cnt, rl;
    reg        irq_en, irq_pend;
    integer i;
    initial begin
        for (i = 0; i < 8; i = i + 1) chr[i] = 0;
        prg = 0; mir = 0; cnt = 0; rl = 0; irq_en = 0; irq_pend = 0;
    end

    wire m159 = (map_id == 8'd159);
    wire m153 = (map_id == 8'd153);
    wire m157 = (map_id == 8'd157);
    wire x01  = m157 && cfg[1];             // 157 con la 24C01 del cartucho (Battle Rush)
    // $8000-$FFFF siempre; $6000-$7FFF solo en el 16 (en el 153 es SRAM, en el 157/159 nada)
    wire reg_wr = !cpu_rw && (!romsel_n || (!m159 && !m153 && !m157 && romsel_n && cpu_a[14:13] == 2'b11));
    reg sram_en = 1'b1;                    // 153: SRAM de $6000 (activa al encender; $800D D5)
    // El OS no da el submapper, pero cada placa decodifica un solo rango: FCG-1/2 solo
    // $6000-$7FFF, LZ93D50 solo $8000-$FFFF. Así, la semántica sale de la dirección:
    //   $6000-$7FFF (FCG-1/2): B/C escriben el contador; A activa sin recargar; sin EEPROM.
    //   $8000-$FFFF (LZ93D50): B/C escriben el latch; A lo copia al contador; D = EEPROM.
    wire fcg = romsel_n;
    reg [15:0] t_cnt; reg t_pend, t_en;
    reg e_scl = 0, e_sda = 0, e_tgl = 0;   // última muestra SCL/SDA escrita en $xxxD
    reg x_scl = 0, x_sda = 0, x_tgl = 0;   // 157: muestras de la 24C01 del cartucho
    always @(negedge m2) begin
        if (rst) begin
            for (i = 0; i < 8; i = i + 1) chr[i] <= 0;
            prg <= 0; mir <= cfg[0] ? 2'd0 : 2'd1; cnt <= 0; rl <= 0; irq_en <= 0; irq_pend <= 0;
            sram_en <= 1'b1;
        end else begin
            if (reg_wr && !fcg && !m153 && cpu_a[3:0] == 4'hD) begin
                e_scl <= cpu_d[5]; e_sda <= cpu_d[6]; e_tgl <= ~e_tgl;
                if (x01) begin x_sda <= cpu_d[6]; x_tgl <= ~x_tgl; end
            end
            if (reg_wr && x01 && !romsel_n && cpu_a[3:2] == 2'b00) begin
                x_scl <= cpu_d[3]; x_tgl <= ~x_tgl;
            end
            t_cnt = cnt; t_pend = irq_pend; t_en = irq_en;
            if (reg_wr) begin
                case (cpu_a[3:0])
                    4'h8: prg <= cpu_d[3:0];
                    4'h9: mir <= cpu_d[1:0];
                    4'hA: begin t_en = cpu_d[0]; if (!fcg) t_cnt = rl; t_pend = 1'b0; end
                    4'hB: if (fcg) t_cnt[7:0]  = cpu_d; else rl[7:0]  <= cpu_d;
                    4'hC: if (fcg) t_cnt[15:8] = cpu_d; else rl[15:8] <= cpu_d;
                    4'hD: if (m153) sram_en <= cpu_d[5];
                    4'hE, 4'hF: ;
                    default: chr[cpu_a[2:0]] <= cpu_d;
                endcase
            end
            if (t_en) begin
                if (t_cnt == 16'd0) t_pend = 1'b1;
                t_cnt = t_cnt - 16'd1;
            end
            cnt <= t_cnt; irq_pend <= t_pend; irq_en <= t_en;
        end
    end

    // 153: bit de PRG exterior (256 KiB) = OR del bit 0 de los ocho registros de CHR
    wire outer = m153 && (chr[0][0] | chr[1][0] | chr[2][0] | chr[3][0] |
                          chr[4][0] | chr[5][0] | chr[6][0] | chr[7][0]);
    wire win6  = romsel_n && cpu_a[14:13] == 2'b11;                // $6000-$7FFF
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = m153 && win6 && sram_en && m2;
    assign prg_wr     = prg_ram_en && !cpu_rw;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {outer, cpu_a[14] ? 4'b1111 : prg, cpu_a[13:10]};

    // CHR-RAM sin banca (el 153 y cualquier variante sin CHR-ROM); CHR-ROM en bancos de 1 KiB
    wire [7:0] cb = chr[ppu_a[12:10]];   // (157: CHR-RAM siempre, los registros no mapean CHR)
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {1'b0, cb};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    // mirroring: 0 vertical, 1 horizontal, 2 pantalla A, 3 pantalla B
    assign ciram_a10 = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : mir[0];
    assign irq = irq_pend;

    // ---- EEPROM serie (dominio clk): cada escritura en $xxxD es una muestra SCL/SDA
    reg [2:0] e_s = 3'd0;
    always @(posedge clk) e_s <= {e_s[1:0], e_tgl};
    wire e_ev = e_s[2] != e_s[1];
    wire e_out;
    eeprom_24c0x eeprom (.clk(clk), .rst(rst), .c01(m159), .ev(e_ev), .scl(e_scl), .sda(e_sda), .out(e_out));
    // 157: 24C01 del cartucho (solo se instancia la lógica; sin x01 nunca recibe muestras y su salida no cuenta)
    reg [2:0] x_s = 3'd0;
    always @(posedge clk) x_s <= {x_s[1:0], x_tgl};
    wire x_out;
    eeprom_24c0x eeprom_x (.clk(clk), .rst(rst), .c01(1'b1), .ev(x_s[2] != x_s[1]), .scl(x_scl), .sda(x_sda), .out(x_out));
    wire sda_out = e_out & (x01 ? x_out : 1'b1);

    wire rd6 = !m153 && romsel_n && cpu_rw && m2 && cpu_a[14:13] == 2'b11;   // $6000-$7FFF (153: SRAM)
    assign cpu_doe  = rd6 ? 8'h18 : 8'h00;                          // D4 EEPROM, D3 = 0
    assign cpu_dout = {3'b000, sda_out, 4'b0000};

endmodule
