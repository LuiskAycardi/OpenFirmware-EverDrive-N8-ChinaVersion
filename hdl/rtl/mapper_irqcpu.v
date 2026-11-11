`timescale 1ns/1ps
// mapper_irqcpu.v — Mappers con IRQ por ciclos de CPU (fase 4, lote 4). Implementación propia (clean room).
// Una instancia para todos (solo hay un mapper activo): comparten los registros de banco y un contador de 16 bits
// que avanza en cada bajada de M2.
//
//   40  NTDEC 2722 (SMB2j): $8000-$9FFF para y reconoce la IRQ (contador a 0), $A000-$BFFF la arranca,
//       $E000-$FFFF = PRG 8 KB en $C000. Fijos: $6000 = 6 (ROM), $8000 = 4, $A000 = 5, $E000 = 7. CHR 8 KB fija.
//       IRQ: contador de 13 bits (un CD4020) que solo cuenta arrancado; la línea es su bit 12: sube 4096 ciclos
//       después de arrancar y, si nadie la reconoce, vuelve a bajar 4096 ciclos más tarde (NESdev).
//   42  Bio Miracle Bokutte Upa / Ai Senshi Nicol: máscara $E003. $8000 = CHR 8 KB (con CHR-RAM no cuenta),
//       $E000 = PRG 8 KB en $6000 (ROM), $E001 D3 = mirroring (1 H), $E002 D1 = IRQ (0: para, reconoce y pone el
//       contador a 0). $8000-$FFFF = últimos 32 KB. IRQ: contador de 15 bits; línea activa con los dos bits altos a
//       1 (24576 ciclos sin IRQ, 8192 con ella, y vuelta a empezar).
//   50  N-32 (SMB2j): registros en $4020-$5FFF con A5 = 1; A8 = 0: PRG 8 KB en $C000 = {D3, D0, D2, D1};
//       A8 = 1: D0 = IRQ (0: para, reconoce y pone a 0). Fijos: $6000 = $0F (ROM), $8000 = 8, $A000 = 9,
//       $E000 = $0B. IRQ como el 40 (bit 12 de un contador de 13 bits).
//   73  Konami VRC3: $8000/$9000/$A000/$B000 = nibbles 0-3 de la recarga; $C000: D0 = activar al reconocer,
//       D1 = activar (con D1 se recarga el contador entero), D2 = modo de 8 bits, y reconoce; $D000 reconoce y copia
//       D0 de $C000 en la activación; $F000 D2-D0 = PRG 16 KB en $8000 ($C000 fijo al último). Contador de 16 bits
//       (o solo los 8 bajos) ascendente: al desbordar recarga (los 8 bajos en modo de 8 bits) y pide IRQ.
//       PRG-RAM 8 KB, CHR-RAM 8 KB.
//   106 SMB3 pirata: los registros se repiten cada 16 bytes en $8000-$FFFF (A3-A0). 0-7 = CHR 1 KB (0 y 2 con el
//       bit 0 a 0, 1 y 3 con el bit 0 a 1, sin el bit 7); 8 = PRG 8 KB en $8000 (+16), 9 = $A000, 10 = $C000
//       (5 bits), 11 = $E000 (+16); 12 D0 = mirroring (1 H); 13 = contador a 0, IRQ parada y reconocida;
//       14/15 = byte bajo/alto del contador (15 activa la IRQ). El contador sube en cada ciclo salvo en $FFFF,
//       donde se queda; la línea está activa con la IRQ activada y el contador en $FFFF. Al encender los
//       registros valen $F (74LS670). PRG-RAM 8 KB.
//   142 Kaiser KS7032 (SMB2j): recarga como el VRC3 ($8000-$BFFF); $C000 D1 = activar (recarga el contador) y
//       reconoce; $D000 reconoce; $E000 D2-D0 elige el registro que escribe $F000 (1 = $8000, 2 = $A000,
//       3 = $C000, 4 = $6000; D3-D0 = banco de 8 KB). $E000 fijo al último. El contador sube con la IRQ activada
//       y al llegar a $FFFF recarga, se para y pide IRQ (NESdev no da el detalle: es lo que hacen FCEUX y Mesen2).
//       CHR-RAM 8 KB.
//
// Fuentes de hechos: NESdev Wiki (páginas de cada mapper) y, donde NESdev no da el detalle, la implementación de
// Mesen2, leída solo para entender direcciones y bits; nada copiado. Diferencias con Mesen2 que se dejan así
// (siguiendo NESdev): 40 y 50 bajan solos la IRQ a los 8192 ciclos; 42 acepta cualquier valor con D1; 73 en modo
// de 8 bits sí pide IRQ; 106 tiene mirroring y su contador se queda en $FFFF; 142 tiene ROM en $6000 desde el
// encendido.

module mapper_irqcpu #(parameter EXTRA56=0) (
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

    output wire [18:10] prg_a,
    output wire        prg_rom_en,
    output wire        prg_ram_en,
    output wire        prg_wr,
    output wire [18:10] chr_a,
    output wire        chr_en,
    output wire        chr_wr,
    output wire        ciram_en,
    output wire        ciram_a10,
    output wire        irq
);

    wire M40 = (map_id == 8'd40), M42 = (map_id == 8'd42), M50 = (map_id == 8'd50);
    wire M73 = (map_id == 8'd73), M106 = (map_id == 8'd106), M142 = (map_id == 8'd142), M56=EXTRA56 && (map_id==8'd56);

    // ------------------------------------------------------------ registros
    reg [4:0]  pr [0:4];     // PRG 8 KB: 0 = $6000, 1 = $8000, 2 = $A000, 3 = $C000, 4 = $E000 (según el mapper)
    reg [7:0]  ch [0:7];     // 106: CHR 1 KB; ch[0] también la CHR 8 KB del 42
    reg use_rom56=0;
    reg        mir;          // 42, 106: 1 = horizontal
    reg [15:0] cnt;          // contador de IRQ
    reg [15:0] lat;          // 73, 142: recarga
    reg        en;           // IRQ activada / contador en marcha
    reg        ena, m8;      // 73: activar al reconocer, modo de 8 bits
    reg        irqf;         // 73, 142: IRQ pedida
    reg [2:0]  sel;          // 142: registro elegido en $E000
    integer i;
    initial begin
        for (i = 0; i < 5; i = i + 1) pr[i] = 5'h0F;
        for (i = 0; i < 8; i = i + 1) ch[i] = 7'h0F;
        mir = 0; cnt = 0; lat = 0; en = 0; ena = 0; m8 = 0; irqf = 0; sel = EXTRA56 ? 1 : 0;
    end

    wire wr8  = !romsel_n && !cpu_rw;                                       // $8000-$FFFF
    wire wr45 = romsel_n && !cpu_rw && (cpu_a[14:13] == 2'b10);             // $4000-$5FFF
    wire [2:0] a3 = cpu_a[14:12];

    // Como en los demás contadores por ciclos (FME-7, VRC): en cada bajada de M2 se aplica primero la escritura
    // del ciclo y luego se cuenta, así el ciclo de la escritura ya cuenta (mismo instante que Mesen2).
    reg [15:0] t_cnt;
    reg        t_en, t_irqf;
    always @(negedge m2) begin
        if (rst) begin
            // al encender, todo a 0 (durante el reset map_id aún vale $FF: el valor no puede depender del mapper)
            for (i = 0; i < 5; i = i + 1) pr[i] <= 5'h00;
            for (i = 0; i < 8; i = i + 1) ch[i] <= 7'h00;
            use_rom56<=0; mir <= 0; cnt <= 0; lat <= 0; en <= 0; ena <= 0; m8 <= 0; irqf <= 0; sel <= EXTRA56 ? 1 : 0;
        end else begin
            t_cnt = cnt; t_en = en; t_irqf = irqf;
            // ---- escrituras
            case (map_id)
                8'd40: if (wr8) case (cpu_a[14:13])
                    2'b00: begin t_en = 1'b0; t_cnt = 16'd0; end
                    2'b01: t_en = 1'b1;
                    2'b11: pr[3] <= cpu_d[4:0];
                    default: ;
                endcase
                8'd42: if (wr8 && cpu_a[14:13] == 2'b00 && cpu_a[1:0] == 2'b00) ch[0] <= cpu_d[6:0];
                       else if (wr8 && cpu_a[14:13] == 2'b11) case (cpu_a[1:0])
                    2'b00: pr[0] <= {M56 && pr[0][4], cpu_d[3:0]};
                    2'b01: mir <= cpu_d[3];
                    2'b10: begin t_en = cpu_d[1]; if (!cpu_d[1]) t_cnt = 16'd0; end
                    default: ;
                endcase
                8'd50: if (wr45 && cpu_a[5]) begin
                    if (!cpu_a[8]) pr[3] <= {1'b0, cpu_d[3], cpu_d[0], cpu_d[2], cpu_d[1]};
                    else if (cpu_d[0]) t_en = 1'b1;
                    else begin t_en = 1'b0; t_cnt = 16'd0; end
                end
                8'd73, 8'd142, 8'd56: if (wr8) case (a3)
                    3'd0: lat[3:0]   <= cpu_d[3:0];
                    3'd1: lat[7:4]   <= cpu_d[3:0];
                    3'd2: lat[11:8]  <= cpu_d[3:0];
                    3'd3: lat[15:12] <= cpu_d[3:0];
                    3'd4: begin                                                     // $C000
                        t_irqf = 1'b0;
                        t_en = cpu_d[1];
                        if (cpu_d[1]) t_cnt = lat;
                        if (M73) begin ena <= cpu_d[0]; m8 <= cpu_d[2]; end
                    end
                    3'd5: begin t_irqf = 1'b0; if (M73) t_en = ena; end             // $D000
                    3'd6: if (M142 || M56) sel <= cpu_d[2:0];                              // $E000
                    3'd7: if (M73) pr[1] <= {2'd0, cpu_d[2:0]};                     // $F000
                          else case (sel)
                              3'd1: pr[1] <= {M56 && pr[1][4], cpu_d[3:0]};
                              3'd2: pr[2] <= {M56 && pr[2][4], cpu_d[3:0]};
                              3'd3: pr[3] <= {M56 && pr[3][4], cpu_d[3:0]};
                              3'd4: pr[0] <= {M56 && pr[0][4], cpu_d[3:0]};
                              default: ;
                          endcase
                endcase
                8'd106: if (wr8) begin
                    if (!cpu_a[3]) ch[cpu_a[2:0]] <= cpu_d[6:0];
                    else case (cpu_a[2:0])
                        3'd0: pr[1] <= cpu_d[4:0];
                        3'd1: pr[2] <= cpu_d[4:0];
                        3'd2: pr[3] <= cpu_d[4:0];
                        3'd3: pr[4] <= cpu_d[4:0];
                        3'd4: mir <= cpu_d[0];
                        3'd5: begin t_cnt = 16'd0; t_en = 1'b0; end
                        3'd6: t_cnt[7:0] = cpu_d;
                        3'd7: begin t_cnt[15:8] = cpu_d; t_en = 1'b1; end
                    endcase
                end
                default: ;
            endcase
            if(M56 && wr8 && a3==7) begin
                if(sel==5) use_rom56<=cpu_d[2];
                case(cpu_a[11:10])
                    0: case(cpu_a[1:0])
                        0:pr[1][4]<=cpu_d[4]; 1:pr[2][4]<=cpu_d[4];
                        2:pr[3][4]<=cpu_d[4]; 3:pr[0][4]<=cpu_d[4];
                    endcase
                    2:mir<=~cpu_d[0];
                    3:ch[cpu_a[2:0]]<=cpu_d;
                    default:;
                endcase
            end
            // ---- contador
            if (M40 || M50) begin
                if (t_en) t_cnt[12:0] = t_cnt[12:0] + 13'd1;
            end else if (M42) begin
                if (t_en) t_cnt[14:0] = t_cnt[14:0] + 15'd1;
            end else if (M73) begin
                if (t_en) begin
                    if (m8 ? (t_cnt[7:0] == 8'hFF) : (t_cnt == 16'hFFFF)) begin    // desborda: recarga e IRQ
                        if (m8) t_cnt[7:0] = lat[7:0]; else t_cnt = lat;
                        t_irqf = 1'b1;
                    end else if (m8) t_cnt[7:0] = t_cnt[7:0] + 8'd1;
                    else t_cnt = t_cnt + 16'd1;
                end
            end else if (M142 || M56) begin
                if (t_en) begin
                    if (t_cnt == 16'hFFFE) begin t_cnt = lat; t_en = 1'b0; t_irqf = 1'b1; end
                    else t_cnt = t_cnt + 16'd1;
                end
            end else if (M106) begin
                if (t_cnt != 16'hFFFF) t_cnt = t_cnt + 16'd1;
            end
            cnt <= t_cnt; en <= t_en; irqf <= t_irqf;
        end
    end

    // ------------------------------------------------------------ bancos
    wire [1:0] w = cpu_a[14:13];
    wire [2:0] s = ppu_a[12:10];
    reg  [5:0] b8;           // página de 8 KB para $8000-$FFFF
    reg  [5:0] b6;           // página de 8 KB de ROM en $6000
    reg        rom6, ram;
    always @(*) begin
        b8 = {4'b1111, w}; b6 = 6'd0; rom6 = 1'b0; ram = 1'b0;
        case (map_id)
            8'd40: begin
                case (w) 2'd0: b8 = 6'd4; 2'd1: b8 = 6'd5; 2'd2: b8 = {1'b0, pr[3]}; default: b8 = 6'd7; endcase
                rom6 = 1'b1; b6 = 6'd6;
            end
            8'd42: begin rom6 = 1'b1; b6 = {2'd0, pr[0][3:0]}; end
            8'd50: begin
                case (w) 2'd0: b8 = 6'd8; 2'd1: b8 = 6'd9; 2'd2: b8 = {1'b0, pr[3]}; default: b8 = 6'd11; endcase
                rom6 = 1'b1; b6 = 6'd15;
            end
            8'd73: begin b8 = w[1] ? {5'b11111, w[0]} : {2'd0, pr[1][2:0], w[0]}; ram = 1'b1; end
            8'd106: begin
                case (w)
                    2'd0: b8 = {2'b01, pr[1][3:0]};
                    2'd1: b8 = {1'b0, pr[2]};
                    2'd2: b8 = {1'b0, pr[3]};
                    default: b8 = {2'b01, pr[4][3:0]};
                endcase
                ram = 1'b1;
            end
            8'd142,8'd56: begin
                case (w) 2'd0: b8 = {1'b0, pr[1]}; 2'd1: b8 = {1'b0, pr[2]}; 2'd2: b8 = {1'b0, pr[3]}; default: ; endcase
                rom6 = !M56 || use_rom56; ram=M56 && !use_rom56; b6 = {1'b0, pr[0]};
            end
            default: ;
        endcase
    end

    reg [8:0] c1;            // página de 1 KB de CHR-ROM
    always @(*) begin
        case (map_id)
            8'd42:  c1 = {2'd0, ch[0][3:0], s};
            8'd106: c1 = s[2] ? {2'd0, ch[s][6:0]} : {2'd0, ch[s][6:1], s[0]};
            8'd56: c1={1'b0,ch[s]};
            default: c1 = {6'd0, s};
        endcase
    end

    wire hdr_h = !cfg[0];                                      // mirroring de la cabecera (1 = H)
    wire h     = (M42 || M106 || M56) ? mir : hdr_h;

    // ------------------------------------------------------------ salidas
    wire win6 = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n || (win6 && rom6 && m2);
    assign prg_ram_en = win6 && ram && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    assign prg_a      = win6 ? (rom6 ? {b6, cpu_a[12:10]} : {6'd0, cpu_a[12:10]}) : {b8, cpu_a[12:10]};

    assign chr_a     = cfg[7] ? {6'd0, s} : c1;
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = h ? ppu_a[11] : ppu_a[10];

    assign irq = ((M40 || M50) && en && cnt[12]) ||
                 (M42 && en && cnt[14] && cnt[13]) ||
                 ((M73 || M142 || M56) && irqf) ||
                 (M106 && en && (cnt == 16'hFFFF));

endmodule
