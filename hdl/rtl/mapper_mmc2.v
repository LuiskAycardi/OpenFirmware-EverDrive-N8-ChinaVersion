`timescale 1ns/1ps
// mapper_mmc2.v — Mappers 9 y 10 (MMC2 PxROM / MMC4 FxROM). Implementación propia (clean room).
// $A000: PRG (MMC2: 8 KB en $8000 y $A000-$FFFF fijos a los 3 últimos; MMC4: 16 KB en $8000
//        y $C000 fijo al último)
// $B000/$C000: CHR 4 KB en $0000 para el latch 0 = FD / FE;  $D000/$E000: lo mismo en $1000
// $F000: mirroring (D0 = 1 horizontal)
// Latches: al terminar una lectura de la PPU (en el dominio de clk, ver abajo) en
//   $0FD8 -> latch izq. = FD, $0FE8 -> FE  (MMC4: rangos $0FD8-$0FDF y $0FE8-$0FEF)
//   $1FD8-$1FDF -> latch der. = FD, $1FE8-$1FEF -> FE
// La lectura que dispara aún usa el banco anterior (como el chip). Al arrancar, latches en FE.
//
// Lógica según la descripción pública (NESdev Wiki); comportamiento contrastado con Mesen2,
// que es la referencia del banco de pruebas. Todas las salidas son activo-alto.

module mapper_mmc2 (
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
    input  wire        clk,        // reloj del sistema (50 MHz): latches FD/FE
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

    wire MMC4 = (map_id == 8'd10);   // 9 = MMC2, 10 = MMC4
    reg [3:0] prg;
    reg [4:0] l_fd, l_fe, r_fd, r_fe;
    reg       mir_h;
    initial begin prg = 0; l_fd = 0; l_fe = 0; r_fd = 0; r_fe = 0; mir_h = 0; end
    wire rom_wr = !romsel_n && !cpu_rw;
    always @(negedge m2) begin
        if (rst) begin
            prg <= 0; l_fd <= 0; l_fe <= 0; r_fd <= 0; r_fe <= 0; mir_h <= !cfg[0];
        end else if (rom_wr) begin
            case (cpu_a[14:12])
                3'd2: prg   <= cpu_d[3:0];   // $A000
                3'd3: l_fd  <= cpu_d[4:0];   // $B000
                3'd4: l_fe  <= cpu_d[4:0];   // $C000
                3'd5: r_fd  <= cpu_d[4:0];   // $D000
                3'd6: r_fe  <= cpu_d[4:0];   // $E000
                3'd7: mir_h <= cpu_d[0];     // $F000
                default: ;
            endcase
        end
    end

    // Latches: cambian al terminar una lectura de la PPU en $xFD8/$xFE8.
    // El flanco de subida de /RD NO sirve como reloj en la consola (fallo visto el 2026-11-05 en
    // Punch-Out!! y Fire Emblem Gaiden, que en el banco salían idénticos): cuando sube /RD, ALE ya abre
    // el latch de direcciones de la consola para el acceso siguiente, así que la dirección puede haber
    // cambiado justo en ese flanco, y además la señal llega con rebotes. Por eso todo va en el dominio
    // de clk (50 MHz): /RD se sincroniza con 2 etapas, la dirección se decodifica cuando /RD lleva 3
    // muestras bajo (estable desde antes de bajar /RD) y el latch cambia cuando /RD lleva 3 muestras
    // alto. Un rebote de hasta ~40 ns no cuenta. La lectura disparadora usa aún el banco anterior.
    // /RD dura ~186 ns bajo y el siguiente acceso al patrón llega >= 3 accesos después (> 1 us).
    // (Hecho aprendido leyendo el MMC2 del N8 PRO de Krikzz: allí también se filtra /RD con el reloj
    // del sistema y se guarda la dirección durante la lectura. Esta implementación es propia.)
    reg latch_l, latch_r;
    reg [1:0] rd_sync;           // rd_sync[1] = /RD ya sincronizado
    reg [1:0] rd_lo, rd_hi;      // muestras seguidas con /RD bajo / alto (saturan en 3)
    reg       pend;              // hay una lectura capturada que aún no se ha aplicado
    reg [3:0] hit;               // {der FE, der FD, izq FE, izq FD} de esa lectura
    initial begin latch_l = 1; latch_r = 1; rd_sync = 2'b11; rd_lo = 0; rd_hi = 0; pend = 0; hit = 0; end
    wire l_fd_hit = MMC4 ? (ppu_a[13:3] == 11'h1FB) : (ppu_a[13:0] == 14'h0FD8);   // $0FD8(-$0FDF)
    wire l_fe_hit = MMC4 ? (ppu_a[13:3] == 11'h1FD) : (ppu_a[13:0] == 14'h0FE8);   // $0FE8(-$0FEF)
    wire r_fd_hit = (ppu_a[13:3] == 11'h3FB);                                      // $1FD8-$1FDF
    wire r_fe_hit = (ppu_a[13:3] == 11'h3FD);                                      // $1FE8-$1FEF
    always @(posedge clk) begin
        rd_sync <= {rd_sync[0], ppu_rd_n};
        if (rst) begin
            latch_l <= 1'b1; latch_r <= 1'b1; pend <= 1'b0; rd_lo <= 2'd0; rd_hi <= 2'd0;
        end else if (!rd_sync[1]) begin                       // lectura en curso
            rd_hi <= 2'd0;
            if (rd_lo != 2'd3) rd_lo <= rd_lo + 2'd1;
            if (rd_lo == 2'd2) begin
                hit  <= {r_fe_hit, r_fd_hit, l_fe_hit, l_fd_hit};
                pend <= 1'b1;
            end
        end else begin                                        // /RD alto
            rd_lo <= 2'd0;
            if (rd_hi != 2'd3) rd_hi <= rd_hi + 2'd1;
            if (rd_hi == 2'd2 && pend) begin
                pend <= 1'b0;
                if (hit[0]) latch_l <= 1'b0;
                if (hit[1]) latch_l <= 1'b1;
                if (hit[2]) latch_r <= 1'b0;
                if (hit[3]) latch_r <= 1'b1;
            end
        end
    end

    wire [4:0] cbank = ppu_a[12] ? (latch_r ? r_fe : r_fd) : (latch_l ? l_fe : l_fd);

    wire win_6000    = romsel_n && (cpu_a[14:13] == 2'b11);
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = win_6000 && m2;
    assign prg_wr     = !cpu_rw && prg_ram_en;
    // PRG: MMC2 en 8 KB (último -3/-2/-1), MMC4 en 16 KB
    wire [5:0] bank8 = (cpu_a[14:13] == 2'd0) ? {2'd0, prg} :
                       (cpu_a[14:13] == 2'd1) ? 6'b111101 :
                       (cpu_a[14:13] == 2'd2) ? 6'b111110 : 6'b111111;
    wire [4:0] bank16 = cpu_a[14] ? 5'b11111 : {1'b0, prg};
    assign prg_a = romsel_n ? {6'd0, cpu_a[12:10]} :
                   MMC4     ? {bank16, cpu_a[13:10]} : {bank8, cpu_a[12:10]};
    assign chr_a = cfg[7] ? {6'd0, ppu_a[12:10]} : {2'd0, cbank, ppu_a[11:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = mir_h ? ppu_a[11] : ppu_a[10];
    assign irq = 1'b0;

endmodule
