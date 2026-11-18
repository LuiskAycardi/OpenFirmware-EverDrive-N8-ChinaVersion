// tb_255.v — Testbench del 255.RBF propio (n8_top compilado con N8_RBF_255: solo el modo OS y el NROM).
// Reproduce lo que hace la BIOS del N8 con el 255.RBF (docs/bios-n8-clon.md §1, pasos 6 y 7):
//   - con el reg 9 del CPLD a 0 (bios_off = 0), $8000-$FFFF es la flash de la BIOS: el FPGA no puede tocarlo;
//   - copia el OS.BIN a la PRG-RAM por la ventana $6000 (reg 129, bancos de 8 KiB) hasta 0x1FFFF;
//   - con el reg 9 a 1, la CPU ejecuta el OS desde la PRG-RAM en $8000 (0x18000-0x1FFFF).
// Y lo que hace después el OS propio en modo OS: ventana $4800 (reg 128), CHR (reg 130), reg 131 y vuelta al menú.
// Ejecutar: make -C hdl sim (se compila aparte, con -DN8_RBF_255).
`timescale 1ns/1ps

module tb_255;

`include "tb_bus.vh"

    integer b;

    initial begin
        $dumpfile("tb_255.vcd");
        $dumpvars(0, tb_255);

        // ---------------------------------------------------------------- la BIOS (reg 9 = 0)
        bios_off = 0;
        repeat (4) cpu_read(16'h0000);
        check(dut.os_mode == 1, "255: arranca en modo OS");
        check({mode1, mode0} == 2'b11, "255: bus_mode OS = 11");

        cpu_read(16'h8000);
        check(!last_ram_ce && !last_prg_ce, "255: con bios_off = 0, $8000 es de la flash");
        cpu_read(16'hFFFC);
        check(!last_ram_ce && !last_prg_ce, "255: con bios_off = 0, vectores de la flash");
        check(cpu_d === 8'hzz, "255: el FPGA no conduce el bus de la CPU");

        // copia del OS.BIN de 32 KiB: bancos 12-15 de la ventana $6000 = 0x18000-0x1FFFF
        for (b = 12; b < 16; b = b + 1) begin
            os_reg(8'd129, b[7:0]);
            cpu_write(16'h6000, 8'hA5);
            check(last_ram_ce && last_ram_we && last_prg_addr == {b[5:0], 13'h0000}, "255: $6000 -> banco de la PRG-RAM");
            cpu_write(16'h7FFF, 8'h5A);
            check(last_ram_ce && last_ram_we && last_prg_addr == {b[5:0], 13'h1FFF}, "255: $7FFF -> fin del banco");
            check(!last_prg_ce, "255: la copia no toca la SRAM de la PRG");
        end
        // página $FC00 de la BIOS: banco 15, $7C00 -> 0x1FC00
        os_reg(8'd129, 8'd15);
        cpu_write(16'h7C00, 8'h78);
        check(last_ram_ce && last_prg_addr == 19'h1FC00, "255: página $FC00 de la BIOS en 0x1FC00");

        // ---------------------------------------------------------------- el OS (reg 9 = 1)
        bios_off = 1;
        cpu_read(16'h8000);
        check(last_ram_ce && !last_prg_ce && last_prg_addr == 19'h18000, "255: $8000 -> PRG-RAM 0x18000");
        cpu_read(16'hFFFC);
        check(last_ram_ce && last_prg_addr == 19'h1FFFC, "255: vectores en la PRG-RAM");
        cpu_write(16'hFB00, 8'h4E);
        check(last_ram_ce && last_ram_we && last_prg_addr == 19'h1FB00, "255: el OS escribe su estado en $FB00");

        os_reg(8'd128, 8'h21);
        cpu_write(16'h4800, 8'hAA);
        check(last_prg_ce && last_prg_we && last_prg_addr == {8'h21, 1'b0, 10'h000}, "255: ventana $4800 (reg 128)");

        os_reg(8'd130, 8'd0);
        ppu_access(14'h0200, 1);
        check(!chr_ce_n && !chr_we_n && chr_map == {7'd127, 2'b00}, "255: fuente del OS en el banco 127 de la CHR");
        ppu_access(14'h2000, 0);
        check(!ciram_ce_n && chr_ce_n, "255: nametable en la CIRAM");
        ppu_access(14'h0000, 0);

        check(irq_n === 1'b1 && ppu_d === 8'hzz && cpu_d === 8'hzz, "255: sin IRQ y buses de datos en Z");

        // un juego NROM se puede lanzar sin cambiar de RBF, y el reset vuelve al modo OS
        os_reg(8'd132, 8'b00001);
        os_reg(8'd133, 8'd0);
        os_reg(8'd134, 8'd1);
        os_reg(8'd136, 8'd0);
        os_reg(8'd131, 8'd0);
        cpu_read(16'hC010);
        check(dut.os_mode == 0 && last_prg_ce && last_prg_addr == 19'h04010, "255: NROM-256 $C010");
        m2 = 0;
        #(20 * 200);
        repeat (2) cpu_read(16'h0000);
        check(dut.os_mode == 1, "255: reset -> modo OS");
        cpu_read(16'h8000);
        check(last_ram_ce && last_prg_addr == 19'h18000, "255: tras el reset, el OS sigue en la PRG-RAM");

        // ningún otro mapper: un número sin módulo (4, MMC3) cae en el NROM, el caso por defecto de n8_top
        os_reg(8'd131, 8'd4);
        cpu_read(16'hC010);
        check(dut.os_mode == 0 && last_prg_ce && last_prg_addr == 19'h04010 && irq_n === 1'b1,
              "255: mapper sin modulo -> NROM, sin IRQ");

        if (errors == 0) $display("OK: todas las pruebas pasaron");
        else             $display("ERRORES: %0d", errors);
        $finish;
    end

endmodule
