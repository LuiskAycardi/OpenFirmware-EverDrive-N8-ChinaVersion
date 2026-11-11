// tb_fase4.v — Testbench autoverificable de los mappers de la fase 4 (RBF 102: mapper_latch.v).
// Comprueba los hechos de NESdev que sostienen cada mapper (bancos, mirroring, ventanas especiales, IRQ) para
// que las mutaciones de tools/mutate.py también cubran esta parte. La comparación completa con Mesen2 la hace
// la ROM sintética (tools/n8sim/fuzz); aquí van los casos que deciden si un mapper está bien o mal.
// Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_fase4;

`include "tb_bus.vh"

    integer n, c;

    task cycles_to_irq(input integer max, output integer cycles);
        begin
            cycles = -1;
            for (n = 1; n <= max && cycles < 0; n = n + 1) begin
                cpu_read(16'h0000);
                if (irq_n === 1'b0) cycles = n;
            end
        end
    endtask

    localparam P512 = 5'b11111;      // 512 KB de PRG: sin máscara
    localparam C512 = 8'b111111;     // 512 KB de CHR-ROM: sin máscara

    initial begin
        repeat (4) cpu_read(16'h0000);

        // ------------------------------------------------------------ lote 1 (un registro)
        start_game(8'd13, 5'b00001, CHR_RAM, 8'd0);
        cpu_write(16'h8000, 8'h02);
        expect_chr(14'h1000, 19'h02000, "13: $1000 = CHR-RAM de 4 KB elegida");
        expect_chr(14'h0000, 19'h00000, "13: $0000 fijo al banco 0");
        back_to_menu;

        start_game(8'd58, P512, C512, 8'd1);
        cpu_write(16'h80E5, 8'h00);                     // A7 H, A6 16 KB, A5-A3 = 4, A2-A0 = 5
        expect_prg(16'h8000, 19'h14000, "58: 16 KB repetido en $8000");
        expect_prg(16'hC000, 19'h14000, "58: 16 KB repetido en $C000");
        expect_chr(14'h0000, 19'h08000, "58: CHR 8 KB = A5-A3");
        expect_a10(14'h2800, 1, "58: A7 = 1 -> horizontal");
        back_to_menu;

        start_game(8'd246, P512, C512, 8'd0);
        expect_prg(16'hE000, 19'h7E000, "246: al encender $E000 = ultimo banco");
        cpu_write(16'h6001, 8'h03);
        expect_prg(16'hA000, 19'h06000, "246: $6001 = PRG 8 KB en $A000");
        back_to_menu;

        start_game(8'd97, 5'b01111, C512, 8'd0);
        cpu_write(16'h8000, 8'h83);
        expect_prg(16'hC000, 19'h0C000, "97: D4-D0 = PRG 16 KB en $C000");
        expect_prg(16'h8000, 19'h3C000, "97: $8000 fijo al ultimo");
        expect_a10(14'h2400, 1, "97: D7 = 1 -> vertical");
        back_to_menu;

        start_game(8'd242, P512, CHR_RAM, 8'd0);
        cpu_write(16'h8028, 8'h00);
        expect_prg(16'h8000, 19'h28000, "242: A6-A3 = PRG 32 KB");
        back_to_menu;

        // ------------------------------------------------------------ lote 3
        // 28 Action 53: al encender, los últimos 16 KB en $C000 (NESdev)
        start_game(8'd28, P512, CHR_RAM, 8'd0);
        expect_prg(16'hC000, 19'h7C000, "28: al encender $C000 = ultimos 16 KB");
        cpu_write(16'h5000, 8'h81); cpu_write(16'h8000, 8'h03);   // banco exterior 3 (32 KB)
        cpu_write(16'h5000, 8'h80); cpu_write(16'h8000, 8'h1F);   // 64 KB, 16 KB, $C000 fijo, H
        cpu_write(16'h5000, 8'h01); cpu_write(16'h8000, 8'h01);   // banco interior 1
        expect_prg(16'h8000, 19'h14000, "28: 16 KB = exterior (sin su bit bajo) | interior");
        expect_prg(16'hC000, 19'h1C000, "28: ventana fija = exterior | 1");
        expect_a10(14'h2800, 1, "28: modo 3 -> horizontal");
        cpu_write(16'h5000, 8'h81); cpu_write(16'h8000, 8'h00);   // exterior 0
        cpu_write(16'h5000, 8'h01); cpu_write(16'h8000, 8'h06);   // interior 6: solo cuentan 2 bits (64 KB)
        expect_prg(16'h8000, 19'h08000, "28: el tamano del juego enmascara el banco interior");
        cpu_write(16'h5000, 8'h00); cpu_write(16'h8000, 8'h03);
        expect_chr(14'h0000, 19'h06000, "28: R0 = CHR-RAM de 8 KB (32 KB)");
        back_to_menu;

        // 30 UNROM 512: con pila (flash) el registro solo está en $C000-$FFFF
        start_game(8'd30, P512, CHR_RAM, 8'd2);
        cpu_write(16'h8000, 8'h05);
        expect_prg(16'h8000, 19'h00000, "30: con pila, $8000-$BFFF no es el registro");
        cpu_write(16'hC000, 8'h65);
        expect_prg(16'h8000, 19'h14000, "30: D4-D0 = PRG 16 KB");
        expect_prg(16'hC000, 19'h7C000, "30: $C000 fijo al ultimo");
        expect_chr(14'h0000, 19'h06000, "30: D6-D5 = CHR-RAM de 8 KB");
        back_to_menu;
        start_game(8'd30, P512, CHR_RAM, 8'd0);
        cpu_write(16'h8000, 8'h03);
        expect_prg(16'h8000, 19'h0C000, "30: sin pila, registro en $8000-$FFFF");
        back_to_menu;

        // 31 NSF: ventanas de 4 KB; PRG A12 sale del mapper
        start_game(8'd31, P512, CHR_RAM, 8'd0);
        expect_prg(16'hF000, 19'h7F000, "31: al encender $F000 = ultimo banco de 4 KB");
        cpu_write(16'h5002, 8'h07);
        expect_prg(16'hA400, 19'h07400, "31: $5002 = 4 KB en $A000");
        back_to_menu;

        // 51 BMC 11-in-1: modo 32 KB y ROM en $6000
        start_game(8'd51, P512, CHR_RAM, 8'd0);
        cpu_write(16'h6000, 8'h12);
        cpu_write(16'h8000, 8'h03);
        expect_prg(16'h8000, 19'h18000, "51: modo 32 KB");
        expect_prg(16'h6000, 19'h5E000, "51: ROM de 8 KB en $6000");
        back_to_menu;

        // 77 Irem LROG017: CHR-ROM 2 KB en $0000 y CHR-RAM en $0800-$1FFF
        start_game(8'd77, P512, C512, 8'h08);
        cpu_write(16'h8000, 8'h21);
        expect_prg(16'h8000, 19'h08000, "77: D3-D0 = PRG 32 KB");
        expect_chr(14'h0000, 19'h01000, "77: D7-D4 = CHR-ROM 2 KB en $0000");
        expect_chr(14'h0800, 19'h7C800, "77: $0800 = CHR-RAM propia");
        ppu_access(14'h0C00, 1);
        check(!chr_we_n, "77: la CHR-RAM se puede escribir");
        ppu_access(14'h0400, 1);
        check(chr_we_n, "77: la CHR-ROM no se escribe");
        ppu_access(14'h0000, 0);
        back_to_menu;

        // 96 Oeka Kids: CHR 4 KB de $0000 = A9-A8 de la última entrada en $2000-$2FFF
        start_game(8'd96, P512, CHR_RAM, 8'd0);
        cpu_write(16'h8000, 8'h04);
        ppu_access(14'h0000, 0); #100;
        ppu_access(14'h2100, 0); #100;
        expect_chr(14'h0000, 19'h05000, "96: $0000 = {D2, A9-A8 de la nametable}");
        expect_chr(14'h1000, 19'h07000, "96: $1000 = {D2, 11}");
        back_to_menu;

        // 103 Doki Doki Panic: ROM o RAM en $6000, segunda página de RAM en $B800-$D7FF
        start_game(8'd103, 5'b00111, CHR_RAM, 8'd0);
        expect_prg(16'h8000, 19'h18000, "103: $8000 = ultimos 32 KB");
        cpu_read(16'h6000);
        check(last_ram_ce && !last_prg_ce, "103: $6000 = RAM al encender");
        cpu_read(16'hB800);
        check(last_ram_ce && last_prg_addr == 19'h02000, "103: $B800 = pagina 1 de RAM");
        cpu_write(16'h8000, 8'h05);
        cpu_write(16'hF000, 8'h10);
        expect_prg(16'h6000, 19'h0A000, "103: $F000 D4 = ROM de 8 KB en $6000");
        expect_prg(16'hB800, 19'h1B800, "103: RAM apagada -> $B800 = ROM");
        cpu_write(16'hE000, 8'h08);
        expect_a10(14'h2800, 1, "103: $E000 D3 = 1 -> horizontal");
        back_to_menu;

        // 108: escrituras con A12 = 0 -> PRG de $6000 y CHR; con A12 = 1 -> solo CHR = D0
        start_game(8'd108, 5'b00111, C512, 8'd0);
        cpu_write(16'h8000, 8'h03);
        expect_prg(16'h6000, 19'h06000, "108: A12 = 0 -> PRG 8 KB en $6000");
        expect_chr(14'h0000, 19'h06000, "108: A12 = 0 -> CHR 8 KB");
        cpu_write(16'h9000, 8'h01);
        expect_chr(14'h0000, 19'h02000, "108: A12 = 1 -> CHR = D0");
        expect_prg(16'h6000, 19'h06000, "108: A12 = 1 no cambia la PRG de $6000");
        back_to_menu;

        // 164 Waixing: PRG 32 KB = {$5100, $5000}; al encender $0F
        start_game(8'd164, P512, CHR_RAM, 8'd0);
        expect_prg(16'h8000, 19'h78000, "164: al encender banco $0F");
        cpu_write(16'h5000, 8'h03); cpu_write(16'h5100, 8'h01);
        expect_prg(16'h8000, 19'h18000, "164: $5000 bits bajos, $5100 altos");
        back_to_menu;

        // 168 Racermate: IRQ cada 1024 ciclos; $C000 la reconoce
        start_game(8'd168, 5'b00011, CHR_RAM, 8'd0);
        cpu_write(16'hC000, 8'h00);
        check(irq_n === 1'b1, "168: $C000 reconoce la IRQ");
        cycles_to_irq(1100, c);
        check(c == 1023, "168: IRQ 1024 ciclos tras la escritura (contando la suya)");
        $display("      168: IRQ tras %0d ciclos", c);
        cpu_write(16'hC000, 8'h00);
        check(irq_n === 1'b1, "168: reconocida");
        cpu_write(16'h8000, 8'h45);
        expect_prg(16'h8000, 19'h04000, "168: D7-D6 = PRG 16 KB");
        expect_chr(14'h1000, 19'h05000, "168: D3-D0 = CHR-RAM 4 KB en $1000");
        cpu_write(16'hC000, 8'h00);
        expect_prg(16'h8000, 19'h04000, "168: $C000 (IRQ) no cambia los bancos");
        expect_chr(14'h1000, 19'h05000, "168: ni la CHR-RAM");
        back_to_menu;

        // 171 Kaiser 7058
        start_game(8'd171, P512, C512, 8'd0);
        cpu_write(16'hF000, 8'h03); cpu_write(16'hF080, 8'h05);
        expect_chr(14'h0000, 19'h03000, "171: $F000 = CHR 4 KB en $0000");
        expect_chr(14'h1000, 19'h05000, "171: $F080 = CHR 4 KB en $1000");
        back_to_menu;

        // 175 Kaiser 7022: el banco se aplica al leer $FFFC
        start_game(8'd175, P512, C512, 8'd0);
        cpu_write(16'hA000, 8'h03);
        cpu_read(16'hC123);                                 // otra lectura de ROM: no aplica el banco
        expect_prg(16'h8000, 19'h00000, "175: $A000 no cambia aun el banco");
        cpu_read(16'hFFFC);
        expect_prg(16'h8000, 19'h0C000, "175: leer $FFFC aplica el banco");
        expect_chr(14'h0000, 19'h06000, "175: y el de CHR");
        cpu_write(16'h8000, 8'h04);
        expect_a10(14'h2800, 1, "175: $8000 D2 = 1 -> horizontal");
        back_to_menu;

        // 190 Magic Kid Googoo
        start_game(8'd190, P512, C512, 8'd0);
        expect_chr(14'h1800, 19'h01800, "190: al encender, CHR lineal");
        cpu_write(16'h8000, 8'h03);
        expect_prg(16'h8000, 19'h0C000, "190: $8000-$9FFF = PRG 16 KB");
        cpu_write(16'hC000, 8'h02);
        expect_prg(16'h8000, 19'h28000, "190: $C000-$DFFF = 8 + D2-D0");
        expect_prg(16'hC000, 19'h00000, "190: $C000 fijo al banco 0");
        cpu_write(16'hA001, 8'h05);
        expect_chr(14'h0800, 19'h02800, "190: $A001 = CHR 2 KB en $0800");
        cpu_read(16'h7000);
        check(last_ram_ce, "190: PRG-RAM en $6000");
        back_to_menu;

        // 188 Karaoke Studio: $6000 = botones del micrófono (activos a nivel bajo): sin pulsar
        start_game(8'd188, 5'b01111, C512, 8'd0);
        expect_read(16'h6000, 8'h07, 8'h03, "188: $6000 -> A y B sin pulsar, sin sonido");
        expect_read(16'h8000, 8'h00, 8'h00, "188: la FPGA no conduce en la ROM");
        cpu_write(16'h8000, 8'h02);                                     // D4 = 0: ROM del casete
        cpu_read(16'h8000);
        check(last_prg_ce, "188: con 256 KB, el casete es la mitad alta de la ROM");
        check(last_prg_addr == 19'h28000, "188: banco del casete = 8 + D2-D0");
        back_to_menu;
        start_game(8'd188, 5'b00111, CHR_RAM, 8'd0);                   // 128 KB: sin casete
        cpu_write(16'h8000, 8'h02);
        cpu_read(16'h8000);
        check(!last_prg_ce, "188: sin casete (PRG de 128 KB) -> bus abierto");
        cpu_write(16'h8000, 8'h12);
        expect_prg(16'h8000, 19'h08000, "188: D4 = 1 -> ROM interna");
        back_to_menu;

        // 212: protección en $6000 (D7 = 1 con A4 = 0)
        start_game(8'd212, P512, C512, 8'd0);
        expect_read(16'h6000, 8'h80, 8'h80, "212: $6000 con A4 = 0 -> D7 = 1");
        expect_read(16'h6010, 8'h00, 8'h00, "212: $6010 (A4 = 1) -> nada");
        back_to_menu;

        // ------------------------------------------------------------ lote 4 (IRQ por ciclos: mapper_irqcpu)
        // Convención de los contadores: el ciclo de la escritura ya cuenta (como FME-7/VRC y Mesen2).
        start_game(8'd40, 5'b00011, 8'd0, 8'd0);
        expect_prg(16'h6000, 19'h0C000, "40: $6000 = banco 6");
        expect_prg(16'h8000, 19'h08000, "40: $8000 = banco 4");
        expect_prg(16'hE000, 19'h0E000, "40: $E000 = banco 7");
        cpu_write(16'hE000, 8'h02);
        expect_prg(16'hC000, 19'h04000, "40: $E000 = PRG 8 KB en $C000");
        cpu_write(16'hA000, 8'h00);
        cycles_to_irq(5000, c);
        check(c == 4095, "40: IRQ 4096 ciclos despues de arrancar");
        $display("      40: IRQ tras %0d ciclos", c);
        n = 0;
        while (irq_n === 1'b0 && n < 5000) begin cpu_read(16'h0000); n = n + 1; end
        check(n == 4096, "40: sin reconocer, la IRQ baja sola 4096 ciclos despues");
        cpu_write(16'h8000, 8'h00);
        repeat (5000) cpu_read(16'h0000);
        check(irq_n === 1'b1, "40: $8000 para el contador");
        back_to_menu;

        start_game(8'd42, 5'b00111, 8'b001111, 8'd0);
        expect_prg(16'h8000, 19'h18000, "42: $8000-$FFFF = ultimos 32 KB");
        cpu_write(16'hE000, 8'h05);
        expect_prg(16'h6000, 19'h0A000, "42: $E000 = PRG 8 KB en $6000");
        cpu_write(16'h8000, 8'h03);
        expect_chr(14'h0000, 19'h06000, "42: $8000 = CHR 8 KB");
        cpu_write(16'hE001, 8'h08);
        expect_a10(14'h2800, 1, "42: $E001 D3 = 1 -> horizontal");
        cpu_write(16'hE002, 8'h06);
        cycles_to_irq(30000, c);
        check(c == 24575, "42: IRQ con los dos bits altos del contador (24576 ciclos)");
        $display("      42: IRQ tras %0d ciclos", c);
        cpu_write(16'hE002, 8'h00);
        check(irq_n === 1'b1, "42: $E002 D1 = 0 la reconoce");
        back_to_menu;

        start_game(8'd50, 5'b00111, 8'd0, 8'd0);
        expect_prg(16'h6000, 19'h1E000, "50: $6000 = banco 15");
        expect_prg(16'hA000, 19'h12000, "50: $A000 = banco 9");
        expect_prg(16'hE000, 19'h16000, "50: $E000 = banco 11");
        cpu_write(16'h4020, 8'h0B);
        expect_prg(16'hC000, 19'h1A000, "50: banco de $C000 = {D3, D0, D2, D1}");
        cpu_write(16'h4000, 8'h00);
        expect_prg(16'hC000, 19'h1A000, "50: $4000 (A5 = 0) no es el registro");
        cpu_write(16'h4120, 8'h01);
        cycles_to_irq(5000, c);
        check(c == 4095, "50: IRQ 4096 ciclos despues de arrancar");
        cpu_write(16'h4120, 8'h00);
        check(irq_n === 1'b1, "50: D0 = 0 la reconoce");
        back_to_menu;

        start_game(8'd73, 5'b00111, CHR_RAM, 8'd0);
        cpu_write(16'hF000, 8'h03);
        expect_prg(16'h8000, 19'h0C000, "73: $F000 = PRG 16 KB en $8000");
        expect_prg(16'hC000, 19'h1C000, "73: $C000 fijo al ultimo");
        cpu_read(16'h6000);
        check(last_ram_ce, "73: PRG-RAM en $6000");
        cpu_write(16'h8000, 8'h00); cpu_write(16'h9000, 8'h00);
        cpu_write(16'hA000, 8'h0F); cpu_write(16'hB000, 8'h0F);       // recarga $FF00
        cpu_write(16'hC000, 8'h02);
        cycles_to_irq(1000, c);
        check(c == 255, "73: 16 bits: IRQ al desbordar desde la recarga");
        $display("      73: IRQ tras %0d ciclos", c);
        cpu_write(16'hD000, 8'h00);
        check(irq_n === 1'b1, "73: $D000 la reconoce");
        repeat (300) cpu_read(16'h0000);
        check(irq_n === 1'b1, "73: $D000 con A = 0 la deja parada");
        cpu_write(16'h8000, 8'h00); cpu_write(16'h9000, 8'h0F);       // recarga $00F0
        cpu_write(16'hA000, 8'h00); cpu_write(16'hB000, 8'h00);
        cpu_write(16'hC000, 8'h06);
        cycles_to_irq(1000, c);
        check(c == 15, "73: 8 bits: solo cuentan los 8 bajos");
        cpu_write(16'hC000, 8'h00);
        back_to_menu;

        start_game(8'd106, 5'b01111, 8'b001111, 8'd0);
        cpu_write(16'h8008, 8'h03);
        expect_prg(16'h8000, 19'h26000, "106: $8008 = banco + 16 en $8000");
        cpu_write(16'h8009, 8'h12);
        expect_prg(16'hA000, 19'h24000, "106: $8009 = 5 bits en $A000");
        cpu_write(16'hFFFB, 8'h01);
        expect_prg(16'hE000, 19'h22000, "106: registros repetidos cada 16 bytes ($800B)");
        cpu_write(16'h8000, 8'h05);
        expect_chr(14'h0000, 19'h01000, "106: $8000 con el bit 0 a 0");
        cpu_write(16'h8001, 8'h04);
        expect_chr(14'h0400, 19'h01400, "106: $8001 con el bit 0 a 1");
        cpu_write(16'h8004, 8'h09);
        expect_chr(14'h1000, 19'h02400, "106: $8004 = CHR 1 KB en $1000");
        cpu_write(16'h800C, 8'h01);
        expect_a10(14'h2800, 1, "106: $800C D0 = 1 -> horizontal");
        cpu_write(16'h800E, 8'hF0); cpu_write(16'h800F, 8'hFF);
        cycles_to_irq(100, c);                                       // el contador sigue contando entre $800E y $800F
        check(c == 13, "106: IRQ con el contador en $FFFF");
        $display("      106: IRQ tras %0d ciclos", c);
        repeat (20) cpu_read(16'h0000);
        check(irq_n === 1'b0, "106: el contador se queda en $FFFF");
        cpu_write(16'h800D, 8'h00);
        check(irq_n === 1'b1, "106: $800D la reconoce");
        back_to_menu;

        start_game(8'd142, 5'b00111, CHR_RAM, 8'd0);
        cpu_write(16'hE000, 8'h01); cpu_write(16'hF000, 8'h03);
        expect_prg(16'h8000, 19'h06000, "142: registro 1 = PRG 8 KB en $8000");
        cpu_write(16'hE000, 8'h04); cpu_write(16'hF000, 8'h05);
        expect_prg(16'h6000, 19'h0A000, "142: registro 4 = ROM 8 KB en $6000");
        expect_prg(16'hE000, 19'h1E000, "142: $E000 fijo al ultimo");
        cpu_write(16'h8000, 8'h00); cpu_write(16'h9000, 8'h0F);
        cpu_write(16'hA000, 8'h0F); cpu_write(16'hB000, 8'h0F);       // recarga $FFF0
        cpu_write(16'hC000, 8'h02);
        cycles_to_irq(100, c);
        check(c == 14, "142: IRQ al llegar a $FFFF");
        cpu_write(16'hD000, 8'h00);
        check(irq_n === 1'b1, "142: $D000 la reconoce");
        back_to_menu;

        if (errors == 0) $display("OK: todas las pruebas pasaron (fase 4)");
        else             $display("FALLARON %0d comprobaciones (fase 4)", errors);
        $finish;
    end

endmodule
