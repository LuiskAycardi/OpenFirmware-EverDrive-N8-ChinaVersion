`timescale 1ns/1ps
// mapper_fds.v — Famicom Disk System (mapper 254 del N8), implementación propia. Diseño: docs/fds-diseno.md.
//
// El disco no se sirve byte a byte por $4031 como en el FDS real: A0-A9 de la SRAM vienen del bus de la consola y
// la FPGA no puede elegir el byte. La BIOS del usuario, parcheada por nuestro OS, lee y escribe el disco por una
// ventana. Además, en el N8 de NES lo que conduce la FPGA no llega a la CPU en $4000-$41FF (medido en la prueba F0,
// 2026-11-20): los registros privados que hay que leer van en $42xx.
//
// SRAM PRG (512 KB): cara k del disco en k * 64 KB (k = 0-6, 65 500 bytes cada una), código del parche en 0x7D000
// (4 KB) y la BIOS en 0x7E000 (8 KB). Todo lo copia el OS antes de lanzar.
//
// CPU: $E000-$FFFF  BIOS (SRAM PRG 0x7E000, solo lectura)
//      $6000-$DFFF  RAM del FDS, 32 KB: PRG-RAM, bancos de 8 KB 0-3
//      $5000-$5FFF  código del parche (SRAM PRG 0x7D000, solo lectura)
//      $4800-$4BFF  ventana del disco (con $4210 D0 = 1): 1 KB de la cara en el banco de la cabeza, SRAM PRG
//                   {cara, cabeza[15:10], A9-A0}, lectura y escritura
//      registros del FDS (NESdev, «Family Computer Disk System»):
//        $4020/$4021 recarga del temporizador (byte bajo/alto)
//        $4022       D0 = repetir, D1 = activar (con $4023 D0): copia la recarga en el contador; con D1 = 0 la
//                    IRQ se reconoce
//        $4023       D0 = registros del disco y temporizador, D1 = sonido; D0 = 0 para el temporizador y reconoce
//        $4025       D3 = mirroring (1 horizontal, 0 vertical); el resto (motor, transferencia, IRQ del disco) no
//                    hace falta: la transferencia la hace la BIOS parcheada por la ventana
//        $4030 (lect.) D0 = IRQ del temporizador, D3 = mirroring (D2 y D5, bus abierto); leerlo reconoce la IRQ
//        $4032 (lect.) D0-D2 = 0: disco dentro, listo y sin protección (D3-D7, bus abierto)
//        $4033 (lect.) D7 = 1: batería bien
//        (en el N8 de NES estas lecturas no llegan: la CPU lee $40, que da lo mismo en $4032; leer $4030 reconoce
//         la IRQ igual, porque la FPGA ve la dirección)
//      registros privados (para la BIOS parcheada y los juegos que el OS cambia):
//        $4210       D0 = ventana del disco activa
//        $4212       D2-D0 = cara (A18-A16), legible
//        $4213/$4214 posición de la cabeza en la cara (byte bajo/alto), legible
//        $4215       (escr.) la cabeza avanza un byte
//        $4216       un byte de apoyo para el parche (que no puede usar la RAM del juego), legible
//        $4217       (escr.) el parche ha visto B + Select en ReadPads de la BIOS; (lect.) fotogramas seguidos con
//                    la combinación (ver «cambio de cara a mano»)
//        $4218 (escr.) saca el disco 77 fotogramas, sin esperar a que pueda salir
//        $4219 (escr.) número de caras del disco (lo escribe el parche al buscar la cara)
// Cambio de cara a mano: B + Select mantenidos 45 fotogramas (~0,75 s) pasan a la cara siguiente (dando la vuelta)
// y sacan el disco 77 fotogramas, como al darle la vuelta en la consola. Hace falta cuando varias caras tienen el
// mismo ID y el cambio automático no sabe cuál quiere el juego. La combinación se ve de dos maneras, que suman en el
// mismo contador (así una pulsación nunca da dos vueltas): espiando las lecturas del mando 1 en $4016 (D0 y D1, la
// 2.ª y la 3.ª lectura tras el strobe: B y Select) y por el aviso del parche desde ReadPads de la BIOS. El contador
// vuelve a cero tras 10 fotogramas sin verla (hay juegos que no leen el mando en todos).
//        $422E (lect.) como $4030 (también reconoce la IRQ)
//        $4230 (lect.) como $4032, con el disco «fuera» un rato cuando el juego espera a que se saque (ver abajo)
//        $4231 (lect.) como $4033: $80
// Disco fuera: muchos juegos (165 de 396 en la colección; Zelda, Metroid, SMB2...) esperan leyendo $4032 a que se
// saque el disco para cambiar de cara, y en el N8 de NES $4032 da siempre $40 (dentro). Por eso el OS, al montar el
// disco en la SRAM, cambia en los archivos de programa cada lectura absoluta de $4030/$4032/$4033 por la de
// $422E/$4230/$4231 (byte alto + 2, byte bajo - 2: la suma de los bytes no cambia, y hay juegos que la comprueban,
// p. ej. Ai Senshi Nicol), y lo deshace al guardar el disco en la SD (tools/fds/fds.py). En $4230 el disco se saca solo como en
// el FDS de Mesen2 (leído para el criterio, nada copiado): si el juego lo lee más de 20 veces sin pausas de 100
// fotogramas, y han pasado 77 fotogramas desde la última actividad del disco, queda fuera 77 fotogramas; luego
// vuelve a estar dentro (la cara la elige el parche al leer la cabecera) y no puede volver a salir en 234.
// $4032 sigue dando «dentro»: es lo que ve la BIOS (en la NES no le llega otra cosa).
// Temporizador: con la IRQ activa, en cada ciclo de CPU: si el contador vale 0, pide IRQ y recarga (y sin
// «repetir» se para); si no, resta 1. Mismo comportamiento que Mesen2 (leído para los detalles, nada copiado).
// PPU: CHR-RAM de 8 KB en $0000-$1FFF; CIRAM según $4025 D3.
// Sonido ($4040-$408A, con $4023 D1 = 1): snd_fds.v. Salida = nivel (0-63) x 16 para audio_dac.v. Sus lecturas
// ($4040-$407F, $4090, $4092) solo llegan a la CPU en el N8 de Famicom (en el de NES, $40xx es bus abierto).

`ifndef FDS_FOTOGRAMA
`define FDS_FOTOGRAMA 29781                    // ciclos de CPU por fotograma (NTSC); el testbench lo acorta
`endif

module mapper_fds (
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
    output wire [7:0]  cpu_dout,
    output wire [7:0]  cpu_doe,
    output wire [9:0]  snd
);

    // ---------------------------------------------------------------- registros
    reg [15:0] recarga, cuenta;
    reg        t_rep, t_act, t_irq;
    reg        disco_en, sonido_en, mir_h;
    reg        ventana_en;
    reg [15:0] cabeza;
    reg [7:0]  apoyo;
    reg [5:0]  boton;                          // fotogramas con la combinación (45 = ya se dio la vuelta)
    reg [3:0]  sin_boton;                      // fotogramas seguidos sin verla
    reg        visto, pad_b;
    reg [3:0]  pad_i;                          // lecturas de $4016 desde el strobe
    reg [2:0]  n_caras;
    reg [2:0]  cara;
    reg [14:0] pre;                            // ciclos de CPU de un fotograma
    reg [7:0]  espera;                         // fotogramas hasta que el disco pueda salir
    reg [6:0]  hueco, fuera_cta;               // fotogramas desde la última lectura de $4230; disco fuera
    reg [4:0]  lecturas;
    reg        fuera;
    initial begin
        pre = 0; espera = 8'd77; hueco = 7'd100; fuera_cta = 0;
        lecturas = 0; fuera = 0;
        recarga = 0; cuenta = 0; t_rep = 0; t_act = 0; t_irq = 0;
        disco_en = 1; sonido_en = 1; mir_h = 0; ventana_en = 0; cabeza = 0; apoyo = 0; boton = 0; cara = 0;
        sin_boton = 0; visto = 0; pad_b = 0; pad_i = 0; n_caras = 3'd1;
    end

    wire io     = romsel_n && (cpu_a[14:8] == 7'h40);              // $4000-$40FF
    wire priv   = romsel_n && (cpu_a[14:8] == 7'h42);              // $4200-$42FF
    wire es_lee = cpu_rw;
    wire lee_42   = es_lee && priv && cpu_a[7:0] == 8'h30;
    wire lee_estado = es_lee && ((io && cpu_a[7:0] == 8'h30) || (priv && cpu_a[7:0] == 8'h2E));

    reg [15:0] c_cuenta;
    reg        c_act, c_irq;
    always @(negedge m2) begin
        if (rst) begin
            recarga <= 0; cuenta <= 0; t_rep <= 0; t_act <= 0; t_irq <= 0;
            disco_en <= 1; sonido_en <= 1; mir_h <= 0; ventana_en <= 0; cabeza <= 0; apoyo <= 0; boton <= 0;
            cara <= 0; pre <= 0; sin_boton <= 0; visto <= 0; pad_b <= 0; pad_i <= 0; n_caras <= 3'd1; espera <= 8'd77; hueco <= 7'd100;
            fuera_cta <= 0; lecturas <= 0; fuera <= 0;
        end else begin
            // disco fuera (ver la cabecera): un paso por fotograma y las lecturas de $4230
            if (pre == `FDS_FOTOGRAMA - 1) begin
                pre <= 0;
                if (espera != 0) espera <= espera - 8'd1;
                if (hueco != 7'd100) hueco <= hueco + 7'd1;
                if (fuera) begin
                    if (fuera_cta == 0) begin fuera <= 0; espera <= 8'd234; end
                    else fuera_cta <= fuera_cta - 7'd1;
                end
                // cambio de cara a mano
                visto <= 0;
                if (visto) begin
                    sin_boton <= 0;
                    if (boton != 6'd45) begin
                        boton <= boton + 6'd1;
                        if (boton == 6'd44) begin
                            cara <= (cara + 3'd1 >= n_caras) ? 3'd0 : cara + 3'd1;
                            fuera <= 1; fuera_cta <= 7'd77; lecturas <= 0; hueco <= 7'd100;
                        end
                    end
                end else if (sin_boton == 4'd10)
                    boton <= 0;
                else
                    sin_boton <= sin_boton + 4'd1;
            end else
                pre <= pre + 15'd1;
            // el mando 1, espiado: B es la 2.ª lectura de $4016 tras el strobe y Select la 3.ª
            if (!cpu_rw && io && cpu_a[7:0] == 8'h16) pad_i <= 0;
            if (cpu_rw && io && cpu_a[7:0] == 8'h16 && pad_i != 4'd8) begin
                pad_i <= pad_i + 4'd1;
                if (pad_i == 4'd1) pad_b <= cpu_d[0] | cpu_d[1];
                if (pad_i == 4'd2 && pad_b && (cpu_d[0] | cpu_d[1])) visto <= 1;
            end
            if (lee_42 && !fuera) begin
                hueco <= 0;
                if (hueco == 7'd100) lecturas <= 0;
                else if (lecturas == 5'd20) begin
                    if (espera == 0) begin fuera <= 1; fuera_cta <= 7'd77; lecturas <= 0; hueco <= 7'd100; end
                end else lecturas <= lecturas + 5'd1;
            end
            // temporizador: un paso por ciclo de CPU
            c_cuenta = cuenta; c_act = t_act; c_irq = t_irq;
            if (c_act) begin
                if (c_cuenta == 16'd0) begin
                    c_irq = 1'b1;
                    c_cuenta = recarga;
                    if (!t_rep) c_act = 1'b0;
                end else
                    c_cuenta = c_cuenta - 16'd1;
            end
            // escrituras y lecturas con efecto
            if (!cpu_rw && io) begin
                case (cpu_a[7:0])
                    8'h20: recarga[7:0]  <= cpu_d;
                    8'h21: recarga[15:8] <= cpu_d;
                    8'h22: begin
                        t_rep <= cpu_d[0];
                        c_act = cpu_d[1] && disco_en;
                        if (c_act) c_cuenta = recarga;
                        else       c_irq = 1'b0;
                    end
                    8'h23: begin
                        disco_en  <= cpu_d[0];
                        sonido_en <= cpu_d[1];
                        if (!cpu_d[0]) begin c_act = 1'b0; c_irq = 1'b0; end
                    end
                    8'h25: if (disco_en) mir_h <= cpu_d[3];
                    default: ;
                endcase
            end
            if (!cpu_rw && priv) begin
                case (cpu_a[7:0])
                    8'h10: ventana_en <= cpu_d[0];
                    8'h12: cara  <= cpu_d[2:0];
                    8'h13: begin cabeza[7:0]  <= cpu_d; espera <= 8'd77; end
                    8'h14: begin cabeza[15:8] <= cpu_d; espera <= 8'd77; end
                    8'h15: begin cabeza <= cabeza + 16'd1; espera <= 8'd77; end
                    8'h16: apoyo <= cpu_d;
                    8'h17: visto <= 1;
                    8'h19: n_caras <= cpu_d[2:0];
                    8'h18: begin fuera <= 1; fuera_cta <= 7'd77; lecturas <= 0; hueco <= 7'd100; end
                    default: ;
                endcase
            end
            if (lee_estado) c_irq = 1'b0;
            cuenta <= c_cuenta; t_act <= c_act; t_irq <= c_irq;
        end
    end

    // ---------------------------------------------------------------- memoria
    wire bios    = !romsel_n && (cpu_a[14:13] == 2'b11);           // $E000-$FFFF
    wire ram_hi  = !romsel_n && (cpu_a[14:13] != 2'b11);           // $8000-$DFFF
    wire ram_6   = romsel_n && (cpu_a[14:13] == 2'b11);            // $6000-$7FFF
    wire parche  = romsel_n && (cpu_a[14:12] == 3'b101);           // $5000-$5FFF
    wire ventana = romsel_n && (cpu_a[14:10] == 5'b10010) && ventana_en;  // $4800-$4BFF
    wire [1:0] banco_ram = ram_6 ? 2'd0 : (cpu_a[14:13] + 2'd1);   // $6000=0, $8000=1, $A000=2, $C000=3

    assign prg_a = bios    ? {6'b111111, cpu_a[12:10]} :            // 0x7E000
                   parche  ? {7'b1111101, cpu_a[11:10]} :           // 0x7D000
                   ventana ? {cara, cabeza[15:10]} :
                             {4'd0, banco_ram, cpu_a[12:10]};       // PRG-RAM 8 KB * banco_ram
    assign prg_rom_en = bios || ((parche || ventana) && m2);
    assign prg_ram_en = (ram_6 || ram_hi) && m2;
    assign prg_wr     = !cpu_rw && m2 && (ram_6 || ram_hi || ventana);   // con prg_rom_en (ventana): SRAM PRG

    // ---------------------------------------------------------------- sonido
    wire [5:0] snd_nivel, snd_lee;
    snd_fds sonido (.m2(m2), .rst(rst), .wr(!cpu_rw && io && sonido_en && cpu_a[7:6] != 2'b00), .a(cpu_a[7:0]),
                    .d(cpu_d), .out(snd_nivel), .lee(snd_lee));
    assign snd = {snd_nivel, 4'b0000};

    // ---------------------------------------------------------------- lecturas que conduce la FPGA
    wire [7:0] estado = {2'b00, 1'b0, 1'b0, mir_h, 1'b0, 1'b0, t_irq};
    wire r30  = io && cpu_a[7:0] == 8'h30 && disco_en;
    wire r32  = io && cpu_a[7:0] == 8'h32 && disco_en;
    wire r33  = io && cpu_a[7:0] == 8'h33 && disco_en;
    wire p12  = priv && cpu_a[7:0] == 8'h12;
    wire p13  = priv && cpu_a[7:0] == 8'h13;
    wire p14  = priv && cpu_a[7:0] == 8'h14;
    wire p16  = priv && cpu_a[7:0] == 8'h16;
    wire p17  = priv && cpu_a[7:0] == 8'h17;
    wire p30  = priv && cpu_a[7:0] == 8'h2E;          // $422E = $4030
    wire p32  = priv && cpu_a[7:0] == 8'h30;          // $4230 = $4032 con el disco fuera
    wire p33  = priv && cpu_a[7:0] == 8'h31;          // $4231 = $4033
    wire rsnd = io && sonido_en && (cpu_a[7:6] == 2'b01 || cpu_a[7:0] == 8'h90 || cpu_a[7:0] == 8'h92);
    assign cpu_doe  = !cpu_rw ? 8'h00 :
                      (r30 || p30) ? 8'hDB :          // D2 y D5: bus abierto
                      r32 ? 8'h07 :
                      (r33 || p33) ? 8'h80 :
                      rsnd ? 8'h3F :                  // D7-D6: bus abierto
                      (p12 || p13 || p14 || p16 || p17 || p32) ? 8'hFF : 8'h00;
    assign cpu_dout = (r30 || p30) ? estado :
                      r32 ? 8'h00 :
                      (r33 || p33) ? 8'h80 :
                      p32 ? {5'b01000, fuera, fuera, fuera} :    // $40 como el bus abierto de $4032
                      rsnd ? {2'b00, snd_lee} :
                      p12 ? {5'b00000, cara} :
                      p13 ? cabeza[7:0] :
                      p14 ? cabeza[15:8] :
                      p16 ? apoyo :
                      p17 ? {2'b00, boton} : 8'h00;

    // ---------------------------------------------------------------- PPU e IRQ
    assign chr_a     = {6'd0, ppu_a[12:10]};
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = mir_h ? ppu_a[11] : ppu_a[10];
    assign irq       = t_irq;

endmodule
