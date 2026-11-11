`timescale 1ns/1ps
// mapper_latch.v — Mappers de un solo registro (fase 4, lote 1). Implementación propia (clean room).
// Una instancia para todos: solo hay un mapper activo a la vez, así que comparten el registro de dato
// (d), el de dirección (a, para los multicarts que guardan las líneas de dirección) y los ocho registros
// del 246. Cada número elige qué escritura guarda y cómo se forman los bancos.
//
//   13  CPROM: $8000-$FFFF D1-D0 = CHR-RAM de 4 KB en $1000 (16 KB de CHR-RAM); $0000 fijo al banco 0.
//   15  K-1029: $8000-$FFFF, A1-A0 = modo (0 NROM-256, 1 UNROM, 2 NROM-64, 3 NROM-128), D5-D0 = PRG A19-A14,
//       D7 = PRG A13 (solo modo 2), D6 = mirroring (1 H). CHR-RAM protegida contra escritura en modos 0 y 3.
//   38  Bit Corp PCI556: $7000-$7FFF D1-D0 = PRG 32 KB, D3-D2 = CHR 8 KB.
//   57  GK 6-in-1: $8000 (A11 = 0) y $8800 (A11 = 1). CHR 8 KB = {R0 D6, (R0 | R1) D2-D0}; R1 D4 = 32 KB
//       (R1 D7-D6 sin el bit bajo) o 16 KB repetido (R1 D7-D5); R1 D3 = mirroring (1 H).
//   58/213: dirección A2-A0 = PRG, A6 = 16 KB repetido (si no, 32 KB con A2-A1), A5-A3 = CHR 8 KB, A7 = mirroring (1 H).
//   61  dirección: PRG = {A3-A0, A5}, A4 = 16 KB repetido (si no, 32 KB), A7 = mirroring (1 H).
//   94  UN1ROM: D4-D2 = PRG 16 KB en $8000; $C000 fijo al último.
//   97  Irem TAM-S1: $8000-$BFFF; $8000 fijo al último; D4-D0 = PRG 16 KB en $C000; D7 = mirroring (0 H, 1 V).
//   101 Jaleco: $6000-$7FFF = CHR 8 KB.
//   107 Magic Dragon: PRG 32 KB = D7-D1, CHR 8 KB = D.
//   145 Sachen SA-72007: escritura en $4100-$7FFF con A8 = 1: D7 = CHR 8 KB.
//   149 Sachen SA-0036: D7 = CHR 8 KB.
//   177 Hengedianzi: D4-D0 = PRG 32 KB, D5 = mirroring (1 H). CHR-RAM, PRG-RAM.
//   200 dirección A2-A0 = PRG 16 KB repetido y CHR 8 KB, A3 = mirroring (1 V).
//   201 dirección A1-A0 = PRG 32 KB, A2-A0 = CHR 8 KB.
//   202 dirección A3-A1 = PRG 16 KB y CHR 8 KB; A3 y A0 a 1 = 32 KB (bancos n y n + 1); A0 = mirroring (1 H).
//   203 D7-D2 = PRG 16 KB repetido, D1-D0 = CHR 8 KB.
//   212 dirección: escritura en $C000-$FFFF = 32 KB (A2-A1), si no 16 KB repetido (A2-A0); A2-A0 = CHR 8 KB;
//       A3 = mirroring (1 H). Lectura de $6000-$7FFF con A4 = 0: D7 = 1 (protección; el resto, bus abierto).
//   214 dirección A3-A2 = PRG 16 KB repetido, A1-A0 = CHR 8 KB.
//   216 dirección A0 = PRG 32 KB, A3-A1 = CHR 8 KB.
//   227 dirección (1200-in-1): PRG = {A8, A6-A2}; A7 = NROM (A0: 32 KB o 16 KB repetido) o UNROM (A9 = último
//       banco del grupo de 8 o el primero); A1 = mirroring (1 H). CHR-RAM.
//   229 dirección A4-A0: 0 o 1 = 32 KB del banco 0; si no 16 KB repetido; A7-A0 = CHR 8 KB; A5 = mirroring (1 H).
//   231 dirección: PRG 16 KB $8000 = {A4-A1, 0}, $C000 = {A4-A1, A5}; A7 = mirroring (1 H).
//   240 $4020-$5FFF: D7-D4 = PRG 32 KB, D3-D0 = CHR 8 KB. PRG-RAM.
//   242 dirección (Waixing): A6-A3 = PRG 32 KB, A1 = mirroring (1 H); PRG-RAM. Los modos UNROM/NROM-128 que NESdev
//       describe son de los multicarts; la variante Waixing (la de los juegos de la colección) no los tiene: con
//       ellos Wai Xing Zhan Shi se quedaba en verde (banco, 2026-11-08).
//   244 C&E Decathlon: D3 = 1: CHR 8 KB por tabla (D6-D4 elige la permutación de D2-D0); D3 = 0: PRG 32 KB por
//       tabla (D5-D4 elige la permutación de D1-D0). Tablas = permutaciones de bits de la placa.
//   246 Feng Shen Bang: $6000-$6003 = PRG 8 KB en $8000/$A000/$C000/$E000, $6004-$6007 = CHR 2 KB; $6800-$6FFF
//       RAM. Al encender, $E000 = $FF (último).
//
//
// Lote 3 (2026-11-08):
//   28  Action 53: $5000-$5FFF D7/D0 = registro (0 CHR, 1 PRG interno, 2 modo, 3 PRG externo); dato en $8000-$FFFF.
//       Modo: D1-D0 mirroring (0/1 pantalla según el bit de mirroring de R0/R1/R2, 2 V, 3 H), D2 ventana fija,
//       D3 = bancos de 16 KB (si no 32 KB), D5-D4 = tamaño del juego (máscara del banco interno). CHR-RAM 32 KB.
//   30  UNROM 512: D4-D0 = PRG 16 KB en $8000 ($C000 último), D6-D5 = CHR-RAM de 8 KB (32 KB), D7 = pantalla A/B si la
//       cabecera pide pantalla única (bits 3 y 0 = 1 y 0). Con el bit de pila (placa con flash) el registro solo está
//       en $C000-$FFFF ($8000-$BFFF graba la flash, que aquí no se emula).
//   31  NSF (INL): $5000-$5FFF, A2-A0 = ventana de 4 KB de $8000-$FFFF (al encender, la de $F000 = $FF).
//   51  BMC 11-in-1: banco (4 bits) en $8000-$FFFF, modo en $6000-$7FFF (D4, D1) y $C000-$DFFF (D4); ROM en $6000.
//   60  4-in-1 por reset: cada reset de la consola (M2 parado > 2,56 us sin volver al menú, modo de reset largo del
//       OS) pasa al juego siguiente: PRG 16 KB repetido y CHR 8 KB = contador.
//   77  Irem LROG017: D3-D0 = PRG 32 KB, D7-D4 = CHR-ROM 2 KB en $0000; $0800-$1FFF = 6 KB de CHR-RAM (zona libre de la
//       SRAM CHR, como el TQROM); 4 pantallas por la cabecera (top).
//   96  Oeka Kids: D1-D0 = PRG 32 KB, D2 = mitad de la CHR; CHR 4 KB en $0000 = {D2, A9-A8 de la última entrada de la
//       PPU en $2000-$2FFF}, $1000 = {D2, 11}. El cambio de A9-A8 se ve con clk (A13-A12 y A9-A8 sincronizados).
//   103 Doki Doki Panic (FDS): $8000-$FFFF = últimos 32 KB; $6000 = RAM o, con $F000 D4, ROM de 8 KB = $8000 D3-D0;
//       $B800-$D7FF = 2.ª página de RAM (las escrituras van siempre a la RAM); $E000 D3 = mirroring (1 H).
//   108 escrituras con A12 = 0 y en $F000-$FFFF: PRG 8 KB en $6000 y CHR 8 KB = dato; resto: CHR = D0.
//       $8000-$FFFF = últimos 32 KB.
//   164 Waixing: $5000 = PRG 32 KB bits 3-0, $5100 = bits 7-4 (al encender $0F).
//   168 Racermate: $8000-$BFFF: D7-D6 = PRG 16 KB en $8000, D3-D0 = CHR-RAM 4 KB en $1000 (64 KB); $C000-$FFFF reconoce
//       la IRQ, que salta cada 1024 ciclos de CPU.
//   171 Kaiser 7058: $F000 = CHR 4 KB en $0000, $F080 = CHR 4 KB en $1000.
//   175 Kaiser 7022: $8000 D2 = mirroring (1 H), $A000 = registro; al LEER $FFFC (vector de reset) se aplica: PRG 16 KB
//       repetido y CHR 8 KB.
//   178 Waixing: $4800-$4FFF, A1-A0 = registro. R0 D0 mirroring, D1/D2 modo (UNROM/NROM-128/NROM-256), R1 = banco
//       pequeño, R2 = grande, R3 = página de PRG-RAM de 8 KB (32 KB).
//   188 Bandai Karaoke: D4 = 1: PRG 16 KB = D2-D0; si no, el banco 8 + D2-D0 (con PRG de 256 KB) o nada; $C000 = 7;
//       D5 = mirroring (1 H). Lectura de $6000-$7FFF: D2-D0 = micrófono y sus botones (sin pulsar; ver abajo).
//       Sin casete (PRG < 256 KB) los bancos externos son bus abierto (en n8_top.v).
//   190 Magic Kid Googoo: $8000-$9FFF = PRG 16 KB D2-D0, $C000-$DFFF = 8 + D2-D0 (en $8000); $C000 fijo al 0;
//       $A000-$BFFF y $E000-$FFFF: A1-A0 = CHR 2 KB. Al encender, CHR lineal (el logo se dibuja antes de escribirla).
//       PRG-RAM de 8 KB en $6000 (el juego guarda ahí datos del logo).
//   221 NTDEC N625092: escritura en $8000-$BFFF guarda la dirección (modo: A0 mirroring, A1 = 32/16 KB, A8 = UNROM,
//       A7-A2 = banco exterior); $C000-$FFFF: A2-A0 = banco interior.
//
// Fuentes de hechos: descripciones públicas de NESdev Wiki y la implementación de Mesen2 (referencia del banco),
// leída solo para entender direcciones y bits; nada copiado. Donde no coinciden se sigue la descripción del
// hardware de NESdev (15: A13/A14 en los modos 0, 1 y 3; 97) y se anota en la documentación.

module mapper_latch (
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
    output wire        chr_raw,    // 1 = chr_a sin la máscara del OS (CHR-RAM extra del 77)
    output wire [7:0]  cpu_dout,
    output wire [7:0]  cpu_doe
);

    // ------------------------------------------------------------ registros
    reg [7:0]  d;          // dato del último registro
    reg [14:0] a;          // dirección del último registro (A14-A0)
    reg [7:0]  d2;         // segundo registro (57)
    reg [7:0]  r246 [0:7];   // 246; 31 (ocho ventanas de 4 KB)
    reg [7:0]  r [0:3];      // 28, 51, 103, 108, 171, 175, 178, 190, 221: registros del lote 3
    reg [1:0]  sel28;        // 28: registro elegido
    reg        mb28;         // 28: bit de mirroring de pantalla única
    reg [7:0]  p108, b164;   // al encender: $FF y $0F
    reg [7:0]  o28;          // 28: banco exterior (al encender $FF: el último bloque)
    integer i;
    initial begin
        d = 0; a = 0; d2 = 0; for (i = 0; i < 8; i = i + 1) r246[i] = 0; r246[3] = 8'hFF; r246[7] = 8'hFF;
        for (i = 0; i < 4; i = i + 1) r[i] = 0;
        sel28 = 0; mb28 = 0; p108 = 8'hFF; b164 = 8'h0F; o28 = 8'hFF;
    end

    wire wr8  = !romsel_n && !cpu_rw;                                   // $8000-$FFFF
    wire wr6  = romsel_n && !cpu_rw && (cpu_a[14:13] == 2'b11);         // $6000-$7FFF
    wire wr45 = romsel_n && !cpu_rw && (cpu_a[14:13] == 2'b10) && (cpu_a[12:5] != 8'd0);   // $4020-$5FFF

    reg we;                // este mapper guarda la escritura actual en d/a
    always @(*) begin
        case (map_id)
            8'd38:  we = wr6 && (cpu_a[12] == 1'b1);                    // $7000-$7FFF
            8'd101: we = wr6;
            8'd145: we = romsel_n && !cpu_rw && cpu_a[14] && cpu_a[8];  // $4100-$7FFF con A8
            8'd240: we = wr45;
            8'd97:  we = wr8 && !cpu_a[14];                             // $8000-$BFFF
            8'd57:  we = wr8 && !cpu_a[11];                             // R0 en $8000
            8'd190: we = 1'b0;
            8'd221: we = wr8 && !cpu_a[14];                             // modo en $8000-$BFFF
            8'd168: we = wr8 && !cpu_a[14];                             // bancos en $8000-$BFFF ($C000: IRQ)
            8'd246, 8'd28, 8'd31, 8'd51, 8'd103, 8'd108, 8'd164, 8'd171, 8'd175, 8'd178: we = 1'b0;
            8'd30:  we = wr8 && (cpu_a[14] || !cfg[1]);   // con pila (flash), $8000-$BFFF graba la flash: registro en $C000
            default: we = wr8;
        endcase
    end

    always @(negedge m2) begin
        if (rst) begin
            d <= 0; a <= 0; d2 <= 0;
            for (i = 0; i < 8; i = i + 1) r246[i] <= 0;
            r246[3] <= 8'hFF; r246[7] <= 8'hFF;
            for (i = 0; i < 4; i = i + 1) r[i] <= 0;
            sel28 <= 0; mb28 <= 0; p108 <= 8'hFF; b164 <= 8'h0F; o28 <= 8'hFF;
        end else begin
            if (we) begin d <= cpu_d; a <= cpu_a; end
            if (map_id == 8'd57 && wr8 && cpu_a[11]) d2 <= cpu_d;       // R1 en $8800
            if (map_id == 8'd246 && wr6 && cpu_a[12:11] == 2'b00) r246[cpu_a[2:0]] <= cpu_d;   // $6000-$67FF
            // ---- lote 3
            case (map_id)
                8'd28: begin
                    if (wr45 && cpu_a[12]) sel28 <= {cpu_d[7], cpu_d[0]};                  // $5000-$5FFF
                    if (wr8) begin
                        if (sel28 == 2'd3) o28 <= cpu_d; else r[sel28] <= cpu_d;
                        if (sel28[1] == 1'b0) mb28 <= cpu_d[4];
                        else if (sel28 == 2'd2) mb28 <= cpu_d[0];
                    end
                end
                8'd31: if (wr45 && cpu_a[12]) r246[cpu_a[2:0]] <= cpu_d;                   // $5000-$5FFF
                8'd51: begin
                    if (wr6) r[1] <= {6'd0, cpu_d[4], cpu_d[1]};                            // modo
                    if (wr8) begin
                        r[0] <= {4'd0, cpu_d[3:0]};                                       // banco
                        if (cpu_a[14:13] == 2'b10) r[1] <= {6'd0, cpu_d[4], r[1][0]};       // $C000-$DFFF
                    end
                end
                8'd103: if (wr8) case (cpu_a[14:12])
                    3'b000: r[0] <= {4'd0, cpu_d[3:0]};                                   // $8000: ROM de $6000
                    3'b110: r[1][1] <= cpu_d[3];                                          // $E000: mirroring
                    3'b111: r[1][0] <= cpu_d[4];                                          // $F000: RAM apagada
                    default: ;
                endcase
                8'd108: if (wr8) begin                                                   // A12 = 0 o $F000-$FFFF
                    if (!cpu_a[12] || cpu_a[14:12] == 3'b111) begin p108 <= cpu_d; r[1] <= cpu_d; end
                    else r[1] <= {7'd0, cpu_d[0]};
                end
                8'd164: if (wr45 && cpu_a[12] && cpu_a[9:8] == 2'b00) begin              // ($addr & $7300)
                    if (cpu_a[8] == 1'b0) b164[3:0] <= cpu_d[3:0];
                end else if (wr45 && cpu_a[12] && cpu_a[9:8] == 2'b01) b164[7:4] <= cpu_d[3:0];
                8'd171: if (wr8 && cpu_a[14:12] == 3'b111) begin
                    if (cpu_a[7]) r[1] <= cpu_d; else r[0] <= cpu_d;
                end
                8'd175: begin
                    if (wr8 && cpu_a == 15'h0000) r[2] <= {7'd0, cpu_d[2]};               // $8000: mirroring
                    if (wr8 && cpu_a == 15'h2000) r[0] <= {4'd0, cpu_d[3:0]};             // $A000
                    if (!romsel_n && cpu_rw && cpu_a == 15'h7FFC) r[1] <= r[0];            // lectura de $FFFC
                end
                8'd178: if (romsel_n && !cpu_rw && cpu_a[14:11] == 4'b1001) r[cpu_a[1:0]] <= cpu_d;   // $4800-$4FFF
                8'd221: if (wr8 && cpu_a[14]) r[0] <= {5'd0, cpu_a[2:0]};                // $C000-$FFFF
                8'd190: if (wr8) begin
                    if (cpu_a[14:13] == 2'b00)      d <= {5'd0, cpu_d[2:0]};               // $8000-$9FFF
                    else if (cpu_a[14:13] == 2'b10) d <= {4'd0, 1'b1, cpu_d[2:0]};         // $C000-$DFFF
                    else r[cpu_a[1:0]] <= cpu_d ^ {6'd0, cpu_a[1:0]};                     // $A000/$E000: CHR 2 KB
                end
                default: ;
            endcase
        end
    end

    // ---- 60: contador de resets de la consola (clk). M2 parado más de 128 ciclos de clk (2,56 us) y vuelta.
    reg [1:0] m2s = 2'b00;
    reg [7:0] idle60 = 8'd0;
    reg       parado = 1'b0;
    reg [1:0] cnt60 = 2'd0;
    always @(posedge clk) begin
        m2s <= {m2s[0], m2};
        if (rst) begin idle60 <= 0; parado <= 0; cnt60 <= 0; end
        else if (m2s[1] != m2s[0]) begin
            idle60 <= 8'd0;
            if (parado) cnt60 <= cnt60 + 2'd1;
            parado <= 1'b0;
        end else if (idle60 != 8'hFF) begin
            idle60 <= idle60 + 8'd1;
            if (idle60 == 8'd128) parado <= 1'b1;
        end
    end

    // ---- 96: A9-A8 de la última entrada de la PPU en $2000-$2FFF (clk, señales sincronizadas)
    reg [3:0] pa_s1 = 4'd0, pa_s2 = 4'd0;      // {A13, A12, A9, A8}
    reg       en_nt = 1'b0;
    reg [1:0] inner96 = 2'd0;
    always @(posedge clk) begin
        pa_s1 <= {ppu_a[13:12], ppu_a[9:8]};
        pa_s2 <= pa_s1;
        if (rst) begin en_nt <= 1'b0; inner96 <= 2'd0; end
        else if (pa_s1 == pa_s2) begin                                    // dirección estable dos muestras
            if (pa_s2[3:2] == 2'b10) begin
                if (!en_nt) inner96 <= pa_s2[1:0];
                en_nt <= 1'b1;
            end else en_nt <= 1'b0;
        end
    end

    // ---- 168: IRQ cada 1024 ciclos de CPU; $C000-$FFFF la reconoce y reinicia la cuenta
    reg [9:0] c168 = 10'd0;
    reg       irq168 = 1'b0;
    always @(negedge m2) begin
        if (rst) begin c168 <= 10'd0; irq168 <= 1'b0; end
        else if (map_id == 8'd168 && wr8 && cpu_a[14]) begin c168 <= 10'd1023; irq168 <= 1'b0; end   // el ciclo de la escritura cuenta
        else begin
            c168 <= c168 - 10'd1;
            if (map_id == 8'd168 && c168 == 10'd1) irq168 <= 1'b1;
        end
    end

    // ------------------------------------------------------------ bancos
    // b8: banco de PRG de 8 KB para la ventana actual (cpu_a[14:13]); c1: banco de CHR de 1 KB para ppu_a[12:10].
    // mir: 0 vertical, 1 horizontal, 2 pantalla A, 3 pantalla B. cwp: CHR-RAM protegida. ram: PRG-RAM.
    wire [1:0] w  = cpu_a[14:13];
    wire [2:0] s  = ppu_a[12:10];
    wire       hv = cfg[0] ? 1'b0 : 1'b1;                                // mirroring de cabecera (1 = H)

    function [2:0] perm_chr(input [2:0] m, input [2:0] v);               // 244: permutaciones de la placa
        case (m)
            3'd0: perm_chr = v;
            3'd1: perm_chr = {v[2], v[0], v[1]};
            3'd2: perm_chr = {v[1], v[2], v[0]};
            3'd3: perm_chr = {v[0], v[2], v[1]};
            3'd4: perm_chr = {v[0], v[1], v[2]};
            3'd5: perm_chr = {v[1], v[0], v[2]};
            default: perm_chr = ~v;
        endcase
    endfunction
    reg [1:0] p244; reg [2:0] c244;
    always @(negedge m2) begin
        if (rst) begin p244 <= 0; c244 <= 0; end
        else if (map_id == 8'd244 && wr8) begin
            if (cpu_d[3]) c244 <= perm_chr(cpu_d[6:4], cpu_d[2:0]);
            else          p244 <= (cpu_d[5] ? {cpu_d[0], cpu_d[1]} : cpu_d[1:0]) ^ {2{cpu_d[4]}};
        end
    end

    wire [5:0] pb227 = {a[8], a[6:2]};          // 227: banco de 16 KB
    // 28 (Action 53): banco de 16 KB de la ventana (w[1]) según el modo
    reg  [8:0] oa53; reg [3:0] ia53;
    always @(*) begin
        case (r[2][5:4])
            2'd0: begin oa53 = 9'h1FE; ia53 = 4'h1; end
            2'd1: begin oa53 = 9'h1FC; ia53 = 4'h3; end
            2'd2: begin oa53 = 9'h1F8; ia53 = 4'h7; end
            default: begin oa53 = 9'h1F0; ia53 = 4'hF; end
        endcase
    end
    wire [8:0] o53     = {o28, 1'b0};
    wire [8:0] pg53_32 = (o53 & oa53) | {5'd0, {r[1][2:0], w[1]} & ia53};
    wire [8:0] pg53_16 = (w[1] == !r[2][2]) ? ((o53 & oa53) | {5'd0, r[1][3:0] & ia53})
                                             : ((o53 & 9'h1FE) | {8'd0, r[2][2]});
    wire [4:0] a53_bank = r[2][3] ? pg53_16[4:0] : pg53_32[4:0];
    // 178 (Waixing): banco de 16 KB
    wire [4:0] base178 = {r[2][1:0], r[1][2:0]};
    wire [4:0] b178 = r[0][1] ? (w[1] ? (r[0][2] ? {r[2][1:0], 2'b11, r[1][0]} : {r[2][1:0], 3'b111}) : base178)
                              : (r[0][2] ? base178 : base178 + {4'd0, w[1]});
    reg [6:0] b8;
    reg [8:0] c1;
    reg [1:0] mir;
    reg       cwp, ram;
    always @(*) begin
        b8  = {5'd0, w};              // 32 KB fijos
        c1  = {6'd0, s};              // 8 KB fijos
        mir = {1'b0, hv};
        cwp = 1'b0;
        ram = 1'b0;
        case (map_id)
            8'd13: c1 = s[2] ? {5'd0, d[1:0], s[1:0]} : {7'd0, s[1:0]};
            8'd15: begin
                case (a[1:0])
                    2'd0: b8 = {d[5:1], w};                              // NROM-256
                    2'd1: b8 = w[1] ? {d[5:3], 3'b111, w[0]} : {d[5:0], w[0]};   // UNROM
                    2'd2: b8 = {d[5:0], d[7]};                           // NROM-64
                    2'd3: b8 = {d[5:0], w[0]};                           // NROM-128
                endcase
                mir = {1'b0, d[6]};
                cwp = (a[1:0] == 2'd0) || (a[1:0] == 2'd3);
            end
            8'd38:  begin b8 = {3'd0, d[1:0], w}; c1 = {4'd0, d[3:2], s}; end
            8'd57:  begin
                b8 = d2[4] ? {3'd0, d2[7:6], w} : {3'd0, d2[7:5], w[0]};
                c1 = {2'd0, d[6], d[2:0] | d2[2:0], s};
                mir = {1'b0, d2[3]};
            end
            8'd58, 8'd213: begin
                b8 = a[6] ? {3'd0, a[2:0], w[0]} : {3'd0, a[2:1], w};
                c1 = {3'd0, a[5:3], s};
                mir = {1'b0, a[7]};
            end
            8'd61:  begin
                b8 = a[4] ? {1'b0, a[3:0], a[5], w[0]} : {1'b0, a[3:0], w};
                mir = {1'b0, a[7]};
            end
            8'd94:  b8 = w[1] ? {6'b111111, w[0]} : {3'd0, d[4:2], w[0]};
            8'd97:  begin
                b8 = w[1] ? {1'b0, d[4:0], w[0]} : {6'b111111, w[0]};
                mir = {1'b0, !d[7]};
            end
            8'd101: c1 = {d[5:0], s};
            8'd107: begin b8 = {d[5:1], w}; c1 = {d[5:0], s}; end
            8'd145, 8'd149: c1 = {5'd0, d[7], s};
            8'd177: begin b8 = {d[4:0], w}; mir = {1'b0, d[5]}; ram = 1'b1; end
            8'd200: begin b8 = {3'd0, a[2:0], w[0]}; c1 = {3'd0, a[2:0], s}; mir = {1'b0, !a[3]}; end
            8'd201: begin b8 = {3'd0, a[1:0], w}; c1 = {3'd0, a[2:0], s}; end
            8'd202: begin
                b8 = (a[3] && a[0]) ? {3'd0, a[3:1] + {2'd0, w[1]}, w[0]} : {3'd0, a[3:1], w[0]};
                c1 = {3'd0, a[3:1], s};
                mir = {1'b0, a[0]};
            end
            8'd203: begin b8 = {d[7:2], w[0]}; c1 = {4'd0, d[1:0], s}; end
            8'd212: begin
                b8 = a[14] ? {3'd0, a[2:1], w} : {3'd0, a[2:0], w[0]};
                c1 = {3'd0, a[2:0], s};
                mir = {1'b0, a[3]};
            end
            8'd214: begin b8 = {4'd0, a[3:2], w[0]}; c1 = {4'd0, a[1:0], s}; end
            8'd216: begin b8 = {4'd0, a[0], w}; c1 = {3'd0, a[3:1], s}; end
            8'd227: begin
                if (a[7]) b8 = a[0] ? {pb227[5:1], w} : {pb227, w[0]};                       // NROM
                else if (!w[1]) b8 = {a[0] ? {pb227[5:1], 1'b0} : pb227, w[0]};              // UNROM, $8000
                else b8 = {a[9] ? (pb227 | 6'b000111) : (pb227 & 6'b111000), w[0]};          // UNROM, $C000
                mir = {1'b0, a[1]};
            end
            8'd229: begin
                b8 = (a[4:1] == 4'd0) ? {5'd0, w} : {1'b0, a[4:0], w[0]};
                c1 = {a[5:0], s};
                mir = {1'b0, a[5]};
            end
            8'd231: begin
                b8 = w[1] ? {1'b0, a[4:1], a[5], w[0]} : {1'b0, a[4:1], 1'b0, w[0]};
                mir = {1'b0, a[7]};
            end
            8'd240: begin b8 = {1'b0, d[7:4], w}; c1 = {2'd0, d[3:0], s}; ram = 1'b1; end
            8'd242: begin                                                // Waixing: 32 KB = A6-A3, PRG-RAM
                b8 = {1'b0, a[6:3], w};
                mir = {1'b0, a[1]};
                ram = 1'b1;
            end
            8'd244: begin b8 = {3'd0, p244, w}; c1 = {3'd0, c244, s}; end
            8'd246: begin
                b8 = r246[{1'b0, w}][6:0];
                c1 = {r246[{1'b1, s[2:1]}], s[0]};
                ram = 1'b1;
            end
            // ---------------- lote 3
            8'd28: begin
                b8 = {1'b0, a53_bank, w[0]};
                mir = r[2][1] ? {1'b0, r[2][0]} : {1'b1, mb28};
            end
            8'd30: begin
                b8 = w[1] ? {6'b111111, w[0]} : {1'b0, d[4:0], w[0]};
                if (cfg[3] && !cfg[0]) mir = {1'b1, d[7]};                        // pantalla única A/B
            end
            8'd51: begin
                b8 = r[1][0] ? {1'b0, r[0][3:0], w} :
                     w[1] ? {1'b0, r[0][3:2], 3'b111, w[0]} : {1'b0, r[0][3:0], r[1][1], w[0]};
                mir = {1'b0, r[1][1:0] == 2'b11};
            end
            8'd60: begin b8 = {4'd0, cnt60, w[0]}; c1 = {4'd0, cnt60, s}; end
            8'd77: begin b8 = {1'b0, d[3:0], w}; c1 = {4'd0, d[7:4], s[0]}; end
            8'd96: begin b8 = {3'd0, d[1:0], w}; c1 = {4'd0, d[2], s[2] ? 2'b11 : inner96, s[1:0]}; end
            8'd103: begin b8 = {5'b11111, w}; mir = {1'b0, r[1][1]}; end         // últimos 32 KB
            8'd108: begin b8 = {5'b11111, w}; c1 = {r[1][5:0], s}; end
            8'd164: b8 = {b164[4:0], w};
            8'd168: b8 = w[1] ? {6'b111111, w[0]} : {4'd0, d[7:6], w[0]};
            8'd171: c1 = {r[{1'b0, s[2]}][6:0], s[1:0]};
            8'd175: begin b8 = {2'b0, r[1][3:0], w[0]}; c1 = {2'd0, r[1][3:0], s}; mir = {1'b0, r[2][0]}; end
            8'd178: begin b8 = {1'b0, b178, w[0]}; mir = {1'b0, r[0][0]}; ram = 1'b1; end
            8'd188: begin
                b8 = w[1] ? {3'd0, 3'b111, w[0]} : d[4] ? {3'd0, d[2:0], w[0]} : {2'd0, 1'b1, d[2:0], w[0]};
                mir = {1'b0, d[5]};
            end
            8'd190: begin
                b8 = w[1] ? {6'd0, w[0]} : {2'd0, d[3:0], w[0]};
                // guardados con XOR del número de ventana: el reset (0) deja la CHR lineal (2 KB 0-3), como
                // espera el juego en el logo (y como arranca Mesen2)
                c1 = {r[s[2:1]] ^ {6'd0, s[2:1]}, s[0]};
                mir = 2'd0;
                ram = 1'b1;                                                    // PRG-RAM 8 KB en $6000
            end
            8'd221: begin
                b8 = { !a[1] ? (a[7:2] | {3'd0, r[0][2:0]}) :                          // 16 KB repetido
                       a[8]  ? (w[1] ? (a[7:2] | 6'd7) : (a[7:2] | {3'd0, r[0][2:0]})) :   // UNROM
                               ((a[7:2] | {3'd0, r[0][2:1], 1'b0}) + {5'd0, w[1]}),     // 32 KB (bancos n y n + 1)
                       w[0] };
                mir = {1'b0, a[0]};
            end
            default: ;
        endcase
    end

    // ------------------------------------------------------------ salidas
    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);
    wire ram_win  = (map_id == 8'd246) ? (cpu_a[12:11] == 2'b01) : 1'b1;     // 246: RAM solo en $6800-$6FFF
    // ROM de 8 KB en $6000 (51, 108 y el 103 con la RAM apagada)
    reg rom6; reg [5:0] b6;
    always @(*) begin
        rom6 = 1'b0; b6 = 6'd0;
        case (map_id)
            8'd51:  begin rom6 = 1'b1; b6 = r[1][0] ? {1'b1, r[0][2:0], 2'b11} : {1'b1, r[0][2], 4'b1111}; end
            8'd108: begin rom6 = 1'b1; b6 = p108[5:0]; end
            8'd103: begin rom6 = r[1][0]; b6 = {2'd0, r[0][3:0]}; end
            default: ;
        endcase
    end
    // 103: segunda página de RAM en $B800-$D7FF (lecturas con la RAM encendida; escrituras siempre). $6000: las
    // escrituras van siempre a la RAM.
    wire M103   = (map_id == 8'd103);
    wire in_b8  = !romsel_n && (cpu_a[14:10] >= 5'h0E) && (cpu_a[14:10] <= 5'h15);
    wire ram103 = M103 && (in_b8 || win_6000) && (!cpu_rw || !r[1][0]);
    // página de PRG-RAM de 8 KB (178: R3, 32 KB)
    wire [5:0] rpg = (map_id == 8'd178) ? {4'd0, r[3][1:0]} : 6'd0;

    assign prg_rom_en = (!romsel_n && !(ram103 && in_b8)) || (win_6000 && rom6 && m2 && !(M103 && !cpu_rw));
    assign prg_ram_en = ((win_6000 && ram && ram_win && !rom6) || ram103) && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a      = (ram103 && in_b8)           ? {6'd1, cpu_a[12:10] + 3'd2} :      // $B800 = página 1
                        (win_6000 && rom6 && !ram103) ? {b6, cpu_a[12:10]} :
                        romsel_n                      ? {rpg, cpu_a[12:10]} :
                        (map_id == 8'd31)             ? {r246[cpu_a[14:12]][6:0], cpu_a[11:10]} :   // 4 KB
                                                        {b8[5:0], cpu_a[12:10]};

    // CHR-RAM: 8 KB recortados aquí; más en 13 (16 KB), 28/30/96 (32 KB) y 168 (64 KB)
    reg [8:0] c_ram;
    always @(*) begin
        case (map_id)
            8'd13:  c_ram = {5'd0, c1[3:0]};
            8'd28:  c_ram = {4'd0, r[0][1:0], s};
            8'd30:  c_ram = {4'd0, d[6:5], s};
            8'd96:  c_ram = {4'd0, c1[4:0]};                                  // 32 KB
            8'd168: c_ram = s[2] ? {3'd0, d[3:0], s[1:0]} : {7'd0, s[1:0]};
            default: c_ram = {6'd0, s};
        endcase
    end
    // 77: $0800-$1FFF = 6 KB de CHR-RAM en la zona libre de la SRAM CHR (0x7C000, como el TQROM)
    wire raw77 = (map_id == 8'd77) && (s[2:1] != 2'b00);
    assign chr_raw   = raw77;
    assign chr_a     = raw77 ? {6'b111110, s} : cfg[7] ? c_ram : c1;
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = (cfg[7] && !cwp || raw77) && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = (mir == 2'd0) ? ppu_a[10] : (mir == 2'd1) ? ppu_a[11] : mir[0];
    assign irq       = irq168;

    // 212: lectura de $6000-$7FFF con A4 = 0 -> D7 = 1 (protección del cartucho)
    // 188: lectura de $6000-$7FFF = micrófono: D0/D1 = botones A/B (0 = pulsado), D2 = micrófono. El N8 no tiene
    //      micrófono: botones sin pulsar y silencio (con bus abierto, $60, el juego veía los dos pulsados).
    assign cpu_dout = (map_id == 8'd188) ? 8'h03 : 8'h80;
    assign cpu_doe  = (map_id == 8'd212 && win_6000 && cpu_rw && !cpu_a[4]) ? 8'h80 :
                      (map_id == 8'd188 && win_6000 && cpu_rw)               ? 8'h07 : 8'h00;

endmodule
