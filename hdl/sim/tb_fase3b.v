// tb_fase3b.v — Testbench autoverificable de la fase 3b: VRC2/VRC4 (21, 22, 23, 25), FME-7 (69),
// Jaleco SS88006 (18), Bandai FCG (16), MMC2/MMC4 (9, 10), Namco 175/340 (210) y TxSROM (118).
// Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_fase3b;

`include "tb_bus.vh"

    integer n;

    // Ciclos de CPU (lecturas de RAM) hasta que /IRQ baja; -1 si no baja en 'max' ciclos.
    task cycles_to_irq(input integer max, output integer cycles);
        begin
            cycles = -1;
            for (n = 1; n <= max && cycles < 0; n = n + 1) begin
                cpu_read(16'h0000);
                if (irq_n === 1'b0) cycles = n;
            end
        end
    endtask

    // Lectura de la PPU con fin de /RD (flanco de subida), como hace la consola.
    task ppu_read(input [13:0] addr);
        begin
            // tiempos de la consola: /RD alto entre accesos (ALE), ~186 ns bajo, y alto después.
            // expect_chr deja /RD bajo: sin la fase alta, dos lecturas seguidas serían una sola.
            ppu_rd_n = 1; ppu_wr_n = 1; #100;
            ppu_a = addr; ppu_rd_n = 0; #180;
            ppu_rd_n = 1; #180;
        end
    endtask

    // Un acceso de la PPU con sus tiempos reales: 1 punto con /RD alto (ALE) y 1 punto con /RD bajo.
    task ppu_fetch(input [13:0] addr);
        begin
            ppu_a = addr; ppu_wr_n = 1; ppu_rd_n = 1; #186;
            ppu_rd_n = 0; #186;
            ppu_rd_n = 1;
        end
    endtask

    integer c;

    initial begin
        repeat (4) cpu_read(16'h0000);

        // ================================================= VRC2b/VRC4e (23): 256 KB PRG, 256 KB CHR
        start_game(8'd23, 5'b01111, 8'b011111, 8'd0);
        expect_prg(16'hC000, 19'h3C000, "23: $C000 = penultimo");
        expect_prg(16'hE000, 19'h3E000, "23: $E000 = ultimo");
        cpu_write(16'h8000, 8'h05);
        cpu_write(16'hA000, 8'h09);
        expect_prg(16'h8000, 19'h0A000, "23: PRG0 = 5");
        expect_prg(16'hA000, 19'h12000, "23: PRG1 = 9");
        cpu_write(16'hB000, 8'h03); cpu_write(16'hB001, 8'h12);     // CHR0 = $123 -> 9 bits
        cpu_write(16'hB002, 8'h04); cpu_write(16'hB003, 8'h00);     // CHR1 = $004
        cpu_write(16'hE002, 8'h0F); cpu_write(16'hE003, 8'h01);     // CHR7 = $1F
        expect_chr(14'h0000, 19'h08C00, "23: CHR0 nibbles ($123 enmascarado a 256 KB = $23)");
        expect_chr(14'h0400, 19'h01000, "23: CHR1 = 4");
        expect_chr(14'h1C00, 19'h07C00, "23: CHR7 = $1F");
        cpu_write(16'h9000, 8'h01);
        expect_a10(14'h2800, 1, "23: mirroring H");
        cpu_write(16'h9002, 8'h02);                                  // en 23, $9002 también es mirroring
        expect_a10(14'h2800, 0, "23: $9002 = mirroring (pantalla A; en H $2800 daria 1)");
        cpu_write(16'h9004, 8'h03);                                  // A2 (VRC4e) = A0
        expect_a10(14'h2000, 1, "23: A2 equivale a A0 (pantalla B)");
        // IRQ modo ciclo: recarga $FC, cuenta FC->FD->FE->FF y en el 4.º pulso recarga y dispara
        cpu_write(16'hF000, 8'h0C); cpu_write(16'hF001, 8'h0F);     // recarga = $FC
        cpu_write(16'hF002, 8'h06);                                  // activa, modo ciclo
        cycles_to_irq(20, c);
        check(c == 3, "23: IRQ modo ciclo al 4.o pulso");
        if (c != 3) $display("      ciclos hasta IRQ: %0d", c);
        cpu_write(16'hF003, 8'h00);                                  // reconocer
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "23: $F003 reconoce la IRQ");
        // modo scanline: un pulso cada 341/3 ciclos
        cpu_write(16'hF000, 8'h0F); cpu_write(16'hF001, 8'h0F);     // recarga = $FF
        cpu_write(16'hF002, 8'h02);                                  // activa, modo scanline
        cycles_to_irq(300, c);
        check(c >= 110 && c <= 116, "23: IRQ modo scanline a ~114 ciclos");
        $display("      ciclos hasta IRQ (scanline): %0d", c);
        cpu_write(16'hF002, 8'h00);
        back_to_menu;

        // ================================================= VRC4a/c (21): modo PRG y A6/A7
        start_game(8'd21, 5'b01111, 8'b011111, 8'd1);
        cpu_write(16'h8000, 8'h05);
        cpu_write(16'h9004, 8'h02);                                  // A2 -> A1: modo PRG 1
        expect_prg(16'h8000, 19'h3C000, "21: modo 1, $8000 = penultimo");
        expect_prg(16'hC000, 19'h0A000, "21: modo 1, $C000 = PRG0");
        cpu_write(16'h9080, 8'h00);                                  // A7 -> A1 (VRC4c): modo 0
        expect_prg(16'h8000, 19'h0A000, "21: A7 (VRC4c) = A1, modo 0");
        cpu_write(16'hB040, 8'h07);                                  // A6 -> A0: CHR0 nibble alto
        expect_chr(14'h0000, 19'h1C000, "21: A6 (VRC4c) = A0 -> nibble alto");
        back_to_menu;

        // ================================================= VRC4b/d (25): A0/A1 cruzados
        start_game(8'd25, 5'b01111, 8'b011111, 8'd0);
        cpu_write(16'hB002, 8'h01);                                  // A1 -> A0: nibble alto de CHR0
        expect_chr(14'h0000, 19'h04000, "25: A1 = A0 (nibble alto: banco $10)");
        cpu_write(16'hB001, 8'h03);                                  // A0 -> A1: CHR1 nibble bajo
        expect_chr(14'h0400, 19'h00C00, "25: A0 = A1 (registro siguiente)");
        back_to_menu;

        // ================================================= VRC2a (22): CHR >> 1, sin IRQ
        start_game(8'd22, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'hB000, 8'h06);                                  // CHR0 = 6 -> 3
        expect_chr(14'h0000, 19'h00C00, "22: CHR desplazado un bit");
        // en el 22 A0/A1 van cruzados: el control de IRQ de un VRC4 estaría en $F001
        cpu_write(16'hF000, 8'h0F); cpu_write(16'hF002, 8'h0F);     // recarga $FF (A1->A0)
        cpu_write(16'hF001, 8'h06);                                  // control (A0->A1)
        cycles_to_irq(40, c);
        check(c == -1, "22: VRC2 sin IRQ");
        back_to_menu;

        // ================================================= FME-7 (69)
        start_game(8'd69, 5'b01111, 8'b011111, 8'd0);
        expect_prg(16'hE000, 19'h3E000, "69: $E000 fijo al ultimo");
        cpu_write(16'h8000, 8'h09); cpu_write(16'hA000, 8'h05);
        cpu_write(16'h8000, 8'h0B); cpu_write(16'hA000, 8'h07);
        expect_prg(16'h8000, 19'h0A000, "69: cmd 9 -> $8000 = 5");
        expect_prg(16'hC000, 19'h0E000, "69: cmd B -> $C000 = 7");
        cpu_write(16'h8000, 8'h03); cpu_write(16'hA000, 8'h21);
        expect_chr(14'h0C00, 19'h08400, "69: CHR3 = $21");
        cpu_write(16'h8000, 8'h08); cpu_write(16'hA000, 8'h03);     // ROM 3 en $6000
        expect_prg(16'h6000, 19'h06000, "69: ROM en $6000");
        cpu_write(16'h8000, 8'h08); cpu_write(16'hA000, 8'hC1);     // RAM banco 1, habilitada
        cpu_write(16'h6010, 8'h55);
        check(last_ram_ce && last_ram_we && last_prg_addr == 19'h02010, "69: PRG-RAM banco 1");
        cpu_write(16'h8000, 8'h08); cpu_write(16'hA000, 8'h40);     // RAM sin habilitar
        cpu_write(16'h6010, 8'h55);
        check(!last_ram_ce && !last_prg_ce, "69: RAM deshabilitada -> nada");
        cpu_write(16'h8000, 8'h0C); cpu_write(16'hA000, 8'h03);
        expect_a10(14'h2000, 1, "69: pantalla B");
        // IRQ: contador 5; dispara al pasar de 0 a $FFFF (6.º pulso)
        cpu_write(16'h8000, 8'h0E); cpu_write(16'hA000, 8'h05);
        cpu_write(16'h8000, 8'h0F); cpu_write(16'hA000, 8'h00);
        cpu_write(16'h8000, 8'h0D); cpu_write(16'hA000, 8'h81);
        cycles_to_irq(20, c);
        check(c == 5, "69: IRQ al pasar de 0 a $FFFF");
        if (c != 5) $display("      ciclos hasta IRQ: %0d", c);
        cpu_write(16'h8000, 8'h0D); cpu_write(16'hA000, 8'h00);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "69: cmd D reconoce");
        back_to_menu;

        // ================================================= Jaleco SS88006 (18)
        start_game(8'd18, 5'b01111, 8'b011111, 8'd1);
        cpu_write(16'h8000, 8'h05); cpu_write(16'h8001, 8'h01);     // PRG0 = $15 -> 21
        cpu_write(16'h9000, 8'h03);                                  // PRG2 = 3
        expect_prg(16'h8000, 19'h2A000, "18: PRG0 por nibbles ($15)");
        expect_prg(16'hC000, 19'h06000, "18: PRG2 en $C000");
        expect_prg(16'hE000, 19'h3E000, "18: $E000 fijo");
        cpu_write(16'hD002, 8'h09); cpu_write(16'hD003, 8'h02);     // CHR7 = $29
        expect_chr(14'h1C00, 19'h0A400, "18: CHR7 = $29");
        cpu_write(16'hF002, 8'h00);
        expect_a10(14'h2800, 1, "18: mirroring H");
        // IRQ de 4 bits: recarga 3 -> dispara al llegar a 0 (3 pulsos)
        cpu_write(16'hE000, 8'h03); cpu_write(16'hE001, 8'h01);     // recarga $0013
        cpu_write(16'hE002, 8'h00); cpu_write(16'hE003, 8'h00);
        cpu_write(16'hF000, 8'h00);                                  // recarga
        cpu_write(16'hF001, 8'h09);                                  // activa, 4 bits
        cycles_to_irq(20, c);
        check(c == 2, "18: IRQ de 4 bits a los 3 pulsos (solo el nibble bajo de $13)");
        if (c != 2) $display("      ciclos hasta IRQ: %0d", c);
        cpu_write(16'hF000, 8'h00);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "18: $F000 reconoce");
        cpu_write(16'hF001, 8'h00);
        back_to_menu;

        // ================================================= Bandai FCG (16)
        start_game(8'd16, 5'b01111, 8'b011111, 8'd0);
        cpu_write(16'h6008, 8'h05);                                  // rango $6000 (FCG-1/2)
        expect_prg(16'h8000, 19'h14000, "16: PRG 16 KB = 5 via $6008");
        expect_prg(16'hC000, 19'h3C000, "16: $C000 fijo");
        cpu_write(16'h8003, 8'h21);                                  // rango $8000 (LZ93D50)
        expect_chr(14'h0C00, 19'h08400, "16: CHR3 via $8003");
        cpu_write(16'h8009, 8'h01);
        expect_a10(14'h2800, 1, "16: mirroring H");
        cpu_write(16'h6010, 8'h55);
        check(!last_ram_ce, "16: sin PRG-RAM");
        // IRQ: recarga 2; $0A copia y activa; dispara cuando el contador vale 0 (3.er pulso)
        cpu_write(16'h800B, 8'h02); cpu_write(16'h800C, 8'h00);
        cpu_write(16'h800A, 8'h01);
        cycles_to_irq(20, c);
        check(c == 2, "16: IRQ con el contador a 0");
        if (c != 2) $display("      ciclos hasta IRQ: %0d", c);
        cpu_write(16'h800A, 8'h00);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "16: $0A reconoce");
        back_to_menu;

        // ================================================= MMC2 (9)
        start_game(8'd9, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'hA000, 8'h03);
        expect_prg(16'h8000, 19'h06000, "9: PRG 8 KB = 3");
        expect_prg(16'hA000, 19'h1A000, "9: $A000 = antepenultimo");
        expect_prg(16'hE000, 19'h1E000, "9: $E000 = ultimo");
        cpu_write(16'hB000, 8'h04);                                  // izq FD = 4
        cpu_write(16'hC000, 8'h05);                                  // izq FE = 5
        cpu_write(16'hD000, 8'h06);                                  // der FD = 6
        cpu_write(16'hE000, 8'h07);                                  // der FE = 7
        expect_chr(14'h0123, 19'h05123, "9: latch izq. arranca en FE");
cpu_read(16'h0000);                                          // M2 sigue (sin M2 > 2,5 us = reset)
        ppu_rd_n = 1; #100;
        ppu_a = 14'h0FD8; ppu_wr_n = 1; ppu_rd_n = 0; #180;         // la lectura disparadora...
        check(chr_addr_now == 19'h05FD8, "9: la lectura de $0FD8 usa aun el banco FE");
        ppu_rd_n = 1; #20;                                           // ...no cambia nada mientras
        check(chr_addr_now == 19'h05FD8, "9: el latch espera a /RD estable alto");
        #160;                                                        // ...y al terminar cambia
        expect_chr(14'h0123, 19'h04123, "9: tras leer $0FD8 -> FD");
        cpu_read(16'h0000);                                          // M2 sigue (sin M2 > 2,5 us = reset)
        // la direccion cambia justo al subir /RD (ALE del acceso siguiente): debe contar la de la lectura
        ppu_rd_n = 1; #100;
        ppu_a = 14'h0FE8; ppu_rd_n = 0; #180;
        ppu_a = 14'h2000; ppu_rd_n = 1; #180;
        expect_chr(14'h0123, 19'h05123, "9: $0FE8 cuenta aunque la direccion cambie al subir /RD");
        cpu_read(16'h0000);                                          // M2 sigue (sin M2 > 2,5 us = reset)
        // un rebote alto de /RD en mitad de la lectura no aplica el latch antes de tiempo
        ppu_rd_n = 1; #100;
        ppu_a = 14'h0FD8; ppu_rd_n = 0; #180;
        ppu_rd_n = 1; #30; ppu_rd_n = 0; #100;
        check(chr_addr_now == 19'h05FD8, "9: un rebote alto de /RD no cambia el banco a mitad de lectura");
        ppu_rd_n = 1; #180;
        expect_chr(14'h0123, 19'h04123, "9: ...y al terminar la lectura si cambia a FD");
        cpu_read(16'h0000);
        ppu_read(14'h0FE8);                                          // se deja el latch en FE
        cpu_read(16'h0000);
        // un pulso corto de /RD (rebote, < 40 ns) no dispara
        ppu_rd_n = 1; #100;
        ppu_a = 14'h0FD8; ppu_rd_n = 0; #20; ppu_rd_n = 1; #180;
        expect_chr(14'h0123, 19'h05123, "9: un rebote de /RD no dispara");
        cpu_read(16'h0000);                                          // M2 sigue (sin M2 > 2,5 us = reset)
        // una lectura en otra direccion entre medias no borra la pendiente: se aplica al terminar
        ppu_rd_n = 1; #100;
        ppu_a = 14'h0FD8; ppu_rd_n = 0; #180;
        ppu_a = 14'h1FE8; #10; ppu_rd_n = 1; #180;
        expect_chr(14'h0123, 19'h04123, "9: $0FD8 -> FD (dir. cambia tras capturar)");
        cpu_read(16'h0000);                                          // M2 sigue (sin M2 > 2,5 us = reset)
        // Secuencia real de la PPU (una lectura cada 372 ns: 186 ns ALE con /RD alto + 186 ns /RD bajo),
        // con la CPU funcionando a la vez: tras el tile disparador ($0FE8, plano alto) el siguiente
        // tile de patrón (3 accesos después) ya usa el banco nuevo.
        fork
            begin
                ppu_fetch(14'h2000); ppu_fetch(14'h23C0); ppu_fetch(14'h0FE0); ppu_fetch(14'h0FE8);
                ppu_fetch(14'h2001); ppu_fetch(14'h23C0);
                ppu_a = 14'h0120; ppu_rd_n = 1; #186; ppu_rd_n = 0; #93;
                check(chr_addr_now == 19'h05120, "9: tile siguiente al $0FE8 ya en FE (tiempos reales)");
                #93; ppu_rd_n = 1;
                ppu_fetch(14'h0128);
                ppu_fetch(14'h2002); ppu_fetch(14'h23C0); ppu_fetch(14'h0FD0); ppu_fetch(14'h0FD8);
                ppu_fetch(14'h2003); ppu_fetch(14'h23C0);
                ppu_a = 14'h0130; ppu_rd_n = 1; #186; ppu_rd_n = 0; #93;
                check(chr_addr_now == 19'h04130, "9: tile siguiente al $0FD8 ya en FD (tiempos reales)");
                #93; ppu_rd_n = 1;
            end
            begin
                repeat (12) cpu_read(16'h0000);
            end
        join
        cpu_read(16'h0000);
        ppu_read(14'h0FE9);                                          // MMC2: solo $0FE8 exacto
        expect_chr(14'h0123, 19'h04123, "9: $0FE9 no dispara (MMC2)");
        cpu_read(16'h0000);                                          // M2 sigue (sin M2 > 2,5 us = reset)
        ppu_read(14'h0FE8);
        expect_chr(14'h0123, 19'h05123, "9: $0FE8 -> FE");
        cpu_read(16'h0000);                                          // M2 sigue (sin M2 > 2,5 us = reset)
        ppu_read(14'h1FDB);
        expect_chr(14'h1123, 19'h06123, "9: $1FDB (rango) -> der. FD");
        cpu_read(16'h0000);                                          // M2 sigue (sin M2 > 2,5 us = reset)
        cpu_write(16'hF000, 8'h01);
        expect_a10(14'h2800, 1, "9: $F000 = horizontal");
        back_to_menu;

        // ================================================= MMC4 (10)
        start_game(8'd10, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'hA000, 8'h02);
        expect_prg(16'h8000, 19'h08000, "10: PRG 16 KB = 2");
        expect_prg(16'hC000, 19'h1C000, "10: $C000 fijo");
        cpu_write(16'hB000, 8'h04); cpu_write(16'hC000, 8'h05);
        ppu_read(14'h0FDC);                                          // MMC4: rango
        expect_chr(14'h0123, 19'h04123, "10: $0FDC (rango) -> FD");
        cpu_write(16'h6000, 8'h11);
        check(last_ram_ce && last_ram_we, "10: PRG-RAM");
        back_to_menu;

        // ================================================= Namco 175/340 (210)
        start_game(8'd210, 5'b00111, 8'b001111, 8'd1);
        cpu_write(16'h8800, 8'h12);                                  // CHR1
        cpu_write(16'hE000, 8'h05); cpu_write(16'hE800, 8'h06); cpu_write(16'hF000, 8'h07);
        expect_chr(14'h0400, 19'h04800, "210: CHR1 = $12");
        expect_prg(16'h8000, 19'h0A000, "210: $8000 = 5");
        expect_prg(16'hC000, 19'h0E000, "210: $C000 = 7");
        expect_prg(16'hE000, 19'h1E000, "210: $E000 fijo");
        expect_a10(14'h2400, 1, "210: sin detectar -> cabecera");
        cpu_write(16'h6000, 8'h11);
        check(!last_ram_ce, "210: sin detectar -> sin PRG-RAM");
        cpu_write(16'hC000, 8'h01);                                  // -> Namco 175, escritura permitida
        cpu_write(16'h6000, 8'h11);
        check(last_ram_ce && last_ram_we, "210: 175 con escritura en PRG-RAM");
        back_to_menu;
        start_game(8'd210, 5'b00111, 8'b001111, 8'd1);
        cpu_write(16'hE000, 8'h85);                                  // D7 -> Namco 340, horizontal
        expect_a10(14'h2800, 1, "210: 340 mirroring H");
        cpu_write(16'hE000, 8'h05);                                  // D7-D6 = 0 -> pantalla A
        expect_a10(14'h2C00, 0, "210: 340 pantalla A");
        back_to_menu;
        // Wagyan Land 2: cabecera horizontal y solo D7-D6 = 01 (vertical) en $E000 -> 340 por D6
        start_game(8'd210, 5'b00111, 8'b001111, 8'd0);
        expect_a10(14'h2400, 0, "210: cabecera horizontal");
        cpu_write(16'hE000, 8'h64);
        expect_a10(14'h2400, 1, "210: D6 en $E000 -> 340 vertical (Wagyan Land 2)");
        // un 175 que escribe D6 antes de $C000 (Family Circuit '91): $C000 manda, PRG-RAM y cabecera
        cpu_write(16'hC000, 8'h01);
        expect_a10(14'h2400, 0, "210: $C000 -> 175, mirroring de cabecera");
        cpu_write(16'h6000, 8'h11);
        check(last_ram_ce && last_ram_we, "210: 175 tras ver D6 conserva la PRG-RAM");
        back_to_menu;

        // ================================================= TxSROM (118)
        start_game(8'd118, 5'b00111, 8'b001111, 8'd1);
        cpu_write(16'h8000, 8'h00); cpu_write(16'h8001, 8'h80);     // R0 bit 7 = 1
        cpu_write(16'h8000, 8'h01); cpu_write(16'h8001, 8'h00);     // R1 bit 7 = 0
        expect_a10(14'h2000, 1, "118: $2000 <- R0 bit 7");
        expect_a10(14'h2400, 1, "118: $2400 <- R0 bit 7");
        expect_a10(14'h2800, 0, "118: $2800 <- R1 bit 7");
        cpu_write(16'hA000, 8'h00);                                  // $A000 no tiene efecto
        expect_a10(14'h2800, 0, "118: $A000 ignorado");
        cpu_write(16'h8000, 8'h82); cpu_write(16'h8001, 8'h80);     // inversión: R2 -> $2000
        cpu_write(16'h8000, 8'h83); cpu_write(16'h8001, 8'h00);     // R3 -> $2400
        expect_a10(14'h2000, 1, "118: invertido $2000 <- R2");
        expect_a10(14'h2400, 0, "118: invertido $2400 <- R3");
        back_to_menu;

        check(cpu_d === 8'hzz && ppu_d === 8'hzz, "buses de datos en Z");
        if (errors == 0) $display("OK: todas las pruebas pasaron (fase 3b)");
        else             $display("ERRORES: %0d", errors);
        $finish;
    end

endmodule
