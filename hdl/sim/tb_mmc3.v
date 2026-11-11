// tb_mmc3.v — Testbench autoverificable del mapper 4 (MMC3): bancos PRG/CHR, mirroring,
// CHR-RAM y el contador de IRQ por scanline con un modelo de la PPU renderizando.
// Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_mmc3;

`include "tb_bus.vh"

    // ================================================================ modelo de la PPU
    // Cada scanline tiene 341 ciclos de PPU (186 ns). Direcciones que pone la PPU en el bus
    // (NESdev Wiki, "PPU rendering"):
    //   ciclo 0         ocioso, dirección del patrón de fondo
    //   1-256, 321-336  por cada tile: NT, AT (A12 = 0, $2xxx) y patrón bajo/alto del fondo
    //   257-320         8 sprites: dos lecturas basura de NT (A12 = 0) y patrón del sprite
    //   337-340         dos lecturas de NT
    // Con fondo en $0000 y sprites en $1000, A12 sube 8 veces por scanline (una por sprite)
    // separadas por solo 4 ciclos de PPU: el filtro del MMC3 debe contar una sola.
    reg ppu_run = 0, ppu_busy = 0;
    reg bg_hi = 0, spr_hi = 1;
    integer glitch_ns = 0;              // ancho de los picos de ruido en A12 (0 = sin ruido)
    integer scanline = 0, dot = 0;
    integer irq_line = -1, irq_dot = -1, irq_count = 0;

    function [13:0] fetch_addr(input integer d);
        integer g;
        begin
            if (d == 0)
                fetch_addr = {1'b0, bg_hi, 12'h010};
            else if ((d >= 1 && d <= 256) || (d >= 321 && d <= 336)) begin
                g = (d - 1) % 8;
                fetch_addr = (g < 4) ? 14'h2000 : {1'b0, bg_hi, 12'h010};
            end else if (d >= 257 && d <= 320) begin
                g = (d - 257) % 8;
                fetch_addr = (g < 4) ? 14'h2000 : {1'b0, spr_hi, 12'hFF0};
            end else
                fetch_addr = 14'h2000;
        end
    endfunction

    always begin
        wait (ppu_run);
        ppu_busy = 1;
        scanline = 0;
        while (ppu_run) begin
            for (dot = 0; dot < 341 && ppu_run; dot = dot + 1) begin
                ppu_a    = fetch_addr(dot);
                ppu_rd_n = 0;
                ppu_wr_n = 1;
                if (glitch_ns != 0 && !ppu_a[12] && (dot % 23) == 7) begin
                    // pico de ruido en A12 con la línea baja (diafonía/rebotes en la placa)
                    #60;
                    ppu_a[12] = 1'b1;
                    #(glitch_ns);
                    ppu_a[12] = 1'b0;
                    #(126 - glitch_ns);
                end else
                    #186;
            end
            if (ppu_run) scanline = scanline + 1;
        end
        ppu_rd_n = 1;
        ppu_busy = 0;
    end

    always @(negedge irq_n) begin
        irq_line  = scanline;
        irq_dot   = dot;
        irq_count = irq_count + 1;
    end

    task start_ppu(input bg, input spr);
        begin
            bg_hi = bg;
            spr_hi = spr;
            irq_line = -1; irq_dot = -1; irq_count = 0;
            ppu_run = 1;
            #1;
        end
    endtask

    task stop_ppu;
        begin
            ppu_run = 0;
            while (ppu_busy) #10;
            ppu_a = 14'h2000;
        end
    endtask

    // La CPU sigue funcionando (M2 activo) mientras la PPU dibuja.
    task run_lines(input integer n);
        integer target;
        begin
            target = scanline + n;
            while (scanline < target) cpu_read(16'h0000);
        end
    endtask

    task wait_irq(input integer max_lines);
        integer target;
        begin
            target = scanline + max_lines;
            while (irq_n !== 1'b0 && scanline < target) cpu_read(16'h0000);
        end
    endtask

    task show_irq;
        $display("      IRQ en scanline %0d, ciclo PPU %0d (pulsos: %0d)", irq_line, irq_dot, irq_count);
    endtask

    task mmc3_bank(input [2:0] r, input [7:0] v, input [7:0] mode);
        begin
            cpu_write(16'h8000, mode | {5'd0, r});
            cpu_write(16'h8001, v);
        end
    endtask

    // ================================================================ pruebas
    integer gi;

    initial begin
        repeat (4) cpu_read(16'h0000);

        // ---------------------------------------------- bancos: 256 KB PRG, 128 KB CHR, vertical
        start_game(8'd4, 5'b01111, 8'b001111, 8'd1);
        expect_prg(16'hE000, 19'h3E000, "MMC3: $E000 = ultimo banco");
        expect_prg(16'hC123, 19'h3C123, "MMC3 modo 0: $C000 = penultimo");
        expect_prg(16'h8000, 19'h00000, "MMC3: R6 = 0 al arrancar");
        expect_prg(16'hA000, 19'h02000, "MMC3: R7 = 1 al arrancar");
        expect_a10(14'h2400, 1, "MMC3: vertical segun cabecera");

        mmc3_bank(6, 8'd5, 8'h00);
        mmc3_bank(7, 8'd9, 8'h00);
        expect_prg(16'h8456, 19'h0A456, "MMC3 modo 0: R6 = 5 en $8000");
        expect_prg(16'hA456, 19'h12456, "MMC3: R7 = 9 en $A000");
        expect_prg(16'hFFFC, 19'h3FFFC, "MMC3 modo 0: vectores en el ultimo banco");

        cpu_write(16'h8000, 8'h46);       // modo PRG 1, selecciona R6
        expect_prg(16'h8000, 19'h3C000, "MMC3 modo 1: $8000 = penultimo");
        expect_prg(16'hC000, 19'h0A000, "MMC3 modo 1: R6 en $C000");
        expect_prg(16'hA000, 19'h12000, "MMC3 modo 1: R7 sigue en $A000");
        expect_prg(16'hE000, 19'h3E000, "MMC3 modo 1: $E000 fijo");
        cpu_write(16'h8001, 8'h27);       // R6 = 39 -> enmascarado a 7 (256 KB)
        expect_prg(16'hC000, 19'h0E000, "MMC3: R6 fuera de rango enmascarado");

        // CHR sin inversión
        cpu_write(16'h8000, 8'h00);
        mmc3_bank(0, 8'h11, 8'h00);       // impar: el bit bajo se ignora
        mmc3_bank(1, 8'h13, 8'h00);
        mmc3_bank(2, 8'h20, 8'h00);
        mmc3_bank(3, 8'h21, 8'h00);
        mmc3_bank(4, 8'h22, 8'h00);
        mmc3_bank(5, 8'h23, 8'h00);
        expect_chr(14'h0000, 19'h04000, "MMC3 CHR: R0 en $0000");
        expect_chr(14'h07FF, 19'h047FF, "MMC3 CHR: R0 son 2 KB");
        expect_chr(14'h0800, 19'h04800, "MMC3 CHR: R1 ignora el bit bajo");
        expect_chr(14'h0C00, 19'h04C00, "MMC3 CHR: R1 segunda mitad");
        expect_chr(14'h1000, 19'h08000, "MMC3 CHR: R2 en $1000");
        expect_chr(14'h1400, 19'h08400, "MMC3 CHR: R3 en $1400");
        expect_chr(14'h1800, 19'h08800, "MMC3 CHR: R4 en $1800");
        expect_chr(14'h1C00, 19'h08C00, "MMC3 CHR: R5 en $1C00");
        // con inversión de A12
        cpu_write(16'h8000, 8'h80);
        expect_chr(14'h0000, 19'h08000, "MMC3 CHR invertido: R2 en $0000");
        expect_chr(14'h0C00, 19'h08C00, "MMC3 CHR invertido: R5 en $0C00");
        expect_chr(14'h1000, 19'h04000, "MMC3 CHR invertido: R0 en $1000");
        expect_chr(14'h1C00, 19'h04C00, "MMC3 CHR invertido: R1 en $1C00");
        mmc3_bank(2, 8'hFF, 8'h80);
        expect_chr(14'h0000, 19'h1FC00, "MMC3 CHR: banco 255 enmascarado a 128 KB");
        ppu_access(14'h0100, 1);
        check(chr_we_n, "MMC3: CHR-ROM no escribible");

        // mirroring
        cpu_write(16'hA000, 8'h01);
        expect_a10(14'h2800, 1, "MMC3: horizontal $2800");
        expect_a10(14'h2400, 0, "MMC3: horizontal $2400");
        cpu_write(16'hA000, 8'h00);
        expect_a10(14'h2400, 1, "MMC3: vertical $2400");
        expect_a10(14'h2800, 0, "MMC3: vertical $2800");

        // PRG-RAM ($A001 se ignora)
        cpu_write(16'h6123, 8'h55);
        check(last_ram_ce && last_ram_we && last_prg_addr == 19'h00123, "MMC3: PRG-RAM $6000");
        cpu_write(16'hA001, 8'h00);
        cpu_write(16'h7FFF, 8'h55);
        check(last_ram_ce && last_ram_we, "MMC3: $A001 no bloquea la PRG-RAM");
        back_to_menu;

        start_game(8'd4, 5'b01111, 8'b001111, 8'd0);
        expect_prg(16'h8000, 19'h00000, "MMC3: registros reiniciados tras el menu");
        expect_a10(14'h2800, 1, "MMC3: horizontal segun cabecera");
        back_to_menu;

        // ---------------------------------------------- 512 KB PRG + CHR-RAM (Mega Man 4/6)
        start_game(8'd4, 5'b11111, CHR_RAM, 8'd0);
        expect_prg(16'hE000, 19'h7E000, "MMC3 512 KB: ultimo banco");
        expect_prg(16'hC000, 19'h7C000, "MMC3 512 KB: penultimo");
        mmc3_bank(6, 8'h21, 8'h00);
        expect_prg(16'h8000, 19'h42000, "MMC3 512 KB: R6 = 33");
        mmc3_bank(2, 8'h2D, 8'h00);
        expect_chr(14'h1000, 19'h01400, "MMC3 CHR-RAM: R2 recortado a 8 KB");
        mmc3_bank(0, 8'hF7, 8'h00);
        expect_chr(14'h0000, 19'h01800, "MMC3 CHR-RAM: R0 recortado a 8 KB");
        ppu_access(14'h1000, 1);
        check(!chr_we_n, "MMC3: CHR-RAM escribible");
        back_to_menu;

        // ---------------------------------------------- IRQ: fondo $0000, sprites $1000
        start_game(8'd4, 5'b01111, 8'b001111, 8'd0);
        cpu_write(16'hC000, 8'd3);
        cpu_write(16'hC001, 8'd0);
        cpu_write(16'hE001, 8'd0);
        start_ppu(0, 1);
        wait_irq(10);
        show_irq;
        check(irq_line == 3, "IRQ: latch 3 -> scanline 3 (recarga + 3)");
        check(irq_dot >= 257 && irq_dot <= 275, "IRQ: al empezar los sprites (~260)");
        cpu_write(16'hE000, 8'd0);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "IRQ: $E000 la reconoce");
        cpu_write(16'hE001, 8'd0);
        wait_irq(10);
        show_irq;
        check(irq_line == 7, "IRQ: una cuenta por scanline (siguiente en la 7)");
        check(irq_count == 2, "IRQ: sin pulsos de mas");

        cpu_write(16'hE000, 8'd0);        // desactivada: el contador sigue, sin IRQ
        irq_count = 0;
        run_lines(10);
        check(irq_count == 0 && irq_n === 1'b1, "IRQ: desactivada no dispara");
        stop_ppu;

        // latch = 0: IRQ en cada scanline (MMC3 nuevo)
        cpu_write(16'hC000, 8'd0);
        cpu_write(16'hC001, 8'd0);
        cpu_write(16'hE001, 8'd0);
        start_ppu(0, 1);
        wait_irq(3);
        check(irq_line == 0, "IRQ latch 0: dispara en la scanline 0");
        cpu_write(16'hE000, 8'd0);
        cpu_write(16'hE001, 8'd0);
        wait_irq(3);
        check(irq_line == 1, "IRQ latch 0: dispara en cada scanline");
        stop_ppu;

        // ---------------------------------------------- IRQ: fondo $1000, sprites $0000
        cpu_write(16'hE000, 8'd0);
        ppu_a = 14'h1000;
        repeat (3) cpu_read(16'h0000);
        cpu_write(16'hC000, 8'd2);
        cpu_write(16'hC001, 8'd0);
        cpu_write(16'hE001, 8'd0);
        start_ppu(1, 0);
        wait_irq(10);
        show_irq;
        check(irq_line == 2, "IRQ fondo $1000: latch 2 -> scanline 2");
        check(irq_dot >= 321 && irq_dot <= 340, "IRQ fondo $1000: tras los sprites (~325)");
        check(irq_count == 1, "IRQ fondo $1000: filtra los tiles del fondo");
        stop_ppu;

        // ---------------------------------------------- ruido en A12 (fallo de SMB3 en la consola)
        // Picos de 15/25/35 ns con A12 bajo: el chip real los filtra (condensador en A12);
        // si el mapper los cuenta, la IRQ llega antes y la barra de estado salta.
        for (gi = 15; gi <= 35; gi = gi + 10) begin
            glitch_ns = gi;
            cpu_write(16'hE000, 8'd0);
            cpu_write(16'hC000, 8'd3);
            cpu_write(16'hC001, 8'd0);
            cpu_write(16'hE001, 8'd0);
            start_ppu(0, 1);
            wait_irq(10);
            $display("      ruido %0d ns:", gi);
            show_irq;
            check(irq_line == 3 && irq_dot >= 257 && irq_dot <= 275, "IRQ con ruido en A12: misma scanline");
            cpu_write(16'hE000, 8'd0);
            cpu_write(16'hE001, 8'd0);
            wait_irq(10);
            check(irq_line == 7, "IRQ con ruido en A12: segunda IRQ en la 7");
            stop_ppu;
        end
        glitch_ns = 0;

        // ---------------------------------------------- RESET con IRQ pendiente
        cpu_write(16'hE000, 8'd0);
        cpu_write(16'hC000, 8'd0);
        cpu_write(16'hC001, 8'd0);
        cpu_write(16'hE001, 8'd0);
        start_ppu(0, 1);
        wait_irq(3);
        stop_ppu;
        check(irq_n === 1'b0, "IRQ pendiente antes del RESET");
        back_to_menu;
        check(irq_n === 1'b1, "IRQ: el menu no ve /IRQ");
        irq_count = 0;
        start_game(8'd4, 5'b01111, 8'b001111, 8'd0);
        repeat (4) cpu_read(16'h0000);
        check(irq_n === 1'b1 && irq_count == 0, "IRQ: ni un pulso al arrancar el siguiente juego");
        back_to_menu;

        // ---------------------------------------------- 4 pantallas (MAP_CFG bit 3): Rad Racer II
        start_game(8'd4, 5'b00011, 8'b000111, 8'h08);   // 64 KB PRG, 64 KB CHR, 4 pantallas
        expect_chr(14'h2000, 19'h7E000, "4 pantallas: $2000 -> RAM de la SRAM CHR");
        check(ciram_ce_n && !ppu_ex, "4 pantallas: CIRAM apagada, transceptor activo");
        expect_chr(14'h2400, 19'h7E400, "4 pantallas: $2400 pagina propia");
        expect_chr(14'h2800, 19'h7E800, "4 pantallas: $2800 pagina propia");
        expect_chr(14'h2FFF, 19'h7EFFF, "4 pantallas: $2FFF");
        expect_chr(14'h3123, 19'h7E123, "4 pantallas: $3000 espejo de $2000");
        ppu_access(14'h2C10, 1);
        check(!chr_we_n && !chr_ce_n && chr_addr_now == 19'h7EC10, "4 pantallas: escritura en $2C10");
        cpu_write(16'hA000, 8'h01);                      // el mirroring del MMC3 no influye
        expect_chr(14'h2800, 19'h7E800, "4 pantallas: ignora $A000");
        mmc3_bank(2, 8'h05, 8'h00);
        expect_chr(14'h1000, 19'h01400, "4 pantallas: patrones siguen con el MMC3");
        ppu_access(14'h1000, 1);
        check(chr_we_n, "4 pantallas: CHR-ROM sigue protegida");
        back_to_menu;
        ppu_access(14'h2000, 0);
        check(!ciram_ce_n, "4 pantallas: el menu usa la CIRAM");
        start_game(8'd4, 5'b00011, 8'b000111, 8'h00);
        expect_a10(14'h2800, 1, "sin bit 3: CIRAM normal otra vez");
        back_to_menu;
        start_game(8'd0, 5'b00001, 8'd0, 8'h09);         // genérico: también en NROM
        expect_chr(14'h2C00, 19'h7EC00, "4 pantallas en NROM (generico)");
        back_to_menu;

        check(cpu_d === 8'hzz && ppu_d === 8'hzz, "buses de datos en Z");

        if (errors == 0) $display("OK: todas las pruebas pasaron (MMC3)");
        else             $display("ERRORES: %0d", errors);
        $finish;
    end

endmodule
