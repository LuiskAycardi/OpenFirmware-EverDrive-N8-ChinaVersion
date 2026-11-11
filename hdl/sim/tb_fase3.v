// tb_fase3.v — Testbench autoverificable de la fase 3a: mappers 11, 33, 34, 66, 70, 71, 79,
// 86, 87, 113, 140, 146, 148, 152, 184, 206 y 232. Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_fase3;

`include "tb_bus.vh"

    task expect_no_ram(input [15:0] addr, input [8*64-1:0] msg);
        begin
            cpu_write(addr, 8'h5A);
            check(!last_ram_ce && !last_ram_we, msg);
        end
    endtask

    initial begin
        repeat (4) cpu_read(16'h0000);

        // ------------------------------------------------ 11 Color Dreams: 128 KB PRG, 128 KB CHR
        start_game(8'd11, 5'b00111, 8'b001111, 8'd1);
        cpu_write(16'hFFFF, 8'h52);                       // CHR 5, PRG 2
        expect_prg(16'h8000, 19'h10000, "11: PRG 32 KB banco 2");
        expect_prg(16'hC123, 19'h14123, "11: PRG banco 2, mitad alta");
        expect_chr(14'h0123, 19'h0A123, "11: CHR 8 KB banco 5");
        expect_a10(14'h2400, 1, "11: mirroring de cabecera");
        back_to_menu;
        start_game(8'd11, 5'b00111, CHR_RAM, 8'd0);
        cpu_write(16'h8000, 8'hF0);
        expect_chr(14'h1123, 19'h01123, "11: CHR-RAM recortada a 8 KB");
        back_to_menu;

        // ------------------------------------------------ 66 GxROM
        start_game(8'd66, 5'b00111, 8'b000011, 8'd0);
        cpu_write(16'h8000, 8'h21);
        expect_prg(16'h8000, 19'h10000, "66: PRG 32 KB banco 2");
        expect_chr(14'h0000, 19'h02000, "66: CHR 8 KB banco 1");
        expect_no_ram(16'h6000, "66: sin PRG-RAM");
        back_to_menu;

        // ------------------------------------------------ 79 NINA-03/06 y 146
        start_game(8'd79, 5'b00011, 8'b000111, 8'd0);
        cpu_write(16'h4100, 8'h0D);
        expect_prg(16'h8000, 19'h08000, "79: PRG banco 1");
        expect_chr(14'h0000, 19'h0A000, "79: CHR banco 5");
        cpu_write(16'h4000, 8'h00);                       // A8 = 0: no es el registro
        expect_chr(14'h0000, 19'h0A000, "79: $4000 (A8=0) se ignora");
        cpu_write(16'h8000, 8'h00);                       // $8000: no es el registro
        expect_prg(16'h8000, 19'h08000, "79: $8000 se ignora");
        cpu_write(16'h5FFF, 8'h02);
        expect_chr(14'h0000, 19'h04000, "79: $5FFF (A8=1) es el registro");
        back_to_menu;
        start_game(8'd146, 5'b00011, 8'b000111, 8'd0);
        cpu_write(16'h4100, 8'h0B);
        expect_prg(16'hC000, 19'h0C000, "146: igual que el 79 (PRG 1)");
        expect_chr(14'h0000, 19'h06000, "146: CHR 3");
        back_to_menu;

        // ------------------------------------------------ 113 HES
        start_game(8'd113, 5'b01111, 8'b001111, 8'd0);
        expect_a10(14'h2800, 1, "113: horizontal de cabecera al arrancar");
        cpu_write(16'h4100, 8'hDD);                       // V, PRG 3, CHR {1,101} = 13
        expect_prg(16'h8000, 19'h18000, "113: PRG 3");
        expect_chr(14'h0000, 19'h1A000, "113: CHR 13 (bit D6 alto)");
        expect_a10(14'h2400, 1, "113: D7 = vertical");
        back_to_menu;

        // ------------------------------------------------ 148 Sachen SA-0037
        start_game(8'd148, 5'b00011, 8'b000111, 8'd0);
        cpu_write(16'h8000, 8'h0E);
        expect_prg(16'h8000, 19'h08000, "148: PRG 1");
        expect_chr(14'h0000, 19'h0C000, "148: CHR 6");
        back_to_menu;

        // ------------------------------------------------ 87 Jaleco (bits cruzados)
        start_game(8'd87, 5'b00001, 8'b000011, 8'd0);
        cpu_write(16'h6000, 8'h01);
        expect_chr(14'h0000, 19'h04000, "87: D0 -> banco 2");
        cpu_write(16'h7FFF, 8'h02);
        expect_chr(14'h0000, 19'h02000, "87: D1 -> banco 1");
        expect_prg(16'hC010, 19'h04010, "87: PRG fijo");
        expect_no_ram(16'h6000, "87: $6000 es registro, sin PRG-RAM");
        back_to_menu;

        // ------------------------------------------------ 140 Jaleco JF-11/14
        start_game(8'd140, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h6000, 8'h23);
        expect_prg(16'h8000, 19'h10000, "140: PRG 2");
        expect_chr(14'h0000, 19'h06000, "140: CHR 3");
        back_to_menu;

        // ------------------------------------------------ 86 Jaleco JF-13
        start_game(8'd86, 5'b00111, 8'b000111, 8'd0);
        cpu_write(16'h6000, 8'h61);                       // PRG 2, CHR {1,01} = 5
        expect_prg(16'h8000, 19'h10000, "86: PRG 2");
        expect_chr(14'h0000, 19'h0A000, "86: CHR 5 (D6 = bit alto)");
        cpu_write(16'h7000, 8'h00);                       // chip de voz: no toca bancos
        expect_chr(14'h0000, 19'h0A000, "86: $7000 no cambia los bancos");
        back_to_menu;

        // ------------------------------------------------ 184 Sunsoft-1
        start_game(8'd184, 5'b00001, 8'b000011, 8'd0);
        cpu_write(16'h6000, 8'h53);
        expect_chr(14'h0123, 19'h03123, "184: $0000 = banco 4 KB 3");
        expect_chr(14'h1123, 19'h05123, "184: $1000 = banco 4 KB 5");
        back_to_menu;

        // ------------------------------------------------ 70 Bandai
        start_game(8'd70, 5'b00111, 8'b001111, 8'd1);
        cpu_write(16'h8000, 8'h35);
        expect_prg(16'h8000, 19'h0C000, "70: PRG 16 KB 3 en $8000");
        expect_prg(16'hC000, 19'h1C000, "70: $C000 fijo al ultimo");
        expect_chr(14'h0000, 19'h0A000, "70: CHR 5");
        expect_a10(14'h2400, 1, "70: cabecera hasta que D7 = 1");
        cpu_write(16'h8000, 8'hB5);                       // D7 = 1: pantalla única B
        expect_a10(14'h2000, 1, "70: D7 activa pantalla unica (B)");
        cpu_write(16'h8000, 8'h35);
        expect_a10(14'h2400, 0, "70: sigue en pantalla unica (A)");
        back_to_menu;

        // ------------------------------------------------ 152 Bandai (pantalla única)
        start_game(8'd152, 5'b00111, 8'b001111, 8'd1);
        cpu_write(16'h8000, 8'hA3);
        expect_prg(16'h8000, 19'h08000, "152: PRG 2");
        expect_chr(14'h0000, 19'h06000, "152: CHR 3");
        expect_a10(14'h2000, 1, "152: pantalla B");
        cpu_write(16'h8000, 8'h23);
        expect_a10(14'h2C00, 0, "152: pantalla A");
        back_to_menu;

        // ------------------------------------------------ 71 Camerica
        start_game(8'd71, 5'b01111, CHR_RAM, 8'd1);
        cpu_write(16'hC000, 8'h05);
        expect_prg(16'h8000, 19'h14000, "71: PRG 16 KB 5");
        expect_prg(16'hC000, 19'h3C000, "71: $C000 fijo al ultimo");
        cpu_write(16'h8000, 8'h02);                       // $8000: no es el banco
        expect_prg(16'h8000, 19'h14000, "71: $8000 no cambia el banco");
        expect_a10(14'h2400, 1, "71: cabecera antes de $9000");
        cpu_write(16'h9000, 8'h10);
        expect_a10(14'h2000, 1, "71: $9000 D4=1 -> pantalla B");
        cpu_write(16'h9000, 8'h00);
        expect_a10(14'h2400, 0, "71: $9000 D4=0 -> pantalla A");
        back_to_menu;
        start_game(8'd71, 5'b01111, CHR_RAM, 8'd1);
        expect_a10(14'h2400, 1, "71: el control de $9000 se reinicia en el menu");
        back_to_menu;

        // ------------------------------------------------ 232 Quattro
        start_game(8'd232, 5'b01111, CHR_RAM, 8'd0);
        cpu_write(16'h8000, 8'h18);                       // bloque 3
        cpu_write(16'hC000, 8'h02);                       // página 2
        expect_prg(16'h8000, 19'h38000, "232: $8000 = bloque*4 + pagina");
        expect_prg(16'hC000, 19'h3C000, "232: $C000 = bloque*4 + 3");
        cpu_write(16'h8000, 8'h08);                       // bloque 1
        expect_prg(16'hC000, 19'h1C000, "232: $C000 sigue al bloque");
        back_to_menu;

        // ------------------------------------------------ 34 BNROM (CHR-RAM) y NINA-001 (CHR-ROM)
        start_game(8'd34, 5'b01111, CHR_RAM, 8'd0);
        cpu_write(16'h8000, 8'h03);
        expect_prg(16'h8000, 19'h18000, "34 BNROM: PRG 32 KB 3");
        cpu_write(16'h7FFD, 8'h01);
        expect_prg(16'h8000, 19'h18000, "34 BNROM: $7FFD no es registro");
        back_to_menu;
        start_game(8'd34, 5'b00011, 8'b000111, 8'd0);
        cpu_write(16'h7FFD, 8'h01);
        cpu_write(16'h7FFE, 8'h03);
        cpu_write(16'h7FFF, 8'h09);
        expect_prg(16'h8000, 19'h08000, "34 NINA: PRG 1");
        expect_chr(14'h0123, 19'h03123, "34 NINA: CHR 4 KB 3 en $0000");
        expect_chr(14'h1123, 19'h09123, "34 NINA: CHR 4 KB 9 en $1000");
        cpu_write(16'h8000, 8'h00);
        expect_prg(16'h8000, 19'h08000, "34 NINA: $8000 no es registro");
        cpu_write(16'h6010, 8'h77);
        check(last_ram_ce && last_ram_we, "34 NINA: PRG-RAM en $6000");
        back_to_menu;

        // ------------------------------------------------ 206 Namco 108
        start_game(8'd206, 5'b00111, 8'b000111, 8'd0);
        expect_prg(16'hE000, 19'h1E000, "206: $E000 = ultimo");
        expect_prg(16'hC000, 19'h1C000, "206: $C000 = penultimo");
        cpu_write(16'h8000, 8'h06); cpu_write(16'h8001, 8'h05);
        cpu_write(16'h8000, 8'h07); cpu_write(16'h8001, 8'h09);
        expect_prg(16'h8000, 19'h0A000, "206: R6 = 5 en $8000");
        expect_prg(16'hA000, 19'h12000, "206: R7 = 9 en $A000");
        cpu_write(16'h8000, 8'h46);                       // D6 (modo PRG del MMC3) no existe
        expect_prg(16'h8000, 19'h0A000, "206: sin modo PRG");
        cpu_write(16'h8000, 8'h00); cpu_write(16'h8001, 8'h11);
        cpu_write(16'h8000, 8'h02); cpu_write(16'h8001, 8'h20);
        expect_chr(14'h0000, 19'h04000, "206: R0 2 KB ignora el bit bajo");
        expect_chr(14'h0400, 19'h04400, "206: R0 segunda mitad");
        expect_chr(14'h1000, 19'h08000, "206: R2 1 KB en $1000");
        cpu_write(16'h8000, 8'h80);                       // D7 (inversión del MMC3) no existe
        expect_chr(14'h1000, 19'h08000, "206: sin inversion CHR");
        cpu_write(16'hA000, 8'h01);                       // $A000: no hay registro de mirroring
        expect_a10(14'h2800, 1, "206: mirroring de cabecera");
        // el chip solo mira A15 y A0: $C000/$C001 son los mismos registros que $8000/$8001 (Krikzz y Mesen2)
        cpu_write(16'hC000, 8'h06); cpu_write(16'hC001, 8'h03);
        expect_prg(16'h8000, 19'h06000, "206: registros repetidos en $C000 (solo A15 y A0)");
        cpu_write(16'hE7FE, 8'h06); cpu_write(16'hF001, 8'h05);
        expect_prg(16'h8000, 19'h0A000, "206: registros repetidos en $E000-$FFFF");
        back_to_menu;

        // ------------------------------------------------ 33 Taito TC0190
        start_game(8'd33, 5'b00111, 8'b001111, 8'd1);
        cpu_write(16'h8000, 8'h45);                       // PRG0 5, horizontal
        cpu_write(16'h8001, 8'h07);
        expect_prg(16'h8000, 19'h0A000, "33: PRG $8000 = 5");
        expect_prg(16'hA000, 19'h0E000, "33: PRG $A000 = 7");
        expect_prg(16'hC000, 19'h1C000, "33: $C000 = penultimo");
        expect_prg(16'hE000, 19'h1E000, "33: $E000 = ultimo");
        expect_a10(14'h2800, 1, "33: D6 = horizontal");
        cpu_write(16'h8002, 8'h03);
        cpu_write(16'h8003, 8'h05);
        cpu_write(16'hA001, 8'h21);
        expect_chr(14'h0000, 19'h01800, "33: CHR 2 KB 3 en $0000");
        expect_chr(14'h0400, 19'h01C00, "33: CHR 2 KB 3, segunda mitad");
        expect_chr(14'h0800, 19'h02800, "33: CHR 2 KB 5 en $0800");
        expect_chr(14'h1400, 19'h08400, "33: CHR 1 KB $21 en $1400");
        cpu_write(16'h8000, 8'h05);
        expect_a10(14'h2400, 1, "33: D6 = 0 vertical");
        back_to_menu;

        check(cpu_d === 8'hzz && ppu_d === 8'hzz, "buses de datos en Z");
        if (errors == 0) $display("OK: todas las pruebas pasaron (fase 3a)");
        else             $display("ERRORES: %0d", errors);
        $finish;
    end

endmodule
