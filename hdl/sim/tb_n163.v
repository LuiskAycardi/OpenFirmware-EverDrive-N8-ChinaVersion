// tb_n163.v — Testbench autoverificable del Namco 163 (mapper 19): bancos, CIRAM como CHR y nametables,
// protección de la PRG-RAM, IRQ legible, puerto de la RAM interna y sonido de tabla de ondas.
// Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_n163;

`include "tb_bus.vh"

    integer n, c, hi, lo, cambios, prev, v;

    task cycles_to_irq(input integer max, output integer cycles);
        begin
            cycles = -1;
            for (n = 1; n <= max && cycles < 0; n = n + 1) begin
                cpu_read(16'h0000);
                if (irq_n === 1'b0) cycles = n;
            end
        end
    endtask

    // cuenta ciclos de CPU con el nivel de sonido = a o = b, y cambios
    task medir2(input integer ciclos, input integer a, input integer b);
        begin
            hi = 0; lo = 0; cambios = 0; prev = -1;
            for (n = 0; n < ciclos; n = n + 1) begin
                cpu_read(16'h0000);
                v = dut.snd_level;
                if (v == a) hi = hi + 1;
                if (v == b) lo = lo + 1;
                if (prev >= 0 && v != prev) cambios = cambios + 1;
                prev = v;
            end
        end
    endtask

    task ram_w(input [6:0] addr, input [7:0] val);
        begin cpu_write(16'hF800, {1'b0, addr}); cpu_write(16'h4800, val); end
    endtask

    initial begin
        repeat (4) cpu_read(16'h0000);
        start_game(8'd19, 5'b01111, 8'b011111, 8'd1);

        // ---------------------------------------------------- PRG
        cpu_write(16'hE000, 8'h03);
        cpu_write(16'hE800, 8'h04);
        cpu_write(16'hF000, 8'h05);
        expect_prg(16'h8000, 19'h06000, "N163: $E000 = PRG en $8000");
        expect_prg(16'hA000, 19'h08000, "N163: $E800 = PRG en $A000");
        expect_prg(16'hC000, 19'h0A000, "N163: $F000 = PRG en $C000");
        expect_prg(16'hE000, 19'h3E000, "N163: $E000-$FFFF fijo al ultimo");

        // ---------------------------------------------------- CHR y nametables
        expect_a10(14'h2400, 1, "N163: nametables sin escribir = cabecera (vertical)");
        cpu_write(16'h8000, 8'h10);
        expect_chr(14'h0000, 19'h04000, "N163: CHR 1 KB");
        cpu_write(16'h8000, 8'hE1);
        expect_a10(14'h0010, 1, "N163: >= $E0 = CIRAM pagina 1 como CHR");
        cpu_write(16'hE800, 8'h44);                     // D6: sin CIRAM en $0000-$0FFF
        expect_chr(14'h0000, 19'h38400, "N163: $E800 D6 = CHR-ROM aunque sea >= $E0");
        cpu_write(16'hB800, 8'hE0);
        expect_a10(14'h1C00, 0, "N163: $1000-$1FFF sigue con CIRAM (D7 = 0)");
        cpu_write(16'hC000, 8'hE0);
        cpu_write(16'hC800, 8'hE1);
        cpu_write(16'hD000, 8'h05);
        expect_a10(14'h2000, 0, "N163: $C000 = CIRAM pagina 0");
        expect_a10(14'h2400, 1, "N163: $C800 = CIRAM pagina 1");
        expect_chr(14'h2800, 19'h01400, "N163: $D000 = nametable de CHR-ROM");

        // ---------------------------------------------------- PRG-RAM con protección
        cpu_write(16'h6000, 8'h55);
        check(last_ram_ce === 1'b0 || !last_ram_we, "N163: PRG-RAM protegida al arrancar");
        cpu_write(16'hF800, 8'h40);
        cpu_write(16'h6000, 8'h55);
        check(last_ram_ce && last_ram_we, "N163: $F800 D6 permite escribir");
        cpu_write(16'hF800, 8'h41);
        cpu_write(16'h6000, 8'h55);
        check(!(last_ram_ce && last_ram_we), "N163: D0 protege $6000-$67FF");
        cpu_write(16'h6800, 8'h55);
        check(last_ram_ce && last_ram_we, "N163: $6800 sigue escribible");
        cpu_read(16'h6000);
        check(last_ram_ce, "N163: la PRG-RAM se lee aunque este protegida");

        // ---------------------------------------------------- IRQ
        cpu_write(16'h5000, 8'hFC);
        cpu_write(16'h5800, 8'hFF);                     // activo, cuenta $7FFC
        cycles_to_irq(10, c);
        check(c == 2, "N163: IRQ al llegar a $7FFF");
        if (c != 2) $display("      ciclos hasta IRQ: %0d", c);
        expect_read(16'h5000, 8'hFF, 8'hFF, "N163: $5000 se lee");
        expect_read(16'h5800, 8'hFF, 8'hFF, "N163: $5800 se lee");
        cpu_write(16'h5800, 8'h00);
        cpu_read(16'h0000);
        check(irq_n === 1'b1, "N163: escribir $5800 reconoce");

        // ---------------------------------------------------- RAM interna por $4800
        cpu_write(16'hF800, 8'h80);                     // dirección 0, autoincremento
        cpu_write(16'h4800, 8'h11);
        cpu_write(16'h4800, 8'h22);
        cpu_write(16'h4800, 8'h33);
        cpu_write(16'hF800, 8'h80);
        expect_read(16'h4800, 8'hFF, 8'h11, "N163: RAM[0]");
        expect_read(16'h4800, 8'hFF, 8'h22, "N163: autoincremento al leer");
        expect_read(16'h4800, 8'hFF, 8'h33, "N163: RAM[2]");
        cpu_write(16'hF800, 8'h01);                     // sin autoincremento
        expect_read(16'h4800, 8'hFF, 8'h22, "N163: sin autoincremento");
        expect_read(16'h4800, 8'hFF, 8'h22, "N163: misma posicion");

        // ---------------------------------------------------- sonido
        // onda de 4 muestras: 0, 15, 0, 15 (RAM[0] = RAM[1] = $F0); canal 7, frecuencia 1 muestra por paso
        ram_w(7'h00, 8'hF0);
        ram_w(7'h01, 8'hF0);
        ram_w(7'h78, 8'h00);                            // frecuencia baja
        ram_w(7'h7A, 8'h00);                            // frecuencia media
        ram_w(7'h7C, 8'hFD);                            // largo 4 (& $FC = $FC), frecuencia bit 16 = 1
        ram_w(7'h7E, 8'h00);                            // dirección de la onda
        ram_w(7'h7F, 8'h0F);                            // volumen 15, 1 canal
        medir2(150, 450, 0);
        check(hi > 30 && lo > 30 && cambios >= 8 && cambios <= 11, "N163: canal 7 alterna (15-8)x15 y (0-8)x15");
        $display("      N163 1 canal: %0d en 450, %0d en 0, %0d cambios", hi, lo, cambios);
        // 3 canales (los 5 y 6 en silencio): media de 3, truncada hacia cero
        ram_w(7'h7F, 8'h2F);
        medir2(200, 240 + 2 * 35, 240 - 2 * 40);
        check(hi > 20 && lo > 20, "N163: 3 canales: 105/3 = 35 y -120/3 = -40");
        $display("      N163 3 canales: %0d en 310, %0d en 160", hi, lo);
        // $E000 D6: sonido parado
        cpu_write(16'hE000, 8'h43);
        medir2(100, 0, 0);
        check(cambios == 0, "N163: $E000 D6 para el sonido");
        expect_prg(16'h8000, 19'h06000, "N163: $E000 D6 no cambia la PRG");
        check(exp === 1'b0 || exp === 1'b1, "N163: el pin 97 se conduce");
        back_to_menu;

        if (errors == 0) $display("OK: todas las pruebas pasaron (N163)");
        else             $display("FALLARON %0d comprobaciones (N163)", errors);
        $finish;
    end

endmodule
