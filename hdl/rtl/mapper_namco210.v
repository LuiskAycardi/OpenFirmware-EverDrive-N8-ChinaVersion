`timescale 1ns/1ps
// mapper_namco210.v — Mapper 210 (Namco 175 / 340). Implementación propia (clean room).
// Como el Namco 163 sin audio, sin RAM interna ni IRQ. iNES 1.0 no distingue la variante:
// se detecta por las escrituras del juego:
//   - escritura en $C000-$C7FF -> Namco 175: D0 habilita la escritura en la PRG-RAM de $6000. Manda
//     siempre (aunque antes se haya visto el 340): mirroring de cabecera.
//   - escritura en $E000 con D7 o D6 a 1 -> Namco 340: mirroring en D7-D6 (0 A, 1 V, 2 H, 3 B)
//   - sin detectar: sin PRG-RAM y mirroring de cabecera
// Criterio revisado el 2026-11-06 con los 13 juegos del mapper 210 de la colección: Mesen2 (iNES 1.0) solo
// toma el 340 con D7 = 1, y Wagyan Land 2 (340, cabecera horizontal) solo escribe D7-D6 = 01 (vertical), así
// que quedaba en horizontal (columna rota y barra sin texto en el banco). Los 175 también escriben D7-D6 = 01,
// pero tienen cabecera vertical: el resultado es el mismo. El OS v13 no pasa el submapper NES 2.0 a la FPGA.
// $8000-$BFFF: CHR de 1 KB (registro = A13-A11)   $E000/$E800/$F000: PRG 8 KB en $8000/$A000/$C000
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_namco210 (
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

    reg [7:0] chr [0:7];
    reg [5:0] p0, p1, p2;
    reg       is175, is340, ram_we;
    reg [1:0] mir340;
    integer i;
    initial begin
        for (i = 0; i < 8; i = i + 1) chr[i] = 0;
        p0 = 0; p1 = 0; p2 = 0; is175 = 0; is340 = 0; ram_we = 0; mir340 = 0;
    end
    wire rom_wr = !romsel_n && !cpu_rw;
    always @(negedge m2) begin
        if (rst) begin
            for (i = 0; i < 8; i = i + 1) chr[i] <= 0;
            p0 <= 0; p1 <= 0; p2 <= 0; is175 <= 0; is340 <= 0; ram_we <= 0; mir340 <= 0;
        end else if (rom_wr) begin
            if (!cpu_a[14]) chr[cpu_a[13:11]] <= cpu_d;                       // $8000-$BFFF
            else case (cpu_a[13:11])
                3'd0: begin is175 <= 1'b1; ram_we <= cpu_d[0]; end               // $C000
                3'd4: begin p0 <= cpu_d[5:0]; mir340 <= cpu_d[7:6];              // $E000
                            if (cpu_d[7:6] != 2'd0) is340 <= 1'b1; end
                3'd5: p1 <= cpu_d[5:0];                                          // $E800
                3'd6: p2 <= cpu_d[5:0];                                          // $F000
                default: ;
            endcase
        end
    end

    reg [5:0] bank8;
    always @(*) begin
        case (cpu_a[14:13])
            2'd0: bank8 = p0;
            2'd1: bank8 = p1;
            2'd2: bank8 = p2;
            2'd3: bank8 = 6'b111111;
        endcase
    end
    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && is175 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en && ram_we;
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} : {bank8, cpu_a[12:10]};

    wire [7:0] cb = chr[ppu_a[12:10]];
    assign chr_a = cfg[7] ? {6'd0, cb[2:0]} : {1'b0, cb};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = (!is340 || is175) ? (cfg[0] ? ppu_a[10] : ppu_a[11]) :
                       (mir340 == 2'd0) ? 1'b0 : (mir340 == 2'd1) ? ppu_a[10] :
                       (mir340 == 2'd2) ? ppu_a[11] : 1'b1;
    assign irq = 1'b0;

endmodule
