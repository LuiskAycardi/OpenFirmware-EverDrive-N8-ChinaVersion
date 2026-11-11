`timescale 1ns/1ps
// mapper_mmc3.v — Mapper 4 (MMC3: TxROM). Implementación propia según la descripción
// pública del chip (NESdev Wiki).
//
// Registros (escritura en $8000-$FFFF, decodificados por A14..A13 y A0):
//   $8000 par    selección: [2:0] registro destino R0..R7, [6] modo PRG, [7] inversión CHR A12
//   $8001 impar  dato del banco elegido
//   $A000 par    mirroring: 0 = vertical, 1 = horizontal
//   $A001 impar  protección de PRG-RAM: se ignora (como hacen los emuladores, por
//                compatibilidad con el MMC6 de StarTropics); la PRG-RAM queda habilitada
//   $C000 par    valor de recarga del contador de IRQ
//   $C001 impar  recargar el contador en el próximo pulso
//   $E000 par    desactivar IRQ (y reconocer la pendiente)
//   $E001 impar  activar IRQ
//
// PRG (bancos de 8 KB, 6 bits = 512 KB):
//   modo 0: $8000 = R6, $A000 = R7, $C000 = penúltimo, $E000 = último
//   modo 1: $8000 = penúltimo, $A000 = R7, $C000 = R6, $E000 = último
//   ("último" = todo unos; la máscara PRG_SIZE del OS lo lleva al último banco real).
// CHR (bancos de 1 KB, 8 bits = 256 KB):
//   sin inversión: $0000 R0 (2 KB), $0800 R1 (2 KB), $1000 R2, $1400 R3, $1800 R4, $1C00 R5
//   con inversión: las dos mitades de 4 KB intercambiadas.
//   Con CHR-RAM (TGROM/TNROM, p. ej. Mega Man 4/6) el OS deja la máscara abierta ($FF):
//   se recorta aquí a 8 KB.
//
// IRQ por scanline: el contador se decrementa en cada flanco de subida de PPU A12 que llega
// después de que A12 haya estado bajo durante al menos 4 flancos de bajada de M2 (filtro
// del chip real: ignora las subidas cortas de las búsquedas de sprites). Comportamiento del
// MMC3 "nuevo" (Sharp): si el contador vale 0 o hay recarga pendiente se carga con el valor de
// $C000; si no, se decrementa. Si tras eso vale 0 y la IRQ está activa, /IRQ baja hasta $E000.
// Esta parte corre con clk (pin 17): ver a12_filter.v.
//
// 4 pantallas (TVROM/TR1ROM: Rad Racer II) no está aquí: lo resuelve n8_top para cualquier
// mapper con MAP_CFG bit 3.
//
// Variantes (misma instancia, elegidas por map_id; fase 3c):
//   118 TxSROM: CIRAM A10 = bit 7 del banco CHR.
//   119 TQROM:  bancos CHR con el bit 6 a 1 van a 8 KB de CHR-RAM (fuera de la máscara del OS,
//               en CHR 0x7C000-0x7DFFF: salida chr_raw); el resto, CHR-ROM de hasta 64 KB.
//   37  (SMB + Tetris + NWC): bloque en $6000-$7FFF (D2-D0). Bloques 0-2: PRG 64 KB del 0,
//       3: 64 KB desde 0x10000, 4-6: 128 KB desde 0x20000, 7: 64 KB desde 0x40000;
//       CHR: bloques 4-7 suman 0x80 al banco de 1 KB.
//   47  (Super Spike V'Ball + NWC): bloque D0 en $6000-$7FFF: 128 KB de PRG y CHR por bloque.
//   115 (Kasheng SFC-02B): $4100-$7FFF; A0 = 0: PRG [7] activa el modo NROM, [5] 32 KB / 16 KB,
//       [3:0] banco de 16 KB; A0 = 1: D0 = CHR A18. $5080 = registro de protección: lo que se escribe
//       ahí se lee en $5000-$5FFF (fase 3d: la FPGA conduce el bus).
//   189 (TXC): $4120-$7FFF: banco de 32 KB = (D | D >> 4) & 7; el MMC3 solo hace CHR e IRQ.
//   37, 47, 115 y 189 no tienen PRG-RAM (sus registros ocupan $6000-$7FFF).

module mapper_mmc3 #(
    // GRUPO 0 (RBF 100): 4 y las variantes 37, 47, 115, 118, 119, 189.
    // GRUPO 1 (RBF 102, fase 4): 12, 44, 45, 49, 52, 74, 134, 182, 187, 191, 196, 197, 198, 199, 205, 238, 245,
    //   249, 250. Cada instancia solo sintetiza las variantes de su grupo.
    // GRUPO 2: 165, 176/submapper 0, 192, 194, 195, 219, legacy 248.
    parameter GRUPO = 0
) (
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
    input  wire        clk,
    input  wire [7:0]  map_id,     // número de mapper (variantes de una misma familia)
    input  wire [5:0]  chr_size,   // máscara CHR del OS (sin uso aquí)

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
    output wire        chr_raw,    // 1 = chr_a sin la máscara CHR del OS (CHR-RAM del TQROM)
    output wire [7:0]  cpu_dout,   // lecturas de registros (115: protección en $5000-$5FFF)
    output wire [7:0]  cpu_doe
);

    wire G0 = (GRUPO == 0), G1 = (GRUPO == 1), G2 = (GRUPO == 2);
    wire TXSROM = G0 && (map_id == 8'd118);   // TxSROM: CIRAM A10 = bit 7 del banco CHR de la nametable
    wire TQROM  = G0 && (map_id == 8'd119);
    wire M37    = G0 && (map_id == 8'd37);
    wire M47    = G0 && (map_id == 8'd47);
    wire M115   = (G0 && (map_id == 8'd115)) || (G2 && (map_id == 8'd248));
    wire M189   = G0 && (map_id == 8'd189);
    // fase 4 (GRUPO 1)
    wire M12  = G1 && (map_id == 8'd12),  M44  = G1 && (map_id == 8'd44),  M45  = G1 && (map_id == 8'd45);
    wire M49  = G1 && (map_id == 8'd49),  M52  = G1 && (map_id == 8'd52),  M74  = G1 && (map_id == 8'd74);
    wire M134 = G1 && (map_id == 8'd134), M182 = G1 && (map_id == 8'd182), M187 = G1 && (map_id == 8'd187);
    wire M191 = G1 && (map_id == 8'd191), M196 = G1 && (map_id == 8'd196), M197 = G1 && (map_id == 8'd197);
    wire M198 = G1 && (map_id == 8'd198), M199 = G1 && (map_id == 8'd199), M205 = G1 && (map_id == 8'd205);
    wire M238 = G1 && (map_id == 8'd238), M249 = G1 && (map_id == 8'd249), M250 = G1 && (map_id == 8'd250);
    wire M165 = G2 && map_id == 8'd165;
    // 176 is the FK23C multicart and lives in mapper_fk23c.v; the old LP-8002KB/SFC-12B
    // submapper-0 path of this core is disabled (synthesis prunes it).
    wire M176 = 1'b0;
    wire M219 = G2 && map_id == 8'd219;
    // 192 (Waixing): plain MMC3 whose 1 KiB CHR banks $08-$0B are 4 KiB of CHR-RAM.
    wire M192 = G2 && map_id == 8'd192;
    // 194 / 195 (Waixing): plain MMC3 whose 1 KiB CHR banks $00-$01 (2 KiB) / $00-$03 (4 KiB) are CHR-RAM.
    wire M194 = G2 && map_id == 8'd194, M195 = G2 && map_id == 8'd195;
    // 114 (Super Game / Lion King): $5000-$7FFF = PRG register (D7 = 16 KiB mode, D3-D0 bank); the MMC3
    //   ports are swapped ($8001 = mirroring, $A000 = select with scrambled D2-D0, $A001 = IRQ latch,
    //   $C000 = bank data once per select, $C001 = reload) and the IRQ is the MMC3A one.
    // 121 (Kay / Panda Prince): $5000-$5FFF protection (write lookup, read back) and $5180 outer bit;
    //   $8003 / $8001 load extra PRG registers through a command table.
    // 215 (UNL-8237): $5000 / $5001 outer PRG/CHR, $5007 selects a register/address scramble table.
    wire M114 = G2 && map_id == 8'd114, M121 = G2 && map_id == 8'd121, M215 = G2 && map_id == 8'd215;
    wire NO_RAM = M37 || M47 || M115 || M189 || M45 || M49 || M205 || M238 || M187 || M198 || M114 || M215;

    // ================================================================ registros (dominio M2)
    reg [2:0] sel;
    reg       prg_mode, chr_inv;
    reg [7:0] r0, r1, r2, r3, r4, r5;     // CHR, unidades de 1 KB
    reg [5:0] r6, r7;                     // PRG, unidades de 8 KB
    reg       mir_h;                      // 1 = horizontal
    reg [7:0] irq_latch;
    reg       irq_en;
    reg       reload_tgl;                 // cambia en cada escritura a $C001
    reg [7:0] ext;                        // registro exterior de las variantes (37, 47, 115 PRG, 189)
    reg       ext_chr;                    // 115: CHR A18
    reg [7:0] prot;                       // 115: protección ($5080)
    // fase 4: registros exteriores de las variantes del grupo 1 (solo una variante activa a la vez)
    reg       sel3;                       // bit 3 de $8000 (199: registros extra)
    reg       mir_s;                      // bit 1 de $A000 (199: pantalla única)
    reg [7:0] x2;                         // 196: D7 = modo 32 KB, D3-D0 = banco
    reg [7:0] xa [0:3];                   // 45: cuatro registros; 198/199: registros extra
    reg [1:0] i45;                        // 45: siguiente registro
    reg [1:0] a001;                       // D7-D6 de $A001 (49/52: el registro exterior solo con la RAM habilitada)
    reg [5:0] x198a, x198b;               // 198: PRG de 8 KB en $8000/$A000 (al encender 0 y 1)
    reg [7:0] x199 [0:3];                 // 199: PRG $C000/$E000 y CHR extra (al encender $FE, $FF, 1, 3)

    // Clean-room group 2, public register facts:
    // https://www.nesdev.org/wiki/INES_Mapper_165
    // https://www.nesdev.org/wiki/INES_Mapper_176
    // https://www.nesdev.org/wiki/INES_Mapper_219
    // 248 alias history: https://mamedev.emulab.it/etabeta/2009/10/07/nes-on-fire-part-1/
    // Mesen2 read for comparison only; no source translated/copied.
    // 176: LP-8002KB/SFC-12B submapper 0, solder pad 0 ($501x).
    // Interface has no submapper input and no address above A18: submappers
    // 1..5 (FK23C/FS005/JX9003B/GameStar/HST-162), extended MMC3/CNROM,
    // banked WRAM and larger ROMs are NOT claimed. Mode 6/7 undocumented.
    // CHR-RAM is limited to 8 KiB (165: 4 KiB). Mixed 176 CHR-RAM uses
    // $7C000-$7DFFF; ROM images must leave that physical SRAM range free.
    // IRQ uses this core's filtered Sharp MMC3 behavior; 176's possible
    // additional assertion delay and real-board analog timing are unverified.
    // 248: historical Bao Qing Tian / 115 alias, not experimental mappers.
    // 219: documented A9461 modes, not old Mesen2's extended-only subset.
    reg [7:0] mode176=0, base176=0, chr176=0;
    reg [2:0] unrom176=0;
    // 219 (Mesen MMC3_219 / A9461): $8000->er0=0,er1=v; $8002->er0=v,er1=0;
    // $8001 applies a PRG bank (when er0 in 0x23-0x26, 4 scrambled bits) and/or a
    // CHR bank (per er1 command, with er2 as the high base). The MMC3 core's PRG/CHR
    // update is bypassed; $A000+ still drives its mirroring and IRQ. Init = last 4
    // PRG banks (-4) and CHR 0-7.
    reg [7:0] er0219=0, er1219=0, er2219=0;
    reg [5:0] pp219 [0:3];
    reg [7:0] cc219 [0:7];
    integer init219, reset219;
    reg [7:0] x114 = 0; reg s114 = 0;                     // 114: PRG register, "select written" flag
    reg [7:0] e121 [0:7];                                 // 121: extra registers (Mesen's naming 0-7)
    reg [7:0] x215a = 0, x215b = 8'd3, x215c = 0;         // 215: $5000, $5001 (power-on 3), $5007
    initial begin e121[0]=0; e121[1]=0; e121[2]=0; e121[3]=8'h80; e121[4]=0; e121[5]=0; e121[6]=0; e121[7]=0; end
    function [2:0] sec114(input [2:0] v);
        case (v)
            3'd0: sec114 = 3'd0; 3'd1: sec114 = 3'd3; 3'd2: sec114 = 3'd1; 3'd3: sec114 = 3'd5;
            3'd4: sec114 = 3'd6; 3'd5: sec114 = 3'd7; 3'd6: sec114 = 3'd2; default: sec114 = 3'd4;
        endcase
    endfunction
    // 215 tables: address (port {A14,A13,A0} -> port) and select value, per $5007 (rows 5-7 = identity)
    function [2:0] adr215(input [2:0] t, input [2:0] i);
        reg [23:0] row;
        begin
            case (t)
                3'd1: row = {3'd7,3'd6,3'd5,3'd1,3'd4,3'd0,3'd2,3'd3};
                3'd3: row = {3'd4,3'd6,3'd7,3'd3,3'd2,3'd1,3'd0,3'd5};
                3'd4: row = {3'd7,3'd6,3'd4,3'd2,3'd5,3'd0,3'd1,3'd3};
                default: row = {3'd7,3'd6,3'd5,3'd4,3'd3,3'd2,3'd1,3'd0};
            endcase
            adr215 = row[i*3 +: 3];
        end
    endfunction
    function [2:0] reg215(input [2:0] t, input [2:0] i);
        reg [23:0] row;
        begin
            case (t)
                3'd1: row = {3'd5,3'd4,3'd3,3'd7,3'd1,3'd6,3'd2,3'd0};
                3'd2: row = {3'd3,3'd6,3'd2,3'd7,3'd1,3'd4,3'd5,3'd0};
                3'd3: row = {3'd1,3'd4,3'd2,3'd5,3'd7,3'd3,3'd6,3'd0};
                3'd4: row = {3'd4,3'd7,3'd1,3'd6,3'd3,3'd5,3'd2,3'd0};
                default: row = {3'd7,3'd6,3'd5,3'd4,3'd3,3'd2,3'd1,3'd0};
            endcase
            reg215 = row[i*3 +: 3];
        end
    endfunction
    // 121: command table run on $8003 (new command) and on $8001 (new value, unless locked by e7)
    function [31:0] upd121(input [7:0] c5, input [7:0] v6, input [7:0] o0, input [7:0] o1, input [7:0] o2, input o7);
        reg [7:0] n0, n1, n2, n5; reg n7;
        begin
            n0 = o0; n1 = o1; n2 = o2; n5 = c5; n7 = o7;
            case (c5[5:0])
                6'h20, 6'h29, 6'h2B, 6'h3C, 6'h3F: begin n7 = 1'b1; n0 = v6; end
                6'h26: begin n7 = 1'b0; n0 = v6; end
                6'h2C: begin n7 = 1'b1; if (v6 != 0) n0 = v6; end
                6'h28: begin n7 = 1'b0; n1 = v6; end
                6'h2A: begin n7 = 1'b0; n2 = v6; end
                6'h2F: ;
                default: n5 = 8'd0;
            endcase
            upd121 = {n7, n5[6:0], n2, n1, n0};    // n5 bit 7 is not used by the mapping
        end
    endfunction
    initial begin
        for (init219=0; init219<4; init219=init219+1) pp219[init219]=6'h3c+init219[5:0];
        for (init219=0; init219<8; init219=init219+1) cc219[init219]=init219[7:0];
    end

    initial begin
        sel = 0; prg_mode = 0; chr_inv = 0;
        r0 = 8'd0; r1 = 8'd2; r2 = 8'd4; r3 = 8'd5; r4 = 8'd6; r5 = 8'd7;
        r6 = 6'd0; r7 = 6'd1;
        mir_h = 0; irq_latch = 0; irq_en = 0; reload_tgl = 0; ext = 0; ext_chr = 0; prot = 0;
        sel3 = 0; mir_s = 0; x2 = 0; xa[0] = 0; xa[1] = 0; xa[2] = 8'h0F; xa[3] = 0; i45 = 0;
        a001 = 0; x198a = 0; x198b = 1; x199[0] = 8'hFE; x199[1] = 8'hFF; x199[2] = 8'd1; x199[3] = 8'd3;
    end

    wire rom_wr = !romsel_n && !cpu_rw;
    // escrituras en $4000-$7FFF (romsel alto, A14 = 1) para los registros exteriores
    wire lo_wr  = romsel_n && !cpu_rw && cpu_a[14];
    wire w6000  = lo_wr && cpu_a[13];                                   // $6000-$7FFF
    wire w4100  = lo_wr && (cpu_a[13:8] != 6'd0) && (cpu_a[13:0] != 14'h1080);   // $4100-$7FFF salvo $5080
    wire w4120  = lo_wr && (cpu_a[13:0] >= 14'h0120);                   // $4120-$7FFF

    // Escritura al núcleo del MMC3: registro (A14, A13, A0) y dato, según la variante.
    //   250: dirección como dato (A7-A0) y A10 en lugar de A0.   196: A0 = A0 | A2 | A3 (| A1 por debajo de $C000).
    //   182: $A000 = selección (bits 2-0 barajados), $8001 = mirroring, $C000 = dato, $C001 = recarga + valor.
    function [2:0] scr182(input [2:0] v);
        case (v)
            3'd0: scr182 = 3'd0; 3'd1: scr182 = 3'd3; 3'd2: scr182 = 3'd1; 3'd3: scr182 = 3'd5;
            3'd4: scr182 = 3'd6; 3'd5: scr182 = 3'd7; 3'd6: scr182 = 3'd2; default: scr182 = 3'd4;
        endcase
    endfunction
    wire [2:0] rs_in = {cpu_a[14:13], M250 ? cpu_a[10] :
                        M196 ? (cpu_a[2] | cpu_a[3] | (!cpu_a[14] & cpu_a[1])) : cpu_a[0]};   // 196: A0 sustituido
    reg  [2:0] rs; reg [7:0] wd; reg wcore, w182c001;
    always @(*) begin
        rs = rs_in; wd = M250 ? cpu_a[7:0] : cpu_d; wcore = rom_wr; w182c001 = 1'b0;
        if (M182) case (rs_in)
            3'b001: rs = 3'b010;
            3'b010: begin rs = 3'b000; wd = {cpu_d[7:3], scr182(cpu_d[2:0])}; end
            3'b100: rs = 3'b001;
            3'b101: begin wcore = 1'b0; w182c001 = rom_wr; end
            3'b110, 3'b111: ;
            default: wcore = 1'b0;
        endcase
        // 176 decodes $E003; UNROM consumes all ROM writes.
        if (M176 && (cpu_a[1] || mode176[2:0]==3'd5)) wcore=0;
        if (M219 && cpu_a[14:13]==0) wcore=0;   // $8000-$9FFF: 219 custom decode
        // 114: swapped ports, scrambled select, bank data once per select
        if (M114) case (rs_in)
            3'b000: wcore = 1'b0;
            3'b001: rs = 3'b010;
            3'b010: begin rs = 3'b000; wd = {cpu_d[7:6], 3'b000, sec114(cpu_d[2:0])}; end
            3'b011: rs = 3'b100;
            3'b100: begin rs = 3'b001; if (!s114) wcore = 1'b0; end
            default: ;
        endcase
        // 121: $8003 is also a select write
        if (M121 && rs_in == 3'b001 && cpu_a[1]) rs = 3'b000;
        // 215: port and select value through the $5007 tables
        if (M215) begin
            rs = adr215(x215c[2:0], rs_in);
            if (rs == 3'b000) wd = {cpu_d[7:6], 3'b000, reg215(x215c[2:0], cpu_d[2:0])};
        end
        // 199: $8001 con el bit 3 de la selección -> registros extra (no los del núcleo)
        if (M199 && rs_in == 3'b001 && sel3) wcore = 1'b0;
    end

    always @(negedge m2) begin
        if (rst) begin
            mode176<=0; base176<=0; chr176<=0; unrom176<=0;
            er0219<=0; er1219<=0; er2219<=0;
            for (reset219=0; reset219<4; reset219=reset219+1) pp219[reset219]<=6'h3c+reset219[5:0];
            for (reset219=0; reset219<8; reset219=reset219+1) cc219[reset219]<=reset219[7:0];
            x114 <= 0; s114 <= 0; x215a <= 0; x215b <= 8'd3; x215c <= 0;
            e121[0]<=0; e121[1]<=0; e121[2]<=0; e121[3]<=8'h80; e121[4]<=0; e121[5]<=0; e121[6]<=0; e121[7]<=0;
            sel <= 0; prg_mode <= 0; chr_inv <= 0;
            r0 <= 8'd0; r1 <= 8'd2; r2 <= 8'd4; r3 <= 8'd5; r4 <= 8'd6; r5 <= 8'd7;
            r6 <= 6'd0; r7 <= 6'd1;
            mir_h     <= !cfg[0];             // hasta que el juego escriba $A000: cabecera
            irq_latch <= 8'd0;
            irq_en    <= 1'b0;
            ext       <= 8'd0;
            ext_chr   <= 1'b0;
            prot      <= 8'd0;
            sel3 <= 0; mir_s <= 0; x2 <= 0; xa[0] <= 0; xa[1] <= 0; xa[2] <= 8'h0F; xa[3] <= 0; i45 <= 0;
            a001 <= 0; x198a <= 0; x198b <= 1;
            x199[0] <= 8'hFE; x199[1] <= 8'hFF; x199[2] <= 8'd1; x199[3] <= 8'd3;
        end else if (romsel_n) begin          // $4000-$7FFF: registros exteriores
            if (M176 && lo_wr && (cpu_a & 15'h7010)==15'h5010)
                case (cpu_a[1:0])
                    0: mode176<=cpu_d;
                    1: base176<=cpu_d;
                    2: chr176<=cpu_d;
                    default: ; // no extended mode on submapper 0
                endcase
            if ((M37 || M47) && w6000) ext <= cpu_d;
            if (M115 && lo_wr && cpu_a[13:0] == 14'h1080) prot <= cpu_d;
            if (M115 && w4100) begin
                if (cpu_a[0]) ext_chr <= cpu_d[0];
                else          ext     <= cpu_d;
            end
            if (M189 && w4120) ext <= cpu_d;
            // fase 4
            if (M12 && lo_wr && !cpu_a[13] && (cpu_a[12:5] != 8'd0)) ext <= cpu_d;     // $4020-$5FFF
            if (M205 && w6000) ext <= cpu_d;
            // 49 y 52: el registro exterior se carga con las salidas de RAM del MMC3: solo con $A001 = 10xxxxxx
            if (M49 && w6000 && a001 == 2'b10) ext <= cpu_d;
            if (M52 && w6000 && a001 == 2'b10 && !ext[7]) ext <= cpu_d;               // hasta el bloqueo (D7)
            if (M134 && w6000 && cpu_a[12:0] == 13'h0001) ext <= cpu_d;               // $6001
            if (M187 && lo_wr && (cpu_a == 15'h5000 || cpu_a == 15'h6000)) ext <= cpu_d;   // $5000 y $6000
            if (M238 && lo_wr) ext <= (cpu_d[1:0] == 2'd0) ? 8'h00 : (cpu_d[1:0] == 2'd3) ? 8'h03 : 8'h02;
            if (M196 && w6000 && !cpu_a[12]) x2 <= {1'b1, 3'd0, cpu_d[3:0] | cpu_d[7:4]};   // $6000-$6FFF
            if (M45 && w6000 && !xa[3][6]) begin xa[i45] <= cpu_d; i45 <= i45 + 2'd1; end
            if (M114 && lo_wr && (cpu_a[13] || cpu_a[12])) x114 <= cpu_d;                    // $5000-$7FFF
            if (M121 && lo_wr && cpu_a[13:12] == 2'b01) begin                                // $5000-$5FFF
                e121[4] <= (cpu_d[1:0] == 2'd2) ? 8'h42 : (cpu_d[1:0] == 2'd3) ? 8'h00 : 8'h83;
                if (cpu_a[8] && cpu_a[7]) e121[3] <= cpu_d;                                   // $5180 pattern
            end
            if (M215 && lo_wr && cpu_a[13:0] == 14'h1000) x215a <= cpu_d;
            if (M215 && lo_wr && cpu_a[13:0] == 14'h1001) x215b <= cpu_d;
            if (M215 && lo_wr && cpu_a[13:0] == 14'h1007) x215c <= cpu_d;
        end else if (rom_wr) begin
            if (M114 && rs_in == 3'b010) s114 <= 1'b1;
            if (M114 && rs_in == 3'b100) s114 <= 1'b0;
            if (M121 && cpu_a[14:13] == 2'b00 && cpu_a[0]) begin : u121
                reg [31:0] u; reg [7:0] v6;
                if (cpu_a[1]) begin
                    u = upd121(cpu_d, e121[6], e121[0], e121[1], e121[2], e121[7][0]);
                    e121[0] <= u[7:0]; e121[1] <= u[15:8]; e121[2] <= u[23:16]; e121[5] <= {1'b0, u[30:24]};
                    e121[7] <= {7'd0, u[31]};
                end else begin
                    v6 = {2'b00, cpu_d[0], cpu_d[1], cpu_d[2], cpu_d[3], cpu_d[4], cpu_d[5]};
                    e121[6] <= v6;
                    if (!e121[7][0]) begin
                        u = upd121(e121[5], v6, e121[0], e121[1], e121[2], e121[7][0]);
                        e121[0] <= u[7:0]; e121[1] <= u[15:8]; e121[2] <= u[23:16]; e121[5] <= {1'b0, u[30:24]};
                        e121[7] <= {7'd0, u[31]};
                    end
                end
            end
            if (M176 && mode176[2:0]==3'd5) unrom176<=cpu_d[2:0];
            if (M219 && cpu_a[14:13]==0) case (cpu_a[1:0])
                2'd0: begin er0219<=8'd0; er1219<=cpu_d; end                  // $8000
                2'd2: begin er0219<=cpu_d; er1219<=8'd0; end                  // $8002
                2'd1: begin                                                   // $8001: aplica
                    if (er0219>=8'h23 && er0219<=8'h26)
                        pp219[8'h26-er0219] <= {2'd0, cpu_d[2], cpu_d[3], cpu_d[4], cpu_d[5]};
                    case (er1219)
                        8'h08,8'h0a,8'h0e,8'h12,8'h16,8'h1a,8'h1e: er2219 <= {cpu_d[3:0], 4'd0};
                        8'h09:       cc219[0] <= er2219 | ({1'b0, cpu_d[7:1]} & 8'h0e);
                        8'h0b:       cc219[1] <= er2219 | ({1'b0, cpu_d[7:1]} | 8'h01);
                        8'h0c,8'h0d: cc219[2] <= er2219 | ({1'b0, cpu_d[7:1]} & 8'h0e);
                        8'h0f:       cc219[3] <= er2219 | ({1'b0, cpu_d[7:1]} | 8'h01);
                        8'h10,8'h11: cc219[4] <= er2219 | ({1'b0, cpu_d[7:1]} & 8'h0f);
                        8'h14,8'h15: cc219[5] <= er2219 | ({1'b0, cpu_d[7:1]} & 8'h0f);
                        8'h18,8'h19: cc219[6] <= er2219 | ({1'b0, cpu_d[7:1]} & 8'h0f);
                        8'h1c,8'h1d: cc219[7] <= er2219 | ({1'b0, cpu_d[7:1]} & 8'h0f);
                        default: ;
                    endcase
                end
                default: ;
            endcase
            if (w182c001) begin irq_latch <= cpu_d; reload_tgl <= ~reload_tgl; end
            if (M44 && {cpu_a[14:13], cpu_a[0]} == 3'b011) ext <= (cpu_d[2:0] == 3'd7) ? 8'd6 : {5'd0, cpu_d[2:0]};
            if (M199 && rs_in == 3'b001 && sel3) x199[sel[1:0]] <= cpu_d;
            if (M198 && rs_in == 3'b001 && sel[2:1] == 2'b11) begin
                if (sel[0]) x198b <= cpu_d[5:0]; else x198a <= cpu_d[5:0];   // ($4F/$3F: dentro de 512 KB, 6 bits)
            end
            if (wcore) case (rs)
                3'b000: begin sel <= wd[2:0]; sel3 <= wd[3]; prg_mode <= wd[6]; chr_inv <= wd[7]; end
                3'b001: case (sel)
                            3'd0: r0 <= wd;
                            3'd1: r1 <= wd;
                            3'd2: r2 <= wd;
                            3'd3: r3 <= wd;
                            3'd4: r4 <= wd;
                            3'd5: r5 <= wd;
                            3'd6: r6 <= wd[5:0];
                            3'd7: r7 <= wd[5:0];
                        endcase
                3'b010: begin mir_h <= wd[0]; mir_s <= wd[1]; end
                3'b011: a001 <= wd[7:6];              // protección de PRG-RAM: ignorada (salvo 49/52)
                3'b100: irq_latch <= wd;
                3'b101: reload_tgl <= ~reload_tgl;
                3'b110: irq_en <= 1'b0;
                3'b111: irq_en <= 1'b1;
            endcase
        end
    end

    // 115: lectura de la protección en $5000-$5FFF. 187: $5000-$5FFF = $83. 238: $4020-$7FFF = registro.
    wire rd5   = romsel_n && cpu_rw && (cpu_a[14:12] == 3'b101);
    wire rd238 = M238 && romsel_n && cpu_rw && cpu_a[14] && (cpu_a[13:5] != 9'd0);
    assign cpu_dout = M115 ? prot : M187 ? 8'h83 : M121 ? e121[4] : ext;
    assign cpu_doe  = ((M115 || M187 || M121) && rd5) || rd238 ? 8'hFF : 8'h00;

    // ================================================================ PRG
    reg [5:0] mbank;                      // banco de 8 KB del MMC3
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: mbank = prg_mode ? 6'b111110 : r6;
            2'd1: mbank = r7;
            2'd2: mbank = prg_mode ? r6 : 6'b111110;
            2'd3: mbank = 6'b111111;
        endcase
    end

    // variantes con registro exterior
    wire [2:0] blk37 = ext[2:0];
    wire [5:0] bank37 = (blk37 <= 3'd2) ? {3'b000, mbank[2:0]} :
                        (blk37 == 3'd3) ? {3'b001, mbank[2:0]} :
                        (blk37 == 3'd7) ? {3'b100, mbank[2:0]} :
                                          {2'b01,  mbank[3:0]};
    wire [5:0] bank47  = {1'b0, ext[0], mbank[3:0]};
    wire [5:0] bank115 = !ext[7] ? mbank :
                         ext[5]  ? {1'b0, ext[3:1], cpu_a[14:13]} :      // 32 KB
                                   {1'b0, ext[3:0], cpu_a[13]};          // 16 KB repetido
    wire [2:0] b189    = ext[2:0] | ext[6:4];
    wire [5:0] bank189 = {1'b0, b189, cpu_a[14:13]};

    // fase 4: transformaciones del banco de 8 KB
    wire [2:0] blk44 = ext[2:0];
    wire [5:0] bank44  = (mbank & ((blk44 <= 3'd5) ? 6'h0F : 6'h1F)) | {blk44[1:0], 4'd0};
    wire [5:0] bank45  = (mbank & (6'h3F ^ xa[3][5:0])) | xa[1][5:0];
    wire [5:0] bank49  = ext[0] ? {ext[7:6], mbank[3:0]} : {2'b00, ext[5:4], cpu_a[14:13]};   // 32 KB del registro (sin bloque)
    wire [5:0] bank52  = ext[3] ? {ext[1:0], mbank[3:0]} : {ext[1], mbank[4:0]};
    wire [5:0] bank134 = {ext[1], mbank[4:0]};
    wire [5:0] bank187 = !ext[7] ? mbank :
                         !ext[5] ? {ext[4:0], cpu_a[13]} :                      // 16 KB repetido
                         ext[6]  ? {1'b0, ext[4:2], cpu_a[14:13]} :             // 32 KB (bancos de 8 KB / 4)
                                   {ext[4:1], cpu_a[14:13]};                    // 32 KB
    wire [5:0] bank196 = x2[7] ? {x2[3:0], cpu_a[14:13]} : mbank;
    wire [5:0] bank198 = (cpu_a[14:13] == 2'd0) ? x198a : (cpu_a[14:13] == 2'd1) ? x198b :
                         {5'b11111, cpu_a[13]};                                 // $C000/$E000: los dos últimos
    wire [5:0] bank199 = (cpu_a[14:13] == 2'd2) ? x199[0][5:0] : (cpu_a[14:13] == 2'd3) ? x199[1][5:0] : mbank;
    wire [5:0] bank205 = (mbank & ((ext[1:0] <= 2'd1) ? 6'h1F : 6'h0F)) | {ext[1:0], 4'd0};
    // 249: líneas de dirección cruzadas en la placa (con $5000 D1). Por debajo del banco $20: {p2,p1,p3,p4,p0};
    // desde $20, sobre p - $20: {p2,0,0,p3,p1,p0} (los bits que caen fuera de 512 KB se pierden).
    function [5:0] perm249p(input [5:0] p);
        perm249p = !p[5] ? {1'b0, p[2], p[1], p[3], p[4], p[0]} : {p[2], 2'b00, p[3], p[1], p[0]};
    endfunction
    wire [5:0] bank249 = ext[1] ? perm249p(mbank) : mbank;

    wire [5:0] mask176=6'h3f >> mode176[1:0];
    reg [5:0] bank176;
    always @(*) begin
        bank176=(mbank & mask176) | ({base176[4:0],1'b0} & ~mask176);
        case (mode176[2:0])
            3: bank176={base176[4:0],cpu_a[13]};
            4: bank176={base176[4:1],cpu_a[14:13]};
            5: bank176={base176[4:3],cpu_a[14] ? 3'd7 : unrom176,cpu_a[13]};
            default: ;
        endcase
    end
    wire [5:0] bank219=pp219[cpu_a[14:13]];
    // 114: 16 KiB mode (same bank at $8000 and $C000)
    wire [5:0] bank114 = x114[7] ? {1'b0, x114[3:0], cpu_a[13]} : mbank;
    // 121: OR $20 with $5180 D7; with a command active, $A000/$C000/$E000 come from the extra registers
    wire [5:0] or121 = {e121[3][7], 5'd0};
    wire [5:0] bank121 = ((e121[5][5:0] == 6'd0 || cpu_a[14:13] == 2'd0) ? {1'b0, mbank[4:0]} :
                          (cpu_a[14:13] == 2'd1) ? e121[2][5:0] : (cpu_a[14:13] == 2'd2) ? e121[1][5:0] : e121[0][5:0])
                         | or121;
    // 215: outer bank from $5001 D1-D0 (+ D4 in 128 KiB mode), or $5000 D7 = NROM-style 16/32 KiB bank
    wire [5:0] b215 = x215a[6] ? {x215b[1:0], x215b[4], x215a[2:0]} : {x215b[1:0], x215a[3:0]};
    wire [6:0] n215 = {b215, 1'b0} + (x215a[5] ? {5'd0, cpu_a[14:13]} : {6'd0, cpu_a[13]});
    wire [7:0] m215 = {1'b0, x215b[1:0], 5'd0} | (x215a[6] ? {4'd0, mbank[3:0]} | {3'd0, x215b[4], 4'd0} : {3'd0, mbank[4:0]});
    wire [5:0] bank215 = x215a[7] ? n215[5:0] : m215[5:0];
    wire [5:0] bank8 = M176 ? bank176 : M219 ? bank219 : M114 ? bank114 : M121 ? bank121 : M215 ? bank215 :
                       M37  ? bank37  :
                       M47  ? bank47  :
                       M115 ? bank115 :
                       M189 ? bank189 :
                       M44  ? bank44  : M45  ? bank45  : M49  ? bank49  : M52  ? bank52  :
                       M134 ? bank134 : M187 ? bank187 : M196 ? bank196 : M198 ? bank198 :
                       M199 ? bank199 : M205 ? bank205 : M249 ? bank249 : mbank;

    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);

    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]}    // PRG-RAM, banco 0
                                 : {bank8, cpu_a[12:10]};
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2 && !NO_RAM && (!G2 || a001[1]);
    assign prg_wr     = !cpu_rw && prg_ram_en && (!G2 || !a001[0]);

    // ================================================================ CHR
    wire [2:0] slot = ppu_a[12:10] ^ {chr_inv, 2'b00};
    reg  [7:0] bank1;
    always @(*) begin
        case (slot)
            3'd0: bank1 = {r0[7:1], 1'b0};
            3'd1: bank1 = {r0[7:1], 1'b1};
            3'd2: bank1 = {r1[7:1], 1'b0};
            3'd3: bank1 = {r1[7:1], 1'b1};
            3'd4: bank1 = r2;
            3'd5: bank1 = r3;
            3'd6: bank1 = r4;
            3'd7: bank1 = r5;
        endcase
    end

    // TQROM: CHR-RAM de 8 KB en CHR 0x7C000 (bancos 0x1F0-0x1F7), fuera de cualquier CHR-ROM
    // de TQROM (64 KB) y de la zona de 4 pantallas (0x7E000) y del menú (0x7F000).
    localparam [18:13] TQ_RAM_BANK = 6'b111110;
    wire tq_ram = TQROM && bank1[6];

    // ---- fase 4: transformaciones del banco de 1 KB
    function [7:0] perm249c(input [7:0] c);
        perm249c = {c[5], c[4], c[2], c[6], c[7], c[3], c[1], c[0]};
    endfunction
    // 45: máscara de CHR = $FF >> (15 - R2[3:0]) (0 si R2[3:0] < 8) y OR con R0 y R2[7:4] << 8
    wire [3:0] msk45 = xa[2][3:0];
    wire [7:0] chrmask45 = msk45[3] ? (8'hFF >> (4'd15 - msk45)) : 8'h00;
    // 197: bancos de 4 KB y 2 KB a partir de R0/R2/R3 (unidades de 2 KB)
    wire [8:0] c197_4k = ({1'b0, chr_inv ? r2 : r0} << 1) + {7'd0, ppu_a[11:10]};
    wire [8:0] c197_2k = ({1'b0, chr_inv ? r0 : (ppu_a[11] ? r3 : r2)} << 1) + {8'd0, ppu_a[10]};
    // 199: $0000-$0FFF = R0, X2, R1, X3 (1 KB cada uno, posición fija); los bancos < 8 son CHR-RAM
    reg [7:0] c199;
    always @(*) begin
        case (ppu_a[11:10])
            2'd0: c199 = r0; 2'd1: c199 = x199[2]; 2'd2: c199 = r1; default: c199 = x199[3];
        endcase
        if (ppu_a[12]) c199 = bank1;
    end
    // SH2 latch ranges: $xFD0-$xFD7 / $xFE8-$xFEF, both halves.
    // NESdev's old notes mention $xFE0; observed SH2 (Mesen2) uses $xFE8.
    // Capture during /RD; commit on synchronized read completion so the
    // triggering fetch still sees the old bank, including CPU $2007 reads.
    reg [1:0] latch165=0, rd165=3;
    reg active165=0;
    reg [2:0] hit165=0;
    always @(posedge clk) begin
        rd165<={rd165[0],ppu_rd_n};
        if (rst) begin latch165<=0; active165<=0; hit165<=0; end
        else if (M165) begin
            if (!rd165[1] && !active165) begin
                active165<=1;
                hit165<={!ppu_a[13] && (ppu_a[11:3]==9'h1fa || ppu_a[11:3]==9'h1fd),ppu_a[12],ppu_a[3]};
            end
            if (rd165[1] && active165) begin
                active165<=0;
                if (hit165[2]) latch165[hit165[1]]<=hit165[0];
            end
        end
    end
    wire [7:0] page165=ppu_a[12] ? (latch165[1] ? r4 : r2) : (latch165[0] ? r1 : r0);
    wire ram165=M165 && page165==0;
    wire ram176=M176 && mode176[5] && !cfg[7];
    wire [8:0] c176=mode176[6] ? {chr176[5:0],ppu_a[12:10]} :
                    mode176[4] ? {chr176[5:4],bank1[6:0]} : {chr176[5],bank1};
    reg [8:0] cv;          // banco final de 1 KB
    always @(*) begin
        cv = {1'b0, bank1};
        if (M165) cv={1'b0,page165[7:2],ppu_a[11:10]};
        if (M176) cv=c176;
        if (M219) cv={1'b0, cc219[ppu_a[12:10]]};
        // 121: CHR A18 for the half driven by the 2 KiB registers (R0/R1)
        if (M121) cv = {ppu_a[12] == chr_inv, bank1};
        // 215: $5001 D2 = CHR A18; with $5000 D6 (128 KiB mode) A17 = $5001 D5
        if (M215) cv = {x215b[2], x215a[6] ? {x215b[5], bank1[6:0]} : bank1};
        if (M12)  cv = {ppu_a[12] ? ext[4] : ext[0], bank1};
        if (M44)  cv = {1'b0, bank1 & ((blk44 <= 3'd5) ? 8'h7F : 8'hFF)} | {blk44[1:0], 7'd0};
        if (M45)  cv = {1'b0, (bank1 & chrmask45) | xa[0]} | {xa[2][4], 8'd0};
        if (M49)  cv = {ext[7:6], bank1[6:0]};
        if (M52)  cv = ext[6] ? {ext[5], ext[4], bank1[6:0]} : {ext[5], bank1};
        if (M134) cv = {ext[5], bank1};
        if (M187) cv = {ppu_a[12] == chr_inv, bank1};
        if (M197) cv = ppu_a[12] ? c197_2k : c197_4k;
        if (M199) cv = {1'b0, c199};
        if (M205) cv = {ext[1], ext[0] | (bank1[7] & !ext[1]), bank1[6:0]};   // bloques 0-3
        if (M249) cv = {1'b0, ext[1] ? perm249c(bank1) : bank1};
    end
    // CHR-RAM dentro de la CHR-ROM (fuera de la máscara del OS, en la misma zona que el TQROM): 74 bancos 8-9,
    // 191 bancos con D7, 199 bancos 0-7 (8 KB)
    wire ram74  = M74  && (bank1[7:1] == 7'b0000100);
    wire ram191 = M191 && bank1[7];
    wire ram199 = M199 && (c199[7:3] == 5'd0);
    wire ram192 = M192 && (bank1[7:2] == 6'b000010);           // banks $08-$0B
    wire ram194 = M194 && (bank1[7:1] == 7'd0);                // banks $00-$01
    wire ram195 = M195 && (bank1[7:2] == 6'd0);                // banks $00-$03
    wire xram   = ram74 || ram191 || ram199 || ram165 || ram176 || ram192 || ram194 || ram195;
    wire [2:0] xram_pg = ram165 ? {1'b0,ppu_a[11:10]} : ram176 ? c176[2:0] : ram199 ? c199[2:0] :
                         (ram192 || ram195) ? {1'b0, bank1[1:0]} : {2'b00, bank1[0]};

    wire [8:0] bank_ext = M37 ? {1'b0, bank1[7] | ext[2], bank1[6:0]} :
                          M47 ? {1'b0, ext[0], bank1[6:0]} :
                          M115 ? {ext_chr, bank1} :
                                 cv;
    // 245 con CHR-RAM: 8 KB con las mitades cambiadas según la inversión CHR
    wire [2:0] cram = (G1 && map_id == 8'd245) ? {ppu_a[12] ^ chr_inv, ppu_a[11:10]} : bank1[2:0];

    assign chr_a     = tq_ram ? {TQ_RAM_BANK, bank1[2:0]} :
                       xram   ? {TQ_RAM_BANK, xram_pg} :
                       cfg[7] ? {6'd0, M176 ? c176[2:0] : cram}              // CHR-RAM: 8 KB
                              : bank_ext;                 // CHR-ROM: hasta 256 KB (512 KB en 115 y fase 4)
    assign chr_raw   = tq_ram || xram;
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = (cfg[7] || tq_ram || xram) && !ppu_wr_n && !ppu_a[13];

    assign ciram_en  = ppu_a[13];
    // TxSROM (118): la salida CHR A17 del MMC3 va a CIRAM A10. Para $2000-$2FFF (A12 = 0) el MMC3
    // calcula el banco igual que para $0000-$0FFF: su bit 7 elige la página de nametable, y el
    // registro $A000 no tiene efecto. Se calcula en cada acceso, como el chip.
    assign ciram_a10 = TXSROM ? bank1[7] :
                       (M199 && mir_s) ? mir_h :                     // 199: pantalla A (2) o B (3)
                       (mir_h ? ppu_a[11] : ppu_a[10]);

    // ================================================================ IRQ (dominio clk)
    // Filtro de A12 (ruido + subidas cortas de los sprites): ver a12_filter.v.
    // Umbral: A12 baja durante al menos 4 bajadas de M2 (~3 ciclos de CPU, >= 9 puntos de PPU).
    // Con 3 bajadas se aceptaban huecos de 7-8 puntos (sprites 8x16 de las dos tablas) y Armadillo
    // (118) recibía ~40 pulsos de más; Mesen2 exige > 10 puntos y las pruebas de blargg pasan.
    wire a12_clk, m2_fall_unused;
    a12_filter #(.LOW_M2(4), .W(3)) flt (
        .clk(clk), .m2(m2), .a12(ppu_a[12]), .a12_clk(a12_clk), .m2_fall(m2_fall_unused));

    reg [2:0] rel_s  = 3'd0;
    reg [1:0] en_s   = 2'd0;
    reg [7:0] counter = 8'd0;
    reg       reload  = 1'b0;
    reg       pending = 1'b0;
    wire en_now   = en_s[1];

    wire [7:0] next = (counter == 8'd0 || reload) ? irq_latch : counter - 8'd1;
    // MMC3A (114): no IRQ when the counter is reloaded with 0 unless it was a $C001 reload
    wire       fire = (next == 8'd0) && (!M114 || counter != 8'd0 || reload);

    always @(posedge clk) begin
        rel_s  <= {rel_s[1:0], reload_tgl};
        en_s   <= {en_s[0], irq_en};

        if (rst) begin
            counter <= 8'd0;
            reload  <= 1'b0;
            pending <= 1'b0;
        end else begin
            if (rel_s[2] != rel_s[1]) begin          // escritura en $C001
                counter <= 8'd0;
                reload  <= 1'b1;
            end else if (a12_clk) begin
                counter <= next;
                reload  <= 1'b0;
                if (fire && en_now) pending <= 1'b1;
            end
            if (!en_now) pending <= 1'b0;            // $E000: desactiva y reconoce
        end
    end

    assign irq = pending;

endmodule
