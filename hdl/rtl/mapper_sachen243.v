`timescale 1ns/1ps
// mapper_sachen243.v — Mappers 243 (Sachen SA-020A) y 150 (SA-015/SA-630), chip 74LS374N.
// Implementación propia (clean room).
// Registros en $4100-$7FFF (máscara $C101): $4100 selección (D2-D0), $4101 dato (D2-D0).
//   CHR de 8 KB = R2.0 | R4.0 << 1 | R6[1:0] << 2      PRG de 32 KB = R5[1:0]
//   R7[2:1] mirroring: 0 = $2C00 en B y el resto en A, 1 H, 2 V, 3 pantalla A.
// 150 (por map_id, fase 3d): CHR = R4.0 << 2 | R6[1:0]; y leer $4101 (A & $C101) devuelve el registro
//   elegido en D2-D0 (los demás bits, bus abierto). El interruptor que pone D2 a 1 (Mesen2) no se usa.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_sachen243 (
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
    input  wire        clk,        // reloj del sistema
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
    output wire [7:0]  cpu_dout,   // 150: lectura del registro elegido
    output wire [7:0]  cpu_doe
);

    wire M150 = (map_id == 8'd150);
    reg [2:0] sel, r0, r1, r2, r3, r4, r5, r6, r7;
    initial begin sel = 0; r0 = 0; r1 = 0; r2 = 0; r3 = 0; r4 = 0; r5 = 0; r6 = 0; r7 = 0; end
    wire reg_wr = romsel_n && !cpu_rw && cpu_a[14] && cpu_a[8];
    always @(negedge m2) begin
        if (rst) begin
            sel <= 0; r0 <= 0; r1 <= 0; r2 <= 0; r3 <= 0; r4 <= 0; r5 <= 0; r6 <= 0; r7 <= 0;
        end else if (reg_wr) begin
            if (!cpu_a[0]) sel <= cpu_d[2:0];
            else case (sel)
                3'd0: r0 <= cpu_d[2:0];
                3'd1: r1 <= cpu_d[2:0];
                3'd2: r2 <= cpu_d[2:0];
                3'd3: r3 <= cpu_d[2:0];
                3'd4: r4 <= cpu_d[2:0];
                3'd5: r5 <= cpu_d[2:0];
                3'd6: r6 <= cpu_d[2:0];
                3'd7: r7 <= cpu_d[2:0];
            endcase
        end
    end

    // sin PRG-RAM: $6000-$7FFF son registros o la placa no la tiene
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {2'd0, r5[1:0], cpu_a[14:10]};
    wire [3:0] chr8 = M150 ? {1'b0, r4[0], r6[1:0]} : {r6[1:0], r4[0], r2[0]};

    // 150: lectura de $4101 (A15 = 0, A14 = 1, A8 = 1, A0 = 1)
    reg [2:0] rsel;
    always @(*) begin
        case (sel)
            3'd0: rsel = r0; 3'd1: rsel = r1; 3'd2: rsel = r2; 3'd3: rsel = r3;
            3'd4: rsel = r4; 3'd5: rsel = r5; 3'd6: rsel = r6; 3'd7: rsel = r7;
        endcase
    end
    wire rd4101 = M150 && romsel_n && cpu_rw && cpu_a[14] && cpu_a[8] && cpu_a[0];
    assign cpu_dout = {5'd0, rsel};
    assign cpu_doe  = rd4101 ? 8'h07 : 8'h00;
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {2'd0, chr8, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq = 1'b0;
    wire [1:0] m = r7[2:1];
    assign ciram_a10 = (m == 2'd0) ? (ppu_a[11:10] == 2'd3) :
                       (m == 2'd1) ? ppu_a[11] :
                       (m == 2'd2) ? ppu_a[10] : 1'b0;

endmodule
