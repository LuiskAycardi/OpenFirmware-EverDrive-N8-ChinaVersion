// tb_fase1.v — Testbench autoverificable de los mappers 1 (MMC1), 2 (UxROM),
// 3 (CNROM) y 7 (AxROM). Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_fase1;

`include "tb_bus.vh"

    // Escritura MMC1 de 5 bits (LSB primero), con un ciclo de lectura entre escrituras
    task mmc1_write(input [15:0] addr, input [4:0] v);
        integer i;
        begin
            for (i = 0; i < 5; i = i + 1) begin
                cpu_write(addr, {7'd0, v[i]});
                cpu_read(16'h0000);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_fase1.vcd");
        $dumpvars(0, tb_fase1);
        repeat (4) cpu_read(16'h0000);

        // ============================================== UxROM (2), 128 KB, CHR-RAM, vertical
        start_game(8'd2, 5'b00111, CHR_RAM, 8'd1);
        expect_prg(16'hC123, 19'h1C123, "UxROM: $C000 = ultimo banco (7)");
        cpu_write(16'h8000, 8'd3);
        expect_prg(16'h8123, 19'h0C123, "UxROM: banco 3 en $8000");
        expect_prg(16'hC123, 19'h1C123, "UxROM: $C000 sigue fijo");
        cpu_write(16'hFFF0, 8'h1F);
        expect_prg(16'h8000, 19'h1C000, "UxROM: banco 31 enmascarado a 7");
        ppu_access(14'h0100, 1);
        check(!chr_we_n, "UxROM: CHR-RAM escribible");
        expect_a10(14'h2400, 1, "UxROM: mirroring vertical");
        cpu_write(16'h6000, 8'h01);
        check(last_ram_ce && last_ram_we && last_prg_addr == 19'h0, "UxROM: PRG-RAM $6000");
        back_to_menu;
        check(dut.os_mode == 1, "UxROM: RESET vuelve al menu");

        // ============================================== CNROM (3), 32 KB PRG, 32 KB CHR, horizontal
        start_game(8'd3, 5'b00001, 8'b000011, 8'd0);
        expect_chr(14'h0400, 19'h00400, "CNROM: banco CHR 0 al arrancar");
        cpu_write(16'h8000, 8'd2);
        expect_chr(14'h0400, 19'h04400, "CNROM: banco CHR 2");
        expect_chr(14'h1FFF, 19'h05FFF, "CNROM: banco CHR 2, final");
        cpu_write(16'h8000, 8'd7);
        expect_chr(14'h0000, 19'h06000, "CNROM: banco 7 enmascarado a 3");
        expect_prg(16'hC010, 19'h04010, "CNROM: PRG 32 KB fijo");
        ppu_access(14'h0100, 1);
        check(chr_we_n, "CNROM: CHR-ROM no escribible");
        expect_a10(14'h2800, 1, "CNROM: mirroring horizontal");
        back_to_menu;

        // los registros del mapper vuelven a 0 al pasar por el menú
        start_game(8'd3, 5'b00001, 8'b000011, 8'd0);
        expect_chr(14'h0000, 19'h00000, "CNROM: registro reiniciado tras el menu");
        back_to_menu;

        // ============================================== AxROM (7), 256 KB, CHR-RAM
        start_game(8'd7, 5'b01111, CHR_RAM, 8'd0);
        expect_prg(16'h8000, 19'h00000, "AxROM: banco 0 al arrancar");
        expect_a10(14'h2000, 0, "AxROM: pantalla A al arrancar");
        cpu_write(16'h8000, 8'h15);   // banco 5, pantalla B
        expect_prg(16'h8000, 19'h28000, "AxROM: banco 5 en $8000");
        expect_prg(16'hC010, 19'h2C010, "AxROM: banco 5 en $C000");
        expect_a10(14'h2000, 1, "AxROM: pantalla B en $2000");
        expect_a10(14'h2C00, 1, "AxROM: pantalla B en $2C00");
        cpu_write(16'h8000, 8'h0F);   // banco 15 enmascarado a 7, pantalla A
        expect_prg(16'h8000, 19'h38000, "AxROM: banco 15 enmascarado");
        expect_a10(14'h2400, 0, "AxROM: pantalla A");
        back_to_menu;

        // ============================================== MMC1 (1), 256 KB PRG, 128 KB CHR
        start_game(8'd1, 5'b01111, 8'b001111, 8'd0);
        // arranque: modo PRG 3 -> $C000 = último banco
        expect_prg(16'hC000, 19'h3C000, "MMC1: $C000 = ultimo banco al arrancar");
        mmc1_write(16'hE000, 5'd5);
        expect_prg(16'h8123, 19'h14123, "MMC1 modo 3: banco 5 en $8000");
        expect_prg(16'hC123, 19'h3C123, "MMC1 modo 3: $C000 fijo");

        mmc1_write(16'h8000, 5'b01010);   // modo PRG 2, vertical, CHR 8 KB
        expect_prg(16'h8123, 19'h00123, "MMC1 modo 2: $8000 fijo al banco 0");
        expect_prg(16'hC123, 19'h14123, "MMC1 modo 2: banco 5 en $C000");
        expect_a10(14'h2400, 1, "MMC1: vertical $2400");
        expect_a10(14'h2800, 0, "MMC1: vertical $2800");

        mmc1_write(16'h8000, 5'b00011);   // modo PRG 0 (32 KB), horizontal
        expect_prg(16'h8000, 19'h10000, "MMC1 modo 0: 32 KB, mitad baja (banco 4)");
        expect_prg(16'hC000, 19'h14000, "MMC1 modo 0: 32 KB, mitad alta (banco 5)");
        expect_a10(14'h2800, 1, "MMC1: horizontal $2800");

        mmc1_write(16'h8000, 5'b00001);   // pantalla B
        expect_a10(14'h2000, 1, "MMC1: pantalla B");
        mmc1_write(16'h8000, 5'b00000);   // pantalla A
        expect_a10(14'h2C00, 0, "MMC1: pantalla A");

        // CHR en 8 KB: se ignora el bit bajo del banco 0
        mmc1_write(16'hA000, 5'd3);
        mmc1_write(16'hC000, 5'd7);
        expect_chr(14'h0400, 19'h02400, "MMC1 CHR 8 KB: mitad baja (banco 2)");
        expect_chr(14'h1400, 19'h03400, "MMC1 CHR 8 KB: mitad alta (banco 3)");
        // CHR en 4 KB
        mmc1_write(16'h8000, 5'b10000);
        expect_chr(14'h0400, 19'h03400, "MMC1 CHR 4 KB: banco 0 = 3");
        expect_chr(14'h1400, 19'h07400, "MMC1 CHR 4 KB: banco 1 = 7");

        // bit 7: reinicia el registro serie y fuerza el modo PRG 3
        cpu_write(16'h8000, 8'h01);       // un bit a medias...
        cpu_read(16'h0000);
        cpu_write(16'h8000, 8'h80);       // ...descartado por el reset
        cpu_read(16'h0000);
        expect_prg(16'hC000, 19'h3C000, "MMC1: bit 7 fuerza modo PRG 3");
        mmc1_write(16'hE000, 5'd2);
        expect_prg(16'h8000, 19'h08000, "MMC1: registro serie limpio tras bit 7");

        // escrituras en ciclos consecutivos: solo cuenta la primera
        cpu_write(16'hE000, 8'd1);
        cpu_write(16'hE000, 8'd0);        // consecutiva: ignorada
        cpu_read(16'h0000);
        cpu_write(16'hE000, 8'd1);  cpu_read(16'h0000);
        cpu_write(16'hE000, 8'd0);  cpu_read(16'h0000);
        cpu_write(16'hE000, 8'd0);  cpu_read(16'h0000);
        cpu_write(16'hE000, 8'd0);  cpu_read(16'h0000);
        expect_prg(16'h8000, 19'h0C000, "MMC1: ignora escritura consecutiva (banco 3)");

        // PRG-RAM
        cpu_write(16'h7FFF, 8'h42);
        check(last_ram_ce && last_ram_we && last_prg_addr == 19'h01FFF, "MMC1: PRG-RAM $7FFF");
        back_to_menu;

        // ============================================== MMC1 SUROM: 512 KB PRG, CHR-RAM
        // (caso de Dragon Warrior III/IV; el OS envía CHR_SIZE = $FF)
        start_game(8'd1, 5'b11111, CHR_RAM, 8'd0);
        expect_prg(16'hC000, 19'h3C000, "SUROM: arranca en la mitad baja");
        mmc1_write(16'hA000, 5'b10000);   // mitad alta
        mmc1_write(16'hE000, 5'd1);
        expect_prg(16'h8000, 19'h44000, "SUROM: banco 1 de la mitad alta");
        expect_prg(16'hC000, 19'h7C000, "SUROM: ultimo banco de la mitad alta");
        ppu_access(14'h0100, 1);
        check(!chr_we_n, "SUROM: CHR-RAM escribible");
        // la CHR-RAM no debe moverse al cambiar de mitad de PRG
        expect_chr(14'h0100, 19'h00100, "SUROM: CHR-RAM fija en 8 KB ($0100)");
        expect_chr(14'h1F00, 19'h01F00, "SUROM: CHR-RAM fija en 8 KB ($1F00)");
        // modo CHR de 4 KB: PRG A18 sigue al registro CHR activo (PPU A12)
        mmc1_write(16'h8000, 5'b11100);   // CHR 4 KB, PRG modo 3, pantalla A
        mmc1_write(16'hA000, 5'b10000);   // banco 0: mitad alta, CHR 4 KB #0
        mmc1_write(16'hC000, 5'b00001);   // banco 1: mitad baja, CHR 4 KB #1
        expect_chr(14'h0400, 19'h00400, "SUROM 4 KB: $0000 -> CHR-RAM 0");
        expect_prg(16'hC000, 19'h7C000, "SUROM 4 KB: con A12=0 mitad alta");
        expect_chr(14'h1400, 19'h01400, "SUROM 4 KB: $1000 -> CHR-RAM 4 KB");
        expect_prg(16'hC000, 19'h3C000, "SUROM 4 KB: con A12=1 mitad baja");
        ppu_access(14'h0000, 0);
        back_to_menu;

        // ============================================== MMC1 SNROM: 256 KB, CHR-RAM
        // (bit 4 del registro CHR = desactivar WRAM; no debe mover la CHR-RAM)
        start_game(8'd1, 5'b01111, CHR_RAM, 8'd0);
        mmc1_write(16'hA000, 5'b10000);
        expect_chr(14'h0200, 19'h00200, "SNROM: CHR-RAM no se mueve con bit 4");
        expect_prg(16'hC000, 19'h3C000, "SNROM: 256 KB, bit 4 enmascarado en PRG");
        ppu_access(14'h0000, 0);
        back_to_menu;

        // ============================================== mapper no implementado -> NROM
        start_game(8'd99, 5'b00001, 8'd0, 8'd1);
        expect_prg(16'hC010, 19'h04010, "mapper 99 se comporta como NROM");
        back_to_menu;

        check(cpu_d === 8'hzz && ppu_d === 8'hzz, "buses de datos en Z");

        if (errors == 0) $display("OK: todas las pruebas pasaron (fase 1)");
        else             $display("ERRORES: %0d", errors);
        $finish;
    end

endmodule
