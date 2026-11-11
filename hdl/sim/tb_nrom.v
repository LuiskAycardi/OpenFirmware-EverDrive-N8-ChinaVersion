// tb_nrom.v — Testbench autoverificable para n8_top + mapper NROM.
// Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_nrom;

`include "tb_bus.vh"

    initial begin
        $dumpfile("tb_nrom.vcd");
        $dumpvars(0, tb_nrom);

        // arranque: M2 corriendo unos ciclos
        repeat (4) cpu_read(16'h0000);

        // ================================================= modo OS
        check(dut.os_mode == 1, "arranca en modo OS");
        check({mode1, mode0} == 2'b11, "bus_mode OS = 11");

        // ventana $4800 -> SRAM PRG, banco de 2 KB = 0x05
        os_reg(8'd128, 8'h05);
        cpu_write(16'h4C34, 8'hAA);
        check(last_prg_ce && last_prg_we, "OS: escritura en $4800 habilita SRAM PRG");
        check(last_prg_addr == {8'h05, 1'b1, 10'h034}, "OS: direccion ventana $4800");
        check(!last_ram_ce, "OS: $4800 no toca PRG-RAM");
        // banco 6: sus bits bajos no coinciden con A12-A11 de $4C34 (en el OS la ventana es de 2 KB y
        // PRG A12-A11 salen del banco, no de la CPU)
        os_reg(8'd128, 8'h06);
        cpu_write(16'h4C34, 8'hAA);
        check(last_prg_addr == {8'h06, 1'b1, 10'h034}, "OS: ventana $4800 con PRG A12-A11 del banco");

        // $8000 con bios_off -> PRG-RAM, offset 0x18000
        cpu_read(16'h8123);
        check(last_ram_ce && !last_prg_ce, "OS: $8000 desde PRG-RAM");
        check(last_prg_addr == 19'h18123, "OS: $8000 -> 0x18000");

        // $6000 -> PRG-RAM banco 3
        os_reg(8'd129, 8'd3);
        cpu_read(16'h7001);
        check(last_ram_ce && last_prg_addr == 19'h07001, "OS: $7001 banco 3 -> 0x7001");

        // CHR: banco 9 en $1000, banco 8 en $0000
        os_reg(8'd130, 8'd9);
        ppu_access(14'h1834, 1);
        check(!chr_ce_n && !chr_we_n, "OS: escritura CHR");
        check(chr_map == {7'd9, 2'b10}, "OS: CHR banco alto");
        ppu_access(14'h0400, 1);
        check(chr_map == {7'd8, 2'b01}, "OS: CHR banco bajo = reg-1");
        ppu_access(14'h0000, 0);

        // ================================================= configurar juego NROM-128
        os_reg(8'd132, 8'b00000);   // PRG 16 KB: A14..A18 enmascarados
        os_reg(8'd133, 8'b0000000); // CHR 8 KB, CHR-ROM
        os_reg(8'd134, 8'd1);       // mirroring vertical
        os_reg(8'd136, 8'd0);       // reset corto
        os_reg(8'd131, 8'd0);       // mapper 0 -> arranca
        cpu_read(16'h0000);
        check(dut.os_mode == 0, "juego activo tras reg 131");
        check({mode1, mode0} == 2'b01, "bus_mode juego = 01");

        // escribir registros en modo juego no cambia nada
        os_reg(8'd131, 8'hFF);
        check(dut.os_mode == 0, "juego: $4401 bloqueado");

        // PRG: $8000 y $C000 deben verse iguales (16 KB espejado)
        cpu_read(16'h8010);
        check(last_prg_ce && !last_ram_ce && last_prg_addr == 19'h00010, "NROM-128 $8010");
        cpu_read(16'hC010);
        check(last_prg_addr == 19'h00010, "NROM-128 $C010 espeja $8010");
        cpu_write(16'h8000, 8'h55);
        check(!last_prg_we, "juego: SRAM PRG no escribible");

        // PRG-RAM $6000
        cpu_write(16'h6005, 8'h12);
        check(last_ram_ce && last_ram_we && last_prg_addr == 19'h00005, "PRG-RAM $6005");
        cpu_read(16'h5000);
        check(!last_ram_ce && !last_prg_ce, "$5000 no selecciona memoria");

        // mirroring vertical: $2400 -> A10=1, $2800 -> A10=0
        ppu_access(14'h2400, 0);
        check(!ciram_ce_n && ciram_a10 == 1 && chr_ce_n && ppu_ex, "vertical $2400");
        ppu_access(14'h2800, 0);
        check(ciram_a10 == 0, "vertical $2800");

        // CHR-ROM: lectura sí, escritura no
        ppu_access(14'h1C00, 0);
        check(!chr_ce_n && chr_map == 9'b000000111, "CHR $1C00");
        ppu_access(14'h1C00, 1);
        check(chr_we_n, "CHR-ROM no escribible");
        ppu_access(14'h0000, 0);

        check(irq_n === 1'b1, "NROM sin IRQ");
        check(cpu_d === 8'hzz && ppu_d === 8'hzz, "buses de datos en Z");

        // ================================================= reset: M2 parado -> menú
        m2 = 0;
        #(20 * 200);       // 200 ciclos de clk sin M2
        check(prg_ce_n && !ram_ce && chr_ce_n, "M2 parado: memorias apagadas");
        repeat (2) cpu_read(16'h0000);
        check(dut.os_mode == 1, "reset corto vuelve al menú");

        // ================================================= NROM-256 + horizontal + CHR-RAM
        os_reg(8'd132, 8'b00001);   // A14 visible
        os_reg(8'd133, CHR_RAM);    // CHR-RAM ($FF, como el OS)
        os_reg(8'd134, 8'd0);       // horizontal
        os_reg(8'd136, 8'd1);       // reset largo
        os_reg(8'd131, 8'd0);
        cpu_read(16'hC010);
        check(last_prg_addr == 19'h04010, "NROM-256 $C010 -> 0x4010");
        ppu_access(14'h2800, 0);
        check(ciram_a10 == 1, "horizontal $2800 -> A10=1");
        ppu_access(14'h2400, 0);
        check(ciram_a10 == 0, "horizontal $2400 -> A10=0");
        ppu_access(14'h0100, 1);
        check(!chr_we_n && !chr_ce_n, "CHR-RAM escribible");
        ppu_access(14'h0000, 0);

        // reset corto con modo largo: el juego sigue
        m2 = 0;
        #(20 * 200);
        repeat (2) cpu_read(16'h0000);
        check(dut.os_mode == 0, "modo largo: reset corto mantiene el juego");

        if (errors == 0) $display("OK: todas las pruebas pasaron");
        else             $display("ERRORES: %0d", errors);
        $finish;
    end

endmodule
