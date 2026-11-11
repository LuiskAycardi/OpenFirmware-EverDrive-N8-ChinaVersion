`timescale 1ns/1ps
// mapper_mmc1.v — Mapper 1 (MMC1: SxROM). Implementación propia según la descripción
// pública del chip (NESdev Wiki).
//
// Registro serie de 5 bits, se carga LSB primero escribiendo en $8000-$FFFF:
//   - bit 7 = 1: reinicia el registro serie y pone el control en modo PRG 3.
//   - 5.ª escritura: el valor va al registro elegido por A14..A13 de esa escritura:
//       $8000 control  [1:0] mirroring (0: pantalla A, 1: pantalla B, 2: vertical, 3: horizontal)
//                      [3:2] modo PRG (0/1: 32 KB, 2: $8000 fijo al primero, 3: $C000 fijo al último)
//                      [4]   modo CHR (0: 8 KB, 1: dos de 4 KB)
//       $A000 CHR banco 0 (4 KB)    $C000 CHR banco 1 (4 KB)    $E000 PRG banco (16 KB)
//   - Se ignoran escrituras en ciclos consecutivos (instrucciones read-modify-write).
// Placas con CHR-RAM (SNROM, SUROM...): la CHR-RAM es de 8 KB y solo usa CHR A12 del MMC1;
// los bits altos de los registros CHR tienen otros usos. Como el OS deja la máscara CHR
// abierta (registro 133 = $FF) con CHR-RAM, el mapper debe recortar él mismo a 8 KB.
// SUROM (512 KB): la salida CHR A16 del MMC1 va a PRG A18 (elige la mitad de 256 KB).
// En modo CHR de 4 KB sigue al registro activo según PPU A12, igual que el chip real.
// No implementado: banco de WRAM de SOROM/SXROM ni el bit de desactivación de WRAM
// (la PRG-RAM queda siempre habilitada, como en MMC1A).

module mapper_mmc1 (
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
    output wire        irq
);

    reg [4:0] ctrl, chr0, chr1, prg;
    reg [4:0] shift;
    reg [2:0] count;
    reg       prev_wr;      // el ciclo anterior fue una escritura en $8000+

    initial begin
        ctrl = 5'h0C; chr0 = 5'd0; chr1 = 5'd0; prg = 5'd0;
        shift = 5'd0; count = 3'd0; prev_wr = 1'b0;
    end

    wire rom_wr = !romsel_n && !cpu_rw;
    wire [4:0] value = {cpu_d[0], shift[4:1]};

    always @(negedge m2) begin
        prev_wr <= rom_wr;
        if (rst) begin
            ctrl  <= 5'h0C;
            chr0  <= 5'd0;
            chr1  <= 5'd0;
            prg   <= 5'd0;
            shift <= 5'd0;
            count <= 3'd0;
        end else if (rom_wr && !prev_wr) begin
            if (cpu_d[7]) begin
                shift <= 5'd0;
                count <= 3'd0;
                ctrl  <= ctrl | 5'h0C;
            end else if (count == 3'd4) begin
                case (cpu_a[14:13])
                    2'd0: ctrl <= value;
                    2'd1: chr0 <= value;
                    2'd2: chr1 <= value;
                    2'd3: prg  <= value;
                endcase
                shift <= 5'd0;
                count <= 3'd0;
            end else begin
                shift <= value;
                count <= count + 3'd1;
            end
        end
    end

    // ---------------------------------------------------------------- PRG
    reg [3:0] bank16;
    always @(*) begin
        case (ctrl[3:2])
            2'd2:    bank16 = cpu_a[14] ? prg[3:0] : 4'b0000;
            2'd3:    bank16 = cpu_a[14] ? 4'b1111  : prg[3:0];
            default: bank16 = {prg[3:1], cpu_a[14]};
        endcase
    end

    wire [4:0] bank4 = ctrl[4] ? (ppu_a[12] ? chr1 : chr0) : {chr0[4:1], ppu_a[12]};

    wire outer    = cfg[7] & bank4[4];      // SUROM: CHR A16 -> PRG A18
    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);

    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]} : {outer, bank16, cpu_a[13:10]};
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;

    // ---------------------------------------------------------------- CHR
    assign chr_a  = cfg[7] ? {6'd0, bank4[0], ppu_a[11:10]}     // CHR-RAM: 8 KB
                           : {2'd0, bank4,    ppu_a[11:10]};    // CHR-ROM: hasta 128 KB
    assign chr_en = !ppu_a[13];
    assign chr_wr = cfg[7] && !ppu_wr_n && !ppu_a[13];

    // ---------------------------------------------------------------- mirroring
    reg a10;
    always @(*) begin
        case (ctrl[1:0])
            2'd0: a10 = 1'b0;
            2'd1: a10 = 1'b1;
            2'd2: a10 = ppu_a[10];
            2'd3: a10 = ppu_a[11];
        endcase
    end

    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = a10;
    assign irq       = 1'b0;

endmodule
