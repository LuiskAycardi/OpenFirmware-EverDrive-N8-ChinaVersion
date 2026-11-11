// tb_fase3d.v — Testbench autoverificable de la fase 3d (la FPGA responde lecturas de la CPU):
//   115 (protección en $5000), 150 (Sachen 74LS374N), TXC 132/172/173/36, Sachen 136/147/143.
// Además de los valores leídos, tb_bus.vh vigila en todo momento que la FPGA solo conduzca en lecturas
// de registro con M2 alto y la SRAM apagada, y que suelte el bus al bajar M2.
// Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_fase3d;

`include "tb_bus.vh"

    initial begin
        repeat (4) cpu_read(16'h0000);

        // ================================================= menú del OS: nunca conduce
        expect_read(16'h5000, 8'h00, 8'h00, "OS: sin lecturas de mapper en el menu");

        // ================================================= 115 (protección $5080 -> $5000-$5FFF)
        start_game(8'd115, 5'b00111, 8'b011111, 8'd0);
        expect_read(16'h5000, 8'hFF, 8'h00, "115: sin escribir, la proteccion lee 0");
        cpu_write(16'h5080, 8'hA5);
        expect_read(16'h5000, 8'hFF, 8'hA5, "115: $5080 se lee en $5000");
        expect_read(16'h5FFF, 8'hFF, 8'hA5, "115: y en todo $5000-$5FFF");
        expect_read(16'h6000, 8'h00, 8'h00, "115: $6000 no conduce");
        expect_read(16'hD000, 8'h00, 8'h00, "115: $D000 (ROM) no conduce");
        expect_prg(16'h8000, 19'h00000, "115: $5080 no cambia la PRG");
        back_to_menu;
        // de vuelta en el menú el número de mapper sigue siendo el del último juego: no debe conducir
        expect_read(16'h5000, 8'h00, 8'h00, "OS: tras un juego con lecturas, el menu no conduce");

        // ================================================= 150 (Sachen 74LS374N)
        start_game(8'd150, 5'b00111, 8'b000111, 8'd0);
        cpu_write(16'h4100, 8'h05);
        cpu_write(16'h4101, 8'h03);
        expect_read(16'h4101, 8'h07, 8'h03, "150: lee el registro elegido en D2-D0");
        expect_prg(16'h8000, 19'h18000, "150: PRG = R5");
        cpu_write(16'h4100, 8'h04); cpu_write(16'h4101, 8'h01);
        cpu_write(16'h4100, 8'h06); cpu_write(16'h4101, 8'h02);
        expect_chr(14'h0000, 19'h0C000, "150: CHR = R4.0 << 2 | R6");
        expect_read(16'h4101, 8'h07, 8'h02, "150: registro 6");
        expect_read(16'h4100, 8'h00, 8'h00, "150: $4100 (par) no conduce");
        expect_read(16'hC101, 8'h00, 8'h00, "150: $C101 (ROM) no conduce");
        back_to_menu;

        // ================================================= 132 (TXC 22211A)
        start_game(8'd132, 5'b00011, 8'b000011, 8'd0);
        cpu_write(16'h4102, 8'h05);          // intermedio = 5
        cpu_write(16'h4100, 8'h00);          // acumulador = 5
        cpu_write(16'h8000, 8'h00);          // salida = 5
        expect_prg(16'h8000, 19'h08000, "132: PRG = salida bit 2");
        expect_chr(14'h0000, 19'h02000, "132: CHR = salida bits 1-0");
        expect_read(16'h4100, 8'h0F, 8'h05, "132: lee el acumulador");
        cpu_write(16'h4103, 8'h01);          // incrementar
        cpu_write(16'h4100, 8'h00);
        expect_read(16'h4100, 8'h0F, 8'h06, "132: incrementa");
        cpu_write(16'h4101, 8'h01);          // invertir
        expect_read(16'h4100, 8'h0F, 8'h0E, "132: invertir afecta a los bits altos");
        expect_read(16'hC100, 8'h00, 8'h00, "132: $C100 (ROM) no conduce");
        back_to_menu;

        // ================================================= 172 (TXC 22211B, JV001, bits al revés)
        start_game(8'd172, 5'b00001, 8'b001111, 8'd0);
        expect_a10(14'h2400, 1, "172: JV001 arranca con invertir = 1 (vertical)");
        cpu_write(16'h4102, 8'h30);          // al revés: 3
        cpu_write(16'h4100, 8'h00);          // acumulador = 3 ^ $FF = $FC
        cpu_write(16'h8000, 8'h00);          // salida = $0C
        expect_chr(14'h0000, 19'h18000, "172: CHR = salida");
        expect_read(16'h4100, 8'h3F, 8'h0F, "172: lectura con los bits al revés");
        cpu_write(16'h4101, 8'h00);          // invertir = 0 -> horizontal
        expect_a10(14'h2400, 0, "172: invertir = 0 -> horizontal");
        back_to_menu;

        // ================================================= 136 (Sachen 3011, JV001)
        start_game(8'd136, 5'b00001, 8'b001111, 8'd0);
        cpu_write(16'h4102, 8'h05);
        cpu_write(16'h4100, 8'h00);          // $FA
        cpu_write(16'h8000, 8'h00);          // salida $0A
        expect_chr(14'h0000, 19'h14000, "136: CHR = salida");
        expect_read(16'h4100, 8'h3F, 8'h3A, "136: lectura de 6 bits");
        back_to_menu;

        // ================================================= 147 (Sachen TC-U01, JV001, bits rotados)
        start_game(8'd147, 5'b00011, 8'b001111, 8'd0);
        cpu_write(16'h4102, 8'h14);          // rotado: 5
        cpu_write(16'h4100, 8'h00);          // $FA
        cpu_write(16'h8000, 8'h00);          // salida $0A
        expect_chr(14'h0000, 19'h0A000, "147: CHR = salida bits 4-1");
        expect_prg(16'h8000, 19'h00000, "147: PRG = salida bits 5 y 0");
        expect_read(16'h4100, 8'hFF, 8'hEB, "147: lectura de 8 bits rotada");
        back_to_menu;

        // ================================================= 36 (TXC 01-22000-400)
        start_game(8'd36, 5'b00111, 8'b001111, 8'd0);
        cpu_write(16'h4200, 8'h07);          // CHR
        expect_chr(14'h0000, 19'h0E000, "36: CHR = $4200");
        cpu_write(16'h4102, 8'h30);          // TXC: D5-D4 = 3
        cpu_write(16'h4100, 8'h00);
        cpu_write(16'h8000, 8'h00);
        expect_prg(16'h8000, 19'h18000, "36: PRG = salida bits 1-0");
        expect_read(16'h4100, 8'h30, 8'h30, "36: lectura en D5-D4");
        back_to_menu;

        // ================================================= 143 (Sachen TCA01)
        start_game(8'd143, 5'b00001, 8'd0, 8'd0);
        expect_read(16'h4100, 8'hFF, 8'h7F, "143: (~A & $3F) | $40");
        expect_read(16'h4123, 8'hFF, 8'h5C, "143: depende de A5-A0");
        expect_read(16'h4020, 8'h00, 8'h00, "143: $4020 no conduce");
        expect_prg(16'hC000, 19'h04000, "143: NROM de 32 KB");
        back_to_menu;

        // ================================================= 173 (TXC 22211C)
        start_game(8'd173, 5'b00001, 8'd0, 8'd0);       // 8 KB de CHR
        ppu_access(14'h0000, 0);
        check(chr_ce_n && ciram_ce_n, "173 (8 KB): CHR apagada al arrancar (Y = 0)");
        cpu_write(16'h8000, 8'h00);                     // cualquier escritura: Y = 1
        expect_chr(14'h0010, 19'h00010, "173 (8 KB): Y = 1 activa la CHR");
        back_to_menu;
        start_game(8'd173, 5'b00001, 8'b000111, 8'd0);  // 64 KB de CHR
        cpu_write(16'h4102, 8'h03);
        cpu_write(16'h4100, 8'h00);
        cpu_write(16'h8000, 8'h00);
        expect_chr(14'h0000, 19'h0E000, "173: CHR = salida.1, Y, salida.0");
        back_to_menu;

        // ================================================= sin lecturas: nunca conduce
        start_game(8'd4, 5'b00111, 8'b000111, 8'd0);
        expect_read(16'h5000, 8'h00, 8'h00, "MMC3: $5000 no conduce");
        expect_read(16'h4100, 8'h00, 8'h00, "MMC3: $4100 no conduce");
        back_to_menu;

        if (errors == 0) $display("OK: todas las pruebas pasaron (fase 3d)");
        else             $display("FALLARON %0d comprobaciones (fase 3d)", errors);
        $finish;
    end

endmodule
