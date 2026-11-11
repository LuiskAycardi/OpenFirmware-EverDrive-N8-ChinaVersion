`timescale 1ns/1ps
// mapper_vrc24.v — Mappers 21, 22, 23 y 25 (Konami VRC2 / VRC4) y los clones 27, 183 y 252 (fase 4, lote 5).
// Implementación propia (clean room).
// Cada número agrupa variantes que se distinguen por qué líneas de dirección van a las
// entradas A0/A1 del chip. Con cabecera iNES 1.0 se combinan (OR) como hace Mesen2:
//   21 (VRC4a/c): A0 = A1|A6, A1 = A2|A7        23 (VRC2b/VRC4e): A0 = A0|A2, A1 = A1|A3
//   25 (VRC4b/d): A0 = A1|A3, A1 = A0|A2        22 (VRC2a):       A0 = A1,    A1 = A0
// Registros (tras traducir A1:A0):
//   $8000-$8003 PRG 8 KB en $8000 (o $C000 en modo 1)     $A000-$A003 PRG 8 KB en $A000
//   $9000-$9001 mirroring (0 V, 1 H, 2 A, 3 B; el 22 solo V/H); $9002-$9003 modo PRG (21 y 25)
//   $B000-$E003 CHR de 1 KB: 8 registros en mitades de 4+5 bits ($x000/$x001, $x002/$x003)
//   $F000/$F001 recarga de IRQ (nibbles), $F002 control, $F003 reconocimiento
//   El 22 (VRC2a) desplaza el banco CHR un bit y no tiene IRQ.
// Clones (fase 4, lote 5; NESdev Wiki):
//   27  VRC4 pirata (World Hero): A0 = A0, A1 = A1, con modo PRG; CHR de 9 bits.
//   183 Shui Guan Pipe (Gimmick! pirata): VRC4 cableado como el VRC4e (A0 = A2, A1 = A3) más un registro que pone
//       ROM de 8 KB en $6000: cualquier escritura en $6000-$7FFF elige el banco con A3-A0. Mesen2 sigue la
//       implementación antigua que NESdev da por errónea (registros en $8800/$A800/$A000 y otra IRQ).
//   252 Waixing (Sangokushi): VRC4 clon con A0 = A2, A1 = A3; los bancos de CHR 6 y 7 son CHR-RAM (2 KB, en la
//       misma zona libre de la SRAM CHR que el TQROM: salida chr_raw); 8 KB de PRG-RAM. Sin modo PRG.
// IRQ VRC: cuenta hacia arriba hasta $FF, recarga y dispara. Modo ciclo: un pulso por ciclo de
// CPU. Modo scanline: un preescalador resta 3 por ciclo y da un pulso cuando llega a <= 0 (+341).
// IRQ por ciclos de CPU: en la bajada de M2 primero se aplica la escritura del ciclo y después
// se da el pulso del contador, que equivale al inicio del ciclo siguiente (igual que el chip, que
// cuenta con M2, y que Mesen2, que cuenta al empezar cada ciclo).
// No implementado: el bit de $6000-$7FFF que algunos VRC2 leen como protección (habría que
// conducir el bus de datos); la PRG-RAM de $6000 queda como RAM normal.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_vrc24 (
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
    output wire        chr_raw     // 1 = chr_a sin la máscara del OS (CHR-RAM del 252)
);

    // variante según el número de mapper (fijo durante la partida)
    wire IS21 = (map_id == 8'd21), IS22 = (map_id == 8'd22), IS23 = (map_id == 8'd23), IS25 = (map_id == 8'd25);
    wire IS27 = (map_id == 8'd27), IS183 = (map_id == 8'd183), IS252 = (map_id == 8'd252);
    wire A23 = IS183 || IS252;                                  // A0 = A2, A1 = A3
    wire HAS_PRG_MODE = IS21 || IS25 || IS27;
    wire HAS_IRQ      = !IS22;

    // ------------------------------------------------ traducción de A0/A1
    wire a0 = IS21 ? (cpu_a[1] | cpu_a[6]) :
              IS23 ? (cpu_a[0] | cpu_a[2]) :
              IS25 ? (cpu_a[1] | cpu_a[3]) :
              IS27 ? cpu_a[0] : A23 ? cpu_a[2] : cpu_a[1];
    wire a1 = IS21 ? (cpu_a[2] | cpu_a[7]) :
              IS23 ? (cpu_a[1] | cpu_a[3]) :
              IS25 ? (cpu_a[0] | cpu_a[2]) :
              IS27 ? cpu_a[1] : A23 ? cpu_a[3] : cpu_a[0];
    wire [2:0] page = cpu_a[14:12];          // $8000 -> 0 ... $F000 -> 7
    wire rom_wr = !romsel_n && !cpu_rw;

    reg [4:0] prg0, prg1;
    reg [3:0] prg6;                                              // 183: ROM en $6000
    reg       prg_mode;
    reg [1:0] mir;
    reg [3:0] chr_lo [0:7];
    reg [4:0] chr_hi [0:7];
    integer i;

    initial begin
        prg0 = 0; prg1 = 0; prg_mode = 0; mir = 0; prg6 = 0;
        for (i = 0; i < 8; i = i + 1) begin chr_lo[i] = 0; chr_hi[i] = 0; end
    end

    wire [1:0] chr_pg  = page[1:0] + 2'd1;                        // $B000 -> 0 ... $E000 -> 3
    wire [2:0] chr_idx = {chr_pg, a1};                             // $B000 -> 0,1 ... $E000 -> 6,7

    always @(negedge m2) begin
        if (rst) begin
            prg0 <= 0; prg1 <= 0; prg_mode <= 0; mir <= cfg[0] ? 2'd0 : 2'd1; prg6 <= 0;
            for (i = 0; i < 8; i = i + 1) begin chr_lo[i] <= 0; chr_hi[i] <= 0; end
        end else if (IS183 && romsel_n && !cpu_rw && cpu_a[14:13] == 2'b11) begin
            prg6 <= cpu_a[3:0];                                  // $6000-$7FFF: banco = A3-A0
        end else if (rom_wr) begin
            case (page)
                3'd0: prg0 <= cpu_d[4:0];
                3'd1: if (!a1 || !HAS_PRG_MODE) mir <= IS22 ? {1'b0, cpu_d[0]} : cpu_d[1:0];
                      else prg_mode <= cpu_d[1];
                3'd2: prg1 <= cpu_d[4:0];
                3'd7: ;                                   // IRQ: vrc_irq
                default: if (a0) chr_hi[chr_idx] <= cpu_d[4:0];
                         else    chr_lo[chr_idx] <= cpu_d[3:0];
            endcase
        end
    end

    // ------------------------------------------------ IRQ ($F000-$F003; el 22 no tiene)
    wire irq_wr = HAS_IRQ && rom_wr && (page == 3'd7);
    wire irq_pend;
    vrc_irq virq (
        .m2(m2), .rst(rst),
        .wr_lat_lo(irq_wr && {a1, a0} == 2'd0), .wr_lat_hi(irq_wr && {a1, a0} == 2'd1),
        .wr_lat(1'b0),
        .wr_ctrl(irq_wr && {a1, a0} == 2'd2), .wr_ack(irq_wr && {a1, a0} == 2'd3),
        .d(cpu_d), .irq(irq_pend));

    // ------------------------------------------------ PRG (8 KB)
    // bancos fijos (penúltimo/último) con todos los bits a 1, también A18: la máscara PRG_SIZE
    // del OS los lleva al final real de la ROM
    wire swap = HAS_PRG_MODE && prg_mode;
    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = swap ? 6'b111110 : {1'b0, prg0};
            2'd1: bank8 = {1'b0, prg1};
            2'd2: bank8 = swap ? {1'b0, prg0} : 6'b111110;
            2'd3: bank8 = 6'b111111;
        endcase
    end

    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n || (IS183 && win_6000 && m2);
    assign prg_ram_en = win_6000 && !IS183 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a = !romsel_n ? {bank8, cpu_a[12:10]} : IS183 ? {2'd0, prg6, cpu_a[12:10]} : {6'd0, cpu_a[12:10]};

    // ------------------------------------------------ CHR (1 KB)
    wire [8:0] chr_full = {chr_hi[ppu_a[12:10]], chr_lo[ppu_a[12:10]]};
    wire [8:0] chr_bank = IS22 ? {1'b0, chr_full[8:1]} : chr_full;
    wire ram252  = IS252 && (chr_bank[8:1] == 8'd3);           // bancos 6 y 7: CHR-RAM
    assign chr_raw = ram252;
    assign chr_a = ram252 ? {6'b111110, 2'b00, chr_bank[0]} :
                   cfg[7] ? {6'd0, chr_bank[2:0]} : chr_bank;

    assign chr_en    = !ppu_a[13];
    assign chr_wr    = (cfg[7] || ram252) && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    // mirroring: 0 vertical, 1 horizontal, 2 pantalla A, 3 pantalla B
    assign ciram_a10 = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : mir[0];
    assign irq = irq_pend;

endmodule
