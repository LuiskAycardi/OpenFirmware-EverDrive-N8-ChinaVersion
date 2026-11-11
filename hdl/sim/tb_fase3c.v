// tb_fase3c.v — Testbench autoverificable de la fase 3c.
//   RBF 100 (variantes): 155, 180, 185, 48, 37, 47, 115, 119, 189, 76, 88, 95, 154
//   RBF 101 (chips nuevos): 64/158, 80/207, 82, 68, 32, 112, 75, 137/138/139/141, 156, 24/26,
//                           65, 89/93, 243, 72/92, 133, 67, 78, 85, 193, 41/46/228/241
// Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_fase3c;

`include "tb_bus.vh"

    // ================================================================ modelo de la PPU (de tb_mmc3)
    reg ppu_run = 0, ppu_busy = 0;
    reg bg_hi = 0, spr_hi = 1;
    integer scanline = 0, dot = 0;
    integer irq_line = -1, irq_dot = -1;

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
                ppu_a = fetch_addr(dot); ppu_rd_n = 0; ppu_wr_n = 1;
                #186;
            end
            if (ppu_run) scanline = scanline + 1;
        end
        ppu_rd_n = 1;
        ppu_busy = 0;
    end

    always @(negedge irq_n) if (ppu_run) begin irq_line = scanline; irq_dot = dot; end

    task start_ppu;
        begin irq_line = -1; irq_dot = -1; ppu_run = 1; #1; end
    endtask
    task stop_ppu;
        begin ppu_run = 0; while (ppu_busy) #10; ppu_a = 14'h2000; end
    endtask
    task wait_irq(input integer max_lines);
        integer target;
        begin
            target = scanline + max_lines;
            while (irq_n !== 1'b0 && scanline < target) cpu_read(16'h0000);
        end
    endtask

    // ================================================================ ayudas
    integer n, c;
    integer bajos, altos;
    defparam dut.tono.CLK_HZ = 40_000;           // tono de prueba acelerado (ver la prueba del 247)

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

    // CHR sin ninguna memoria seleccionada (la PPU lee el bus abierto)
    task expect_chr_off(input [13:0] addr, input [8*64-1:0] msg);
        begin
            ppu_access(addr, 0);
            check(chr_ce_n && ciram_ce_n, msg);
        end
    endtask

    // Escritura de la PPU: ¿llega a la SRAM CHR en la dirección esperada?
    task expect_chr_wr(input [13:0] addr, input want_we, input [18:0] want, input [8*64-1:0] msg);
        begin
            ppu_access(addr, 1);
            check(!chr_ce_n && (!chr_we_n == want_we) && (!want_we || chr_addr_now == want), msg);
            if (!(!chr_ce_n && (!chr_we_n == want_we))) $display("      chr_ce_n=%b chr_we_n=%b", chr_ce_n, chr_we_n);
            ppu_access(addr, 0);
        end
    endtask

    // Nametable desde la SRAM CHR (CIRAM apagada)
    task expect_nt_chr(input [13:0] addr, input [18:0] want, input [8*64-1:0] msg);
        begin
            ppu_access(addr, 0);
            check(!chr_ce_n && ciram_ce_n && chr_addr_now == want, msg);
            if (!(!chr_ce_n && ciram_ce_n && chr_addr_now == want))
                $display("      CHR 0x%05h (ce_n=%b ciram_ce_n=%b), esperado 0x%05h", chr_addr_now, chr_ce_n, ciram_ce_n, want);
        end
    endtask

    task ram_write(input [15:0] addr, input want, input [8*64-1:0] msg);
        begin
            cpu_write(addr, 8'h55);
            check((last_ram_ce && last_ram_we) == want, msg);
        end
    endtask

    task reg2(input [15:0] a_sel, input [7:0] sel, input [15:0] a_dat, input [7:0] v);
        begin cpu_write(a_sel, sel); cpu_write(a_dat, v); end
    endtask

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
        repeat (4) cpu_read(16'h0000);

        // ##################################################################### RBF 100: variantes
        // ================================================= 155 (MMC1A) = instancia del MMC1
        start_game(8'd155, 5'b00111, 8'b000011, 8'd0);
        mmc1_write(16'hE000, 5'd3);
        expect_prg(16'h8000, 19'h0C000, "155: MMC1, banco 3 en $8000");
        expect_prg(16'hC000, 19'h1C000, "155: $C000 fijo al ultimo");
        back_to_menu;

        // ================================================= 180 (UNROM con $8000 fijo)
        start_game(8'd180, 5'b00111, CHR_RAM, 8'd0);
        cpu_write(16'h8000, 8'h05);
        expect_prg(16'h8000, 19'h00000, "180: $8000 fijo al primer banco");
        expect_prg(16'hC000, 19'h14000, "180: $C000 = banco 5");
        back_to_menu;

        // ================================================= 185 (CNROM con protección)
        start_game(8'd185, 5'b00001, 8'b000001, 8'd0);
        expect_chr(14'h0000, 19'h00000, "185: CHR activa al arrancar");
        cpu_write(16'h8000, 8'h00);
        expect_chr_off(14'h0000, "185: D = $00 desactiva la CHR");
        cpu_write(16'h8000, 8'h11);
        expect_chr(14'h0010, 19'h00010, "185: D = $11 activa la CHR (banco 0 siempre)");
        cpu_write(16'h8000, 8'h13);
        expect_chr_off(14'h0000, "185: D = $13 desactiva la CHR");
        cpu_write(16'h8000, 8'h21);
        expect_chr(14'h1000, 19'h01000, "185: D = $21 activa, sin cambiar de banco");
        expect_a10(14'h2800, 1, "185: CIRAM sigue activa");
        back_to_menu;

        // ================================================= 48 (Taito TC0690)
        start_game(8'd48, 5'b00111, 8'b011111, 8'd1);
        cpu_write(16'h8000, 8'h45);
        expect_prg(16'h8000, 19'h0A000, "48: PRG0 = 5");
        expect_a10(14'h2400, 1, "48: D6 de $8000 no cambia el mirroring");
        cpu_write(16'hE000, 8'h40);
        expect_a10(14'h2400, 0, "48: $E000 D6 = horizontal");
        expect_a10(14'h2800, 1, "48: horizontal ($2800)");
        cpu_write(16'h8002, 8'h03);
        expect_chr(14'h0400, 19'h01C00, "48: CHR 2 KB ($8002)");
        cpu_write(16'hA001, 8'h21);
        expect_chr(14'h1400, 19'h08400, "48: CHR 1 KB ($A001)");
        // IRQ: recarga invertida ($FC -> 3), llega ~22 ciclos de CPU después que en el MMC3
        cpu_write(16'hC000, 8'hFC);
        cpu_write(16'hC001, 8'h00);
        cpu_write(16'hC002, 8'h00);
        start_ppu;
        wait_irq(8);
        stop_ppu;
        check(irq_line == 3 && irq_dot >= 300, "48: IRQ en la scanline 3, con retardo");
        $display("      48: IRQ en scanline %0d, ciclo %0d", irq_line, irq_dot);
        cpu_write(16'hC000, 8'hFC);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "48: $C000 reconoce la IRQ");
        back_to_menu;

        // ================================================= 37 (SMB + Tetris + NWC)
        start_game(8'd37, 5'b01111, 8'b011111, 8'd0);
        reg2(16'h8000, 8'h06, 16'h8001, 8'h02);
        reg2(16'h8000, 8'h02, 16'h8001, 8'h05);
        expect_prg(16'h8000, 19'h04000, "37: bloque 0, R6 = 2");
        expect_prg(16'hE000, 19'h0E000, "37: bloque 0, $E000 = ultimo del bloque");
        cpu_write(16'h6000, 8'h03);
        check(!last_ram_ce, "37: $6000 es registro, no RAM");
        expect_prg(16'h8000, 19'h14000, "37: bloque 3 = 64 KB desde 0x10000");
        cpu_write(16'h6000, 8'h04);
        expect_prg(16'h8000, 19'h24000, "37: bloque 4 = 128 KB desde 0x20000");
        expect_prg(16'hE000, 19'h3E000, "37: bloque 4, $E000");
        expect_chr(14'h1000, 19'h21400, "37: bloque 4 suma 0x80 al banco CHR");
        cpu_write(16'h6000, 8'h00);
        expect_chr(14'h1000, 19'h01400, "37: bloque 0, CHR sin sumar");
        back_to_menu;

        // ================================================= 47 (Super Spike V'Ball + NWC)
        start_game(8'd47, 5'b01111, 8'b011111, 8'd0);
        reg2(16'h8000, 8'h06, 16'h8001, 8'h02);
        reg2(16'h8000, 8'h02, 16'h8001, 8'h05);
        expect_prg(16'h8000, 19'h04000, "47: bloque 0");
        cpu_write(16'h6000, 8'h01);
        expect_prg(16'h8000, 19'h24000, "47: bloque 1 = segundos 128 KB");
        expect_chr(14'h1000, 19'h21400, "47: bloque 1 en CHR");
        back_to_menu;

        // ================================================= 115 (Kasheng)
        start_game(8'd115, 5'b00111, 8'b111111, 8'd0);
        reg2(16'h8000, 8'h06, 16'h8001, 8'h02);
        reg2(16'h8000, 8'h02, 16'h8001, 8'h05);
        expect_prg(16'h8000, 19'h04000, "115: MMC3 normal");
        cpu_write(16'h6000, 8'h83);
        expect_prg(16'h8000, 19'h0C000, "115: modo 16 KB, banco 3 en $8000");
        expect_prg(16'hA000, 19'h0E000, "115: modo 16 KB, segunda mitad");
        expect_prg(16'hC000, 19'h0C000, "115: modo 16 KB repetido en $C000");
        cpu_write(16'h6000, 8'hA2);
        expect_prg(16'h8000, 19'h08000, "115: modo 32 KB, banco 1");
        expect_prg(16'hE000, 19'h0E000, "115: modo 32 KB, final");
        cpu_write(16'h5080, 8'h00);
        expect_prg(16'h8000, 19'h08000, "115: $5080 no es el registro PRG");
        cpu_write(16'h4100, 8'h80);
        expect_prg(16'h8000, 19'h00000, "115: $4100 = registro PRG");
        cpu_write(16'h6001, 8'h01);
        expect_chr(14'h1000, 19'h41400, "115: $6001 D0 = CHR A18");
        back_to_menu;

        // ================================================= 189 (TXC)
        start_game(8'd189, 5'b00111, 8'b011111, 8'd0);
        cpu_write(16'h4120, 8'h21);
        expect_prg(16'h8000, 19'h18000, "189: 32 KB = (1 | 2) = 3");
        expect_prg(16'hE000, 19'h1E000, "189: 32 KB, final");
        cpu_write(16'h4100, 8'h00);
        expect_prg(16'h8000, 19'h18000, "189: $4100 no es registro");
        reg2(16'h8000, 8'h02, 16'h8001, 8'h05);
        expect_chr(14'h1000, 19'h01400, "189: CHR del MMC3");
        back_to_menu;

        // ================================================= 119 (TQROM)
        start_game(8'd119, 5'b00111, 8'b000111, 8'd0);
        reg2(16'h8000, 8'h00, 16'h8001, 8'h40);
        expect_chr(14'h0000, 19'h7C000, "119: bit 6 = CHR-RAM (0x7C000, sin mascara)");
        expect_chr_wr(14'h0010, 1, 19'h7C010, "119: la CHR-RAM se escribe");
        reg2(16'h8000, 8'h02, 16'h8001, 8'h45);
        expect_chr(14'h1000, 19'h7D400, "119: CHR-RAM pagina 5");
        reg2(16'h8000, 8'h03, 16'h8001, 8'h05);
        expect_chr(14'h1400, 19'h01400, "119: bit 6 = 0 -> CHR-ROM");
        expect_chr_wr(14'h1400, 0, 19'h0, "119: la CHR-ROM no se escribe");
        back_to_menu;

        // ================================================= 76, 88, 154, 95 (Namco 108)
        start_game(8'd76, 5'b00111, 8'b001111, 8'd0);
        reg2(16'h8000, 8'h02, 16'h8001, 8'h21);
        reg2(16'h8000, 8'h05, 16'h8001, 8'h03);
        reg2(16'h8000, 8'h00, 16'h8001, 8'h09);
        expect_chr(14'h0400, 19'h10C00, "76: R2 = 2 KB en $0000");
        expect_chr(14'h1C00, 19'h01C00, "76: R5 = 2 KB en $1800");
        back_to_menu;

        start_game(8'd88, 5'b00111, 8'b001111, 8'd0);
        reg2(16'h8000, 8'h00, 16'h8001, 8'h04);
        reg2(16'h8000, 8'h02, 16'h8001, 8'h03);
        expect_chr(14'h0000, 19'h01000, "88: $0000 en los 64 KB bajos");
        expect_chr(14'h1000, 19'h10C00, "88: $1000 en los 64 KB altos");
        back_to_menu;

        start_game(8'd154, 5'b00111, 8'b001111, 8'd8);       // cabecera con el bit de 4 pantallas
        reg2(16'h8000, 8'h02, 16'h8001, 8'h03);
        expect_chr(14'h1000, 19'h10C00, "154: CHR como el 88");
        cpu_write(16'h8000, 8'h40);
        expect_a10(14'h2000, 1, "154: D6 = pantalla B (sin RAM de 4 pantallas)");
        cpu_write(16'hC000, 8'h00);
        expect_a10(14'h2400, 0, "154: cualquier escritura en $8000-$FFFF");
        back_to_menu;

        start_game(8'd95, 5'b00111, 8'b000011, 8'd0);
        reg2(16'h8000, 8'h00, 16'h8001, 8'h20);
        reg2(16'h8000, 8'h01, 16'h8001, 8'h00);
        expect_a10(14'h2400, 1, "95: $2000/$2400 = R0 bit 5");
        expect_a10(14'h2800, 0, "95: $2800 = R1 bit 5");
        reg2(16'h8000, 8'h01, 16'h8001, 8'h22);
        expect_a10(14'h2C00, 1, "95: $2C00 = R1 bit 5");
        back_to_menu;

        // ##################################################################### RBF 101: chips nuevos
        // ================================================= 64 (RAMBO-1)
        start_game(8'd64, 5'b00111, 8'b001111, 8'd0);
        reg2(16'h8000, 8'h06, 16'h8001, 8'h03);
        reg2(16'h8000, 8'h07, 16'h8001, 8'h04);
        reg2(16'h8000, 8'h0F, 16'h8001, 8'h05);
        expect_prg(16'h8000, 19'h06000, "64: R6 en $8000");
        expect_prg(16'hA000, 19'h08000, "64: R7 en $A000");
        expect_prg(16'hC000, 19'h0A000, "64: R15 en $C000");
        expect_prg(16'hE000, 19'h1E000, "64: $E000 fijo");
        cpu_write(16'h8000, 8'h46);
        expect_prg(16'h8000, 19'h0A000, "64: modo 1, R15 en $8000");
        expect_prg(16'hA000, 19'h06000, "64: modo 1, R6 en $A000");
        expect_prg(16'hC000, 19'h08000, "64: modo 1, R7 en $C000");
        reg2(16'h8000, 8'h00, 16'h8001, 8'h10);
        expect_chr(14'h0400, 19'h04400, "64: K = 0, $0400 = R0 + 1");
        reg2(16'h8000, 8'h28, 16'h8001, 8'h33);
        expect_chr(14'h0400, 19'h0CC00, "64: K = 1, $0400 = R8");
        reg2(16'h8000, 8'h82, 16'h8001, 8'h07);
        expect_chr(14'h0000, 19'h01C00, "64: inversion, R2 en $0000");
        cpu_write(16'hA000, 8'h01);
        expect_a10(14'h2800, 1, "64: $A000 = horizontal");
        // IRQ modo ciclo: recarga 3; el primer pulso carga 3 + 2 y resta 1; un pulso cada 4 ciclos
        cpu_write(16'h8000, 8'h00);
        cpu_write(16'hC000, 8'h03);
        cpu_write(16'hC001, 8'h01);
        cpu_write(16'hE001, 8'h00);
        cycles_to_irq(60, c);
        check(c >= 18 && c <= 22, "64: IRQ modo ciclo tras 5 pulsos de 4 ciclos");
        $display("      64: ciclos hasta IRQ (modo ciclo): %0d", c);
        cpu_write(16'hE000, 8'h00);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "64: $E000 reconoce");
        // Paso de modo ciclo a modo A12: un pulso más a los <= 4 ciclos (Skull & Crossbones), que
        // consume la recarga (2 + 2 - 1 = 3); después 2, 1, 0 con A12 -> scanline 2
        cpu_write(16'hC000, 8'h02);
        cpu_write(16'hC001, 8'h00);
        cpu_write(16'hE001, 8'h00);
        start_ppu;
        wait_irq(8);
        stop_ppu;
        check(irq_line == 2, "64: de ciclo a A12: pulso extra (IRQ en la scanline 2)");
        $display("      64: IRQ en scanline %0d, ciclo %0d (tras cambio de modo)", irq_line, irq_dot);
        cpu_write(16'hE000, 8'h00);
        // IRQ modo A12 limpio: recarga 2 -> primer pulso 3, luego 2, 1, 0 -> 4.º pulso
        cpu_write(16'hC001, 8'h00);
        cpu_write(16'hE001, 8'h00);
        start_ppu;
        wait_irq(8);
        stop_ppu;
        check(irq_line == 3 && irq_dot >= 263 && irq_dot <= 270, "64: IRQ modo A12 en el 4.o pulso, 2 ciclos tarde");
        $display("      64: IRQ en scanline %0d, ciclo %0d", irq_line, irq_dot);
        cpu_write(16'hE000, 8'h00);
        back_to_menu;

        start_game(8'd158, 5'b00111, 8'b001111, 8'd0);
        reg2(16'h8000, 8'h00, 16'h8001, 8'h80);
        reg2(16'h8000, 8'h01, 16'h8001, 8'h00);
        cpu_write(16'hA000, 8'h01);
        expect_a10(14'h2400, 1, "158: $2000/$2400 = R0 bit 7");
        expect_a10(14'h2800, 0, "158: $2800 = R1 bit 7 ($A000 sin efecto)");
        back_to_menu;

        // ================================================= 80 / 207 (Taito X1-005)
        start_game(8'd80, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h7EFA, 8'h03);
        cpu_write(16'h7EFC, 8'h04);
        cpu_write(16'h7EFE, 8'h05);
        expect_prg(16'h8000, 19'h06000, "80: PRG0");
        expect_prg(16'hA000, 19'h08000, "80: PRG1");
        expect_prg(16'hC000, 19'h0A000, "80: PRG2");
        expect_prg(16'hE000, 19'h1E000, "80: $E000 fijo");
        cpu_write(16'h7EF0, 8'h08);
        cpu_write(16'h7EF5, 8'h21);
        expect_chr(14'h0400, 19'h02400, "80: $7EF0 = 2 KB (banco + 1)");
        expect_chr(14'h1C00, 19'h08400, "80: $7EF5 = 1 KB en $1C00");
        cpu_write(16'h7EF6, 8'h01);
        expect_a10(14'h2400, 1, "80: $7EF6 = 1 vertical");
        cpu_write(16'h7EF7, 8'h00);
        expect_a10(14'h2400, 0, "80: $7EF7 = 0 horizontal");
        ram_write(16'h7F10, 0, "80: RAM sin permiso");
        cpu_write(16'h7EF8, 8'hA3);
        ram_write(16'h7F10, 1, "80: RAM con permiso $A3");
        ram_write(16'h6000, 0, "80: $6000 no es RAM");
        back_to_menu;

        start_game(8'd207, 5'b01111, 8'b001111, 8'd0);
        cpu_write(16'h7EF0, 8'h80);
        cpu_write(16'h7EF1, 8'h00);
        cpu_write(16'h7EF6, 8'h00);
        expect_a10(14'h2400, 1, "207: $2000/$2400 = $7EF0 bit 7");
        expect_a10(14'h2800, 0, "207: $2800 = $7EF1 bit 7");
        back_to_menu;

        // ================================================= 82 (Taito X1-017)
        start_game(8'd82, 5'b00111, 8'b011111, 8'd0);
        cpu_write(16'h7EFA, 8'h0C);
        expect_prg(16'h8000, 19'h06000, "82: PRG = D >> 2");
        cpu_write(16'h7EF0, 8'h05);
        cpu_write(16'h7EF2, 8'h09);
        expect_chr(14'h0400, 19'h01400, "82: 2 KB sin el bit bajo");
        expect_chr(14'h1000, 19'h02400, "82: 1 KB en $1000");
        cpu_write(16'h7EF6, 8'h02);
        expect_chr(14'h0000, 19'h02400, "82: modo CHR 1: 1 KB en $0000");
        expect_chr(14'h1000, 19'h01000, "82: modo CHR 1: 2 KB en $1000");
        expect_a10(14'h2400, 0, "82: D0 = 0 horizontal");
        cpu_write(16'h7EF7, 8'hCA);
        ram_write(16'h6100, 1, "82: $6000-$67FF con $CA");
        ram_write(16'h6900, 0, "82: $6800 sin permiso");
        cpu_write(16'h7EF8, 8'h69);
        ram_write(16'h6900, 1, "82: $6800-$6FFF con $69");
        cpu_write(16'h7EF9, 8'h84);
        ram_write(16'h7000, 1, "82: $7000-$73FF con $84");
        ram_write(16'h7400, 0, "82: $7400 no es RAM");
        back_to_menu;

        // ================================================= 68 (Sunsoft-4)
        start_game(8'd68, 5'b00111, 8'b011111, 8'd0);
        cpu_write(16'hF000, 8'h12);
        expect_prg(16'h8000, 19'h08000, "68: PRG 16 KB = 2");
        expect_prg(16'hC000, 19'h1C000, "68: $C000 fijo");
        ram_write(16'h6000, 1, "68: D4 = PRG-RAM activa");
        cpu_write(16'hF000, 8'h02);
        ram_write(16'h6000, 0, "68: D4 = 0, RAM apagada");
        cpu_write(16'h8000, 8'h05);
        cpu_write(16'hB000, 8'h7F);
        expect_chr(14'h0400, 19'h02C00, "68: CHR 2 KB en $0000");
        expect_chr(14'h1800, 19'h3F800, "68: CHR 2 KB en $1800");
        cpu_write(16'hC000, 8'h03);
        cpu_write(16'hD000, 8'h05);
        cpu_write(16'hE000, 8'h10);
        expect_nt_chr(14'h2000, 19'h20C00, "68: nametable desde CHR ($83)");
        expect_nt_chr(14'h2400, 19'h21400, "68: vertical: $2400 = registro 1");
        cpu_write(16'hE000, 8'h11);
        expect_nt_chr(14'h2400, 19'h20C00, "68: horizontal: $2400 = registro 0");
        expect_nt_chr(14'h2800, 19'h21400, "68: horizontal: $2800 = registro 1");
        cpu_write(16'hE000, 8'h03);
        expect_a10(14'h2000, 1, "68: CIRAM pantalla B");
        back_to_menu;

        // ================================================= 32 (Irem G-101)
        start_game(8'd32, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h8000, 8'h03);
        cpu_write(16'hA000, 8'h04);
        expect_prg(16'h8000, 19'h06000, "32: PRG0");
        expect_prg(16'hA000, 19'h08000, "32: PRG1");
        expect_prg(16'hC000, 19'h1C000, "32: $C000 penultimo");
        cpu_write(16'h9000, 8'h02);
        expect_prg(16'h8000, 19'h1C000, "32: modo 1, $8000 penultimo");
        expect_prg(16'hC000, 19'h06000, "32: modo 1, $C000 = PRG0");
        expect_a10(14'h2400, 1, "32: D0 = 0 vertical");
        cpu_write(16'h9000, 8'h01);
        expect_a10(14'h2400, 0, "32: D0 = 1 horizontal");
        cpu_write(16'hB003, 8'h21);
        expect_chr(14'h0C00, 19'h08400, "32: CHR por A2-A0");
        back_to_menu;

        // ================================================= 112 (NTDEC)
        start_game(8'd112, 5'b00111, 8'b111111, 8'd0);
        expect_a10(14'h2400, 1, "112: vertical al arrancar");
        reg2(16'h8000, 8'h00, 16'hA000, 8'h03);
        expect_prg(16'h8000, 19'h06000, "112: R0 = PRG $8000");
        reg2(16'h8000, 8'h02, 16'hA000, 8'h10);
        expect_chr(14'h0400, 19'h04400, "112: R2 = 2 KB (banco + 1)");
        reg2(16'h8000, 8'h04, 16'hA000, 8'h20);
        expect_chr(14'h1000, 19'h08000, "112: R4 en $1000");
        cpu_write(16'hC000, 8'h10);
        expect_chr(14'h1000, 19'h48000, "112: $C000 D4 = bit 8 de R4");
        cpu_write(16'hE000, 8'h01);
        expect_a10(14'h2800, 1, "112: horizontal");
        back_to_menu;

        // ================================================= 75 (VRC1)
        start_game(8'd75, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h8000, 8'h03);
        cpu_write(16'hC000, 8'h05);
        expect_prg(16'h8000, 19'h06000, "75: PRG0");
        expect_prg(16'hC000, 19'h0A000, "75: PRG2");
        cpu_write(16'hE000, 8'h03);
        expect_chr(14'h0000, 19'h03000, "75: CHR0 = 3");
        cpu_write(16'h9000, 8'h02);
        expect_chr(14'h0000, 19'h13000, "75: $9000 D1 = bit 4 de CHR0");
        cpu_write(16'hF000, 8'h01);
        cpu_write(16'h9000, 8'h05);
        expect_chr(14'h1000, 19'h11000, "75: $9000 D2 = bit 4 de CHR1");
        expect_chr(14'h0000, 19'h03000, "75: CHR0 sin bit 4");
        expect_a10(14'h2800, 1, "75: D0 = horizontal");
        ram_write(16'h6000, 0, "75: sin PRG-RAM");
        back_to_menu;

        // ================================================= 141 / 138 / 139 / 137 (Sachen 8259)
        start_game(8'd141, 5'b00011, 8'b000111, 8'd0);
        reg2(16'h4100, 8'h05, 16'h4101, 8'h01);
        expect_prg(16'h8000, 19'h08000, "141: PRG 32 KB = R5");
        reg2(16'h4100, 8'h00, 16'h4101, 8'h01);
        reg2(16'h4100, 8'h01, 16'h4101, 8'h02);
        expect_chr(14'h0000, 19'h01000, "141: $0000 = R0 << 1");
        expect_chr(14'h0800, 19'h02800, "141: $0800 = R1 << 1 | 1");
        reg2(16'h4100, 8'h07, 16'h4101, 8'h01);
        expect_chr(14'h0800, 19'h01800, "141: modo simple: todos = R0");
        reg2(16'h4100, 8'h07, 16'h4101, 8'h04);
        expect_a10(14'h2000, 0, "141: mirroring 2: $2000 en A");
        expect_a10(14'h2400, 1, "141: mirroring 2: el resto en B");
        expect_a10(14'h2800, 1, "141: mirroring 2: $2800 en B");
        ram_write(16'h6000, 0, "141: sin PRG-RAM");
        back_to_menu;

        start_game(8'd138, 5'b00011, 8'b000111, 8'd0);
        reg2(16'h4100, 8'h00, 16'h4101, 8'h03);
        expect_chr(14'h0000, 19'h01800, "138: $0000 = R0 (sin desplazar)");
        back_to_menu;

        start_game(8'd139, 5'b00011, 8'b000111, 8'd0);
        reg2(16'h4100, 8'h01, 16'h4101, 8'h01);
        expect_chr(14'h0800, 19'h02800, "139: $0800 = R1 << 2 | 1");
        back_to_menu;

        start_game(8'd137, 5'b00011, 8'b001111, 8'd8);       // cabecera con el bit de 4 pantallas
        reg2(16'h4100, 8'h00, 16'h4101, 8'h03);
        reg2(16'h4100, 8'h03, 16'h4101, 8'h02);
        reg2(16'h4100, 8'h04, 16'h4101, 8'h04);
        reg2(16'h4100, 8'h06, 16'h4101, 8'h01);
        expect_chr(14'h0000, 19'h00C00, "137: 1 KB R0");
        expect_chr(14'h0C00, 19'h06800, "137: R3 | R4.2 << 4 | R6.0 << 3");
        expect_chr(14'h1000, 19'h1F000, "137: $1000 = ultimos 4 KB");
        expect_a10(14'h2400, 0, "137: mirroring 0 = horizontal (sin RAM de 4 pantallas)");
        expect_a10(14'h2800, 1, "137: horizontal ($2800)");
        back_to_menu;

        // ================================================= 156 (Daou)
        start_game(8'd156, 5'b00111, 8'b111111, 8'd0);
        expect_a10(14'h2400, 0, "156: pantalla A al arrancar");
        cpu_write(16'hC010, 8'h03);
        expect_prg(16'h8000, 19'h0C000, "156: PRG 16 KB");
        cpu_write(16'hC000, 8'h12);
        cpu_write(16'hC004, 8'h01);
        expect_chr(14'h0000, 19'h44800, "156: CHR0 = $112 (bajo + alto)");
        cpu_write(16'hC00B, 8'h05);
        expect_chr(14'h1C00, 19'h01400, "156: $C00B = CHR7");
        cpu_write(16'hC014, 8'h01);
        expect_a10(14'h2800, 1, "156: $C014 = horizontal");
        back_to_menu;

        // ================================================= 24 / 26 (VRC6)
        start_game(8'd24, 5'b01111, 8'b011111, 8'd0);
        cpu_write(16'h8000, 8'h03);
        cpu_write(16'hC000, 8'h09);
        expect_prg(16'h8000, 19'h0C000, "24: PRG 16 KB");
        expect_prg(16'hA000, 19'h0E000, "24: PRG 16 KB, segunda mitad");
        expect_prg(16'hC000, 19'h12000, "24: PRG 8 KB en $C000");
        expect_prg(16'hE000, 19'h3E000, "24: $E000 fijo");
        cpu_write(16'hD000, 8'h05);
        cpu_write(16'hE003, 8'h33);
        expect_chr(14'h0000, 19'h01400, "24: modo 0, R0");
        expect_chr(14'h1C00, 19'h0CC00, "24: modo 0, R7");
        cpu_write(16'hB003, 8'h21);
        expect_chr(14'h0000, 19'h01000, "24: modo 1 con D5: R0 & $FE");
        expect_chr(14'h0400, 19'h01400, "24: modo 1 con D5: R0 | 1");
        cpu_write(16'hB003, 8'h24);
        expect_a10(14'h2400, 0, "24: $24 = horizontal");
        expect_a10(14'h2800, 1, "24: $24 = horizontal ($2800)");
        cpu_write(16'hB003, 8'h2C);
        expect_a10(14'h2000, 1, "24: $2C = pantalla B");
        ram_write(16'h6000, 0, "24: D7 = 0, sin RAM");
        cpu_write(16'hB003, 8'hA0);
        ram_write(16'h6000, 1, "24: D7 = RAM activa");
        cpu_write(16'hE002, 8'h08);
        cpu_write(16'hB003, 8'h30);
        expect_nt_chr(14'h2400, 19'h02400, "24: nametables de CHR-ROM (R6 | 1)");
        expect_nt_chr(14'h2800, 19'h0C800, "24: nametables de CHR-ROM (R7 & $FE)");
        cpu_write(16'hB003, 8'h20);
        cpu_write(16'hF000, 8'hFC);
        cpu_write(16'hF001, 8'h06);
        cycles_to_irq(20, c);
        check(c == 3, "24: IRQ VRC modo ciclo");
        if (c != 3) $display("      ciclos hasta IRQ: %0d", c);
        cpu_write(16'hF002, 8'h00);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "24: $F002 reconoce");
        back_to_menu;

        start_game(8'd26, 5'b01111, 8'b011111, 8'd0);
        cpu_write(16'hD001, 8'h07);                  // VRC6b: A0 -> A1 = registro 2
        expect_chr(14'h0800, 19'h01C00, "26: A0/A1 intercambiados");
        back_to_menu;

        // ================================================= 65 (Irem H3001)
        start_game(8'd65, 5'b00111, 8'b011111, 8'd1);
        expect_prg(16'hA000, 19'h02000, "65: PRG1 = 1 al arrancar");
        expect_prg(16'hC000, 19'h1C000, "65: PRG2 = penultimo al arrancar");
        cpu_write(16'h8000, 8'h03);
        expect_prg(16'h8000, 19'h06000, "65: PRG0");
        cpu_write(16'hB002, 8'h21);
        expect_chr(14'h0800, 19'h08400, "65: CHR2");
        cpu_write(16'h9001, 8'h80);
        expect_a10(14'h2800, 1, "65: $9001 D7 = horizontal");
        cpu_write(16'h9005, 8'h00);
        cpu_write(16'h9006, 8'h05);
        cpu_write(16'h9004, 8'h00);
        cpu_write(16'h9003, 8'h80);
        cycles_to_irq(20, c);
        check(c == 4, "65: IRQ a los 5 ciclos (cuenta 5 -> 0)");
        if (c != 4) $display("      ciclos hasta IRQ: %0d", c);
        cpu_write(16'h9003, 8'h00);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "65: $9003 reconoce");
        back_to_menu;

        // ================================================= 89 / 93 (Sunsoft-2)
        start_game(8'd89, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h8000, 8'hA5);
        expect_prg(16'h8000, 19'h08000, "89: PRG D6-D4");
        expect_chr(14'h0000, 19'h1A000, "89: CHR D7 y D2-D0");
        expect_a10(14'h2800, 0, "89: D3 = 0 pantalla A");
        cpu_write(16'h8000, 8'h08);
        expect_a10(14'h2000, 1, "89: D3 = 1 pantalla B");
        back_to_menu;

        start_game(8'd93, 5'b00111, CHR_RAM, 8'd1);
        expect_chr(14'h0000, 19'h00000, "93: CHR activa al arrancar");
        cpu_write(16'h8000, 8'h30);
        expect_prg(16'h8000, 19'h0C000, "93: PRG D6-D4");
        expect_chr_off(14'h0000, "93: D0 = 0 desactiva la CHR");
        cpu_write(16'h8000, 8'h31);
        expect_chr_wr(14'h0010, 1, 19'h00010, "93: D0 = 1, CHR-RAM escribible");
        back_to_menu;

        // ================================================= 243 (Sachen)
        start_game(8'd243, 5'b00011, 8'b001111, 8'd0);
        reg2(16'h4100, 8'h05, 16'h4101, 8'h01);
        expect_prg(16'h8000, 19'h08000, "243: PRG = R5");
        reg2(16'h4100, 8'h06, 16'h4101, 8'h03);
        reg2(16'h4100, 8'h02, 16'h4101, 8'h01);
        expect_chr(14'h0000, 19'h1A000, "243: CHR = R6 << 2 | R2.0");
        reg2(16'h4100, 8'h07, 16'h4101, 8'h00);
        expect_a10(14'h2C00, 1, "243: mirroring 0: $2C00 en B");
        expect_a10(14'h2800, 0, "243: mirroring 0: $2800 en A");
        reg2(16'h4100, 8'h07, 16'h4101, 8'h04);
        expect_a10(14'h2400, 1, "243: mirroring 2 = vertical");
        back_to_menu;

        // ================================================= 72 / 92 (Jaleco)
        start_game(8'd72, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h8000, 8'h83);
        expect_prg(16'h8000, 19'h0C000, "72: flanco de D7 carga PRG");
        cpu_write(16'h8000, 8'h85);
        expect_prg(16'h8000, 19'h0C000, "72: sin flanco no cambia");
        cpu_write(16'h8000, 8'h00);
        cpu_write(16'h8000, 8'h45);
        expect_chr(14'h0000, 19'h0A000, "72: flanco de D6 carga CHR");
        expect_prg(16'hC000, 19'h1C000, "72: $C000 fijo");
        back_to_menu;

        start_game(8'd92, 5'b01111, 8'b001111, 8'd0);
        expect_prg(16'hC000, 19'h3C000, "92: $C000 = ultimo al arrancar");
        cpu_write(16'h8000, 8'h85);
        expect_prg(16'hC000, 19'h14000, "92: PRG en $C000");
        expect_prg(16'h8000, 19'h00000, "92: $8000 fijo al primero");
        back_to_menu;

        // ================================================= 133 (Sachen)
        start_game(8'd133, 5'b00011, 8'b000011, 8'd0);
        cpu_write(16'h4100, 8'h07);
        expect_prg(16'h8000, 19'h08000, "133: D2 = PRG");
        expect_chr(14'h0000, 19'h06000, "133: D1-D0 = CHR");
        cpu_write(16'h4000, 8'h00);
        expect_prg(16'h8000, 19'h08000, "133: $4000 (A8 = 0) no es registro");
        cpu_write(16'hC100, 8'h00);
        expect_prg(16'h8000, 19'h00000, "133: $C100 tambien es registro");
        back_to_menu;

        // ================================================= 67 (Sunsoft-3)
        start_game(8'd67, 5'b00111, 8'b011111, 8'd0);
        cpu_write(16'hF800, 8'h03);
        expect_prg(16'h8000, 19'h0C000, "67: PRG 16 KB");
        cpu_write(16'h8800, 8'h05);
        cpu_write(16'hB800, 8'h21);
        expect_chr(14'h0400, 19'h02C00, "67: CHR 2 KB en $0000");
        expect_chr(14'h1800, 19'h10800, "67: CHR 2 KB en $1800");
        cpu_write(16'h8000, 8'h07);
        expect_chr(14'h0000, 19'h02800, "67: $8000 (A11 = 0) no es registro");
        cpu_write(16'hE800, 8'h03);
        expect_a10(14'h2000, 1, "67: pantalla B");
        cpu_write(16'hC800, 8'h00);
        cpu_write(16'hC800, 8'h05);
        cpu_write(16'hD800, 8'h10);
        cycles_to_irq(20, c);
        check(c == 5, "67: IRQ al pasar de 0 a $FFFF");
        if (c != 5) $display("      ciclos hasta IRQ: %0d", c);
        cpu_write(16'hD800, 8'h00);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "67: $D800 reconoce");
        back_to_menu;

        // ================================================= 78 (Irem / Jaleco)
        start_game(8'd78, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h8000, 8'hA3);
        expect_prg(16'h8000, 19'h0C000, "78: PRG D2-D0");
        expect_chr(14'h0000, 19'h14000, "78: CHR D7-D4");
        expect_a10(14'h2400, 0, "78: D3 = 0 pantalla A");
        cpu_write(16'h8000, 8'h08);
        expect_a10(14'h2000, 1, "78: D3 = 1 pantalla B");
        back_to_menu;

        start_game(8'd78, 5'b00111, 8'b001111, 8'd8);        // Holy Diver: bit de 4 pantallas
        cpu_write(16'h8000, 8'h08);
        expect_a10(14'h2400, 1, "78 Holy Diver: D3 = 1 vertical (sin RAM de 4 pantallas)");
        cpu_write(16'h8000, 8'h00);
        expect_a10(14'h2800, 1, "78 Holy Diver: D3 = 0 horizontal");
        back_to_menu;

        // ================================================= 85 (VRC7)
        start_game(8'd85, 5'b01111, 8'b011111, 8'd0);
        cpu_write(16'h8000, 8'h03);
        cpu_write(16'h8010, 8'h04);
        cpu_write(16'h9000, 8'h05);
        expect_prg(16'h8000, 19'h06000, "85: PRG0");
        expect_prg(16'hA000, 19'h08000, "85: $8010 (VRC7a) = PRG1");
        expect_prg(16'hC000, 19'h0A000, "85: PRG2");
        cpu_write(16'h8008, 8'h06);
        expect_prg(16'hA000, 19'h0C000, "85: $8008 (VRC7b) = PRG1");
        cpu_write(16'h9010, 8'h07);
        expect_prg(16'hC000, 19'h0A000, "85: $9010 es sonido, no PRG2");
        cpu_write(16'hA008, 8'h21);
        expect_chr(14'h0400, 19'h08400, "85: CHR1");
        cpu_write(16'hE000, 8'h81);
        expect_a10(14'h2800, 1, "85: $E000 = horizontal");
        ram_write(16'h6000, 1, "85: D7 = RAM activa");
        cpu_write(16'hE008, 8'hFC);
        cpu_write(16'hF000, 8'h06);
        cycles_to_irq(20, c);
        check(c == 3, "85: IRQ VRC modo ciclo");
        if (c != 3) $display("      ciclos hasta IRQ: %0d", c);
        cpu_write(16'hF010, 8'h00);                  // A4 = A3: reconocimiento
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "85: $F010 reconoce");
        back_to_menu;

        // ================================================= 193 (NTDEC TC-112)
        start_game(8'd193, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h6003, 8'h03);
        check(!last_ram_ce, "193: $6000 es registro, no RAM");
        expect_prg(16'h8000, 19'h06000, "193: PRG $8000");
        expect_prg(16'hA000, 19'h1A000, "193: $A000 = antepenultimo");
        cpu_write(16'h6000, 8'h0A);
        cpu_write(16'h6001, 8'h0E);
        expect_chr(14'h0000, 19'h02800, "193: $0000 = D >> 1");
        expect_chr(14'h0800, 19'h03000, "193: $0800 = siguiente");
        expect_chr(14'h1000, 19'h03800, "193: $1000");
        back_to_menu;

        // ================================================= 41 / 46 / 228 / 241
        start_game(8'd41, 5'b01111, 8'b001111, 8'd0);
        cpu_write(16'h6005, 8'h00);
        expect_prg(16'h8000, 19'h28000, "41: A2-A0 = PRG 32 KB");
        cpu_write(16'h8000, 8'h03);
        expect_chr(14'h0000, 19'h06000, "41: CHR bajo (PRG >= 4)");
        cpu_write(16'h6038, 8'h00);
        expect_chr(14'h0000, 19'h1E000, "41: A4-A3 = CHR alto");
        expect_a10(14'h2800, 1, "41: A5 = horizontal");
        cpu_write(16'h8000, 8'h00);
        expect_chr(14'h0000, 19'h1E000, "41: CHR bajo bloqueado con PRG < 4");
        back_to_menu;

        start_game(8'd46, 5'b00011, 8'b001111, 8'd0);
        cpu_write(16'h6000, 8'h10);
        cpu_write(16'h8000, 8'h21);
        expect_prg(16'h8000, 19'h08000, "46: PRG = R0 << 1 | R1.0");
        expect_chr(14'h0000, 19'h14000, "46: CHR = R0 hi << 3 | R1[6:4]");
        back_to_menu;

        start_game(8'd228, 5'b01111, 8'b001111, 8'd0);
        cpu_write(16'h80E2, 8'h01);
        expect_prg(16'h8000, 19'h0C000, "228: 16 KB, banco 3");
        expect_prg(16'hC000, 19'h0C000, "228: 16 KB repetido");
        expect_chr(14'h0000, 19'h12000, "228: CHR = A3-A0 << 2 | D1-D0");
        expect_a10(14'h2400, 1, "228: A13 = 0 vertical");
        cpu_write(16'hA0C0, 8'h00);
        expect_prg(16'h8000, 19'h08000, "228: 32 KB (banco par)");
        expect_prg(16'hC000, 19'h0C000, "228: 32 KB (banco impar)");
        expect_a10(14'h2800, 1, "228: A13 = 1 horizontal");
        back_to_menu;

        start_game(8'd241, 5'b11111, CHR_RAM, 8'd0);
        cpu_write(16'h8000, 8'h05);
        expect_prg(16'h8000, 19'h28000, "241: PRG 32 KB");
        ram_write(16'h6000, 1, "241: PRG-RAM");
        back_to_menu;

        // ================================================= 247: tono de prueba en el pin 97 (cpu_exp)
        // (el testbench acelera el generador: medio segundo = 20 000 ciclos de clk)
        start_game(8'd0, 5'b00001, 8'd0, 8'd0);
        repeat (50) cpu_read(16'h0000);
        check(exp === 1'bz, "audio: sin chip de sonido, cpu_exp en Z");
        back_to_menu;
        start_game(8'd247, 5'b00001, 8'd0, 8'd0);
        expect_prg(16'h8000, 19'h00000, "247: se comporta como NROM");
        bajos = 0; altos = 0;
        for (n = 0; n < 80000; n = n + 1) begin
            @(posedge clk);
            if (exp === 1'b0) bajos = bajos + 1;
            if (exp === 1'b1) altos = altos + 1;
        end
        check(bajos > 0 && altos > bajos * 4, "247: pulsos bajos del tono, salida alta en reposo");
        $display("      247: %0d ciclos bajos, %0d altos", bajos, altos);
        back_to_menu;
        repeat (20) cpu_read(16'h0000);
        check(exp === 1'bz, "audio: en el menu, cpu_exp vuelve a Z");

        if (errors == 0) $display("OK: todas las pruebas pasaron (fase 3c)");
        else             $display("FALLARON %0d comprobaciones (fase 3c)", errors);
        $finish;
    end

endmodule
