`timescale 1ns/1ps
// mapper_camerica.v — Mapper 71 (Camerica/Codemasters BF9093/BF9097). Implementación propia (clean room).
// Escritura en $C000-$FFFF: ....PPPP -> PRG de 16 KB en $8000; $C000 fijo al último banco.
// BF9097 (Fire Hawk): una escritura en $9000-$9FFF activa el control de pantalla única
// (D4 = pantalla) y queda activo hasta volver al menú; mientras tanto, mirroring de cabecera.
// Polaridad: D4 = 1 -> pantalla B (CIRAM A10 = 1), como la referencia de Krikzz (Mesen2 la tiene
// invertida; en pantalla única no se nota porque todas las direcciones van a la misma página).
//
// Lógica según la descripción pública (NESdev Wiki); casos límite contrastados leyendo la
// referencia MIT de Krikzz (N8 PRO) solo para entenderlos. Todas las salidas son activo-alto.

module mapper_camerica (
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

    reg [3:0] prg;
    reg       mir_ctl, nt;
    initial begin prg = 0; mir_ctl = 0; nt = 0; end
    wire wr_c000 = !romsel_n && !cpu_rw && cpu_a[14];                       // $C000-$FFFF
    wire wr_9000 = !romsel_n && !cpu_rw && (cpu_a[14:12] == 3'b001);         // $9000-$9FFF
    always @(negedge m2) begin
        if (rst) begin prg <= 0; mir_ctl <= 0; nt <= 0; end
        else begin
            if (wr_c000) prg <= cpu_d[3:0];
            if (wr_9000) begin mir_ctl <= 1'b1; nt <= cpu_d[4]; end
        end
    end

    // La placa real no tiene PRG-RAM (y $6000-$7FFF son registros): no se habilita.
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign prg_a = romsel_n ? 9'd0 : {1'b0, cpu_a[14] ? 4'b1111 : prg, cpu_a[13:10]};
    assign chr_a = {6'd0, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign irq       = 1'b0;
    assign ciram_a10 = mir_ctl ? nt : (cfg[0] ? ppu_a[10] : ppu_a[11]);

endmodule
