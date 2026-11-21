// tb_prueba254.v — Testbench del mapper 254 de la prueba F0 del FDS (mapper_prueba254.v): ventana de escritura a la
// SRAM PRG en modo juego y lecturas conducidas en $40F1/$40F2. tb_bus.vh vigila además que la FPGA solo conduzca
// en lecturas de registro. Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_prueba254;

`include "tb_bus.vh"

    initial begin
        repeat (4) cpu_read(16'h0000);

        // ================================================= otro mapper: la ROM no se escribe en el juego
        start_game(8'd0, 5'b00001, 8'b000000, 8'd0);
        cpu_write(16'h8000, 8'h12);
        check(!last_prg_we, "NROM: escribir en $8000 no escribe la SRAM PRG");
        cpu_write(16'h4800, 8'h12);
        check(!last_prg_we && !last_prg_ce, "NROM: $4800 no hace nada");
        back_to_menu;

        // ================================================= 254 (prueba F0)
        start_game(8'd254, 5'b00001, 8'b000000, 8'd1);
        expect_prg(16'h8000, 19'h00000, "254: $8000 = PRG 0");
        expect_prg(16'hFFFF, 19'h07FFF, "254: $FFFF = final de los 32 KB");
        cpu_write(16'h8000, 8'h55);
        check(!last_prg_we, "254: escribir en $8000 no escribe la ROM");
        expect_read(16'h40F1, 8'hFF, 8'hA5, "254: $40F1 = $A5");
        expect_read(16'h40F2, 8'hFF, 8'h00, "254: banco 0 al empezar");
        expect_read(16'hC0F1, 8'h00, 8'h00, "254: $C0F1 (ROM) no conduce");
        expect_read(16'h40F0, 8'h00, 8'h00, "254: $40F0 no se lee");
        cpu_write(16'h40F0, 8'h37);
        expect_read(16'h40F2, 8'hFF, 8'h37, "254: $40F2 devuelve el banco");
        expect_prg(16'h4800, 19'h1B800, "254: ventana $4800 = banco $37");
        expect_prg(16'h4C00, 19'h1BC00, "254: $4C00 = A10 de la CPU");
        expect_prg(16'h4FFF, 19'h1BFFF, "254: $4FFF");
        cpu_write(16'h4805, 8'h99);
        check(last_prg_we && last_prg_ce && !last_ram_ce && last_prg_addr == 19'h1B805,
              "254: escribir la ventana escribe la SRAM PRG (y no la PRG-RAM)");
        cpu_write(16'h40F0, 8'hFF);
        expect_prg(16'h4BFF, 19'h7FBFF, "254: banco $FF llega al final de los 512 KB (sin mascara)");
        cpu_read(16'h6000);
        check(!last_prg_ce && !last_ram_ce, "254: $6000 no abre ninguna memoria");
        cpu_write(16'h6000, 8'h01);
        check(!last_prg_ce && !last_ram_ce, "254: escribir $6000 tampoco");
        cpu_read(16'h4700);
        check(!last_prg_ce, "254: $4700 no es la ventana");
        back_to_menu;
        expect_read(16'h40F1, 8'h00, 8'h00, "OS: en el menu $40F1 no conduce");
        cpu_write(16'h40F0, 8'h05);
        check(!(last_prg_we && last_prg_ce) && !last_ram_ce, "OS: $40F0 no escribe nada");

        if (errors == 0) $display("tb_prueba254: todo bien");
        else $display("tb_prueba254: %0d FALLO(S)", errors);
        $finish;
    end
endmodule
