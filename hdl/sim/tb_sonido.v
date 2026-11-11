// tb_sonido.v — Testbench autoverificable del sonido de expansión: VRC6 (24/26), Sunsoft 5B (69) y el
// convertidor de 1 bit del pin 97 (audio_dac.v). Se observa el nivel que entra al convertidor
// (dut.snd_level, 0-1023) en cada ciclo de CPU, y la densidad de pulsos en el pin.
// Ejecutar: make -C hdl sim
`timescale 1ns/1ps

module tb_sonido;

`include "tb_bus.vh"

    integer n, hi, mx, mn, cambios, prev, v;

    // muestras del nivel durante 'ciclos' ciclos de CPU: cuántas valen 'valor', máximo, mínimo y cambios
    task medir(input integer ciclos, input integer valor);
        begin
            hi = 0; mx = 0; mn = 1023; cambios = 0; prev = -1;
            for (n = 0; n < ciclos; n = n + 1) begin
                cpu_read(16'h0000);
                v = dut.snd_level;
                if (v == valor) hi = hi + 1;
                if (v > mx) mx = v;
                if (v < mn) mn = v;
                if (prev >= 0 && v != prev) cambios = cambios + 1;
                prev = v;
            end
        end
    endtask

    task r5b(input [3:0] r, input [7:0] val);
        begin cpu_write(16'hC000, {4'd0, r}); cpu_write(16'hE000, val); end
    endtask

    // Densidad de pulsos bajos en el pin 97 mientras la CPU sigue funcionando (con M2 parado, el top lo
    // tomaría por un reset de la consola y volvería al menú).
    reg contar = 0;
    integer bajos = 0, total = 0;
    always @(posedge clk) if (contar) begin total = total + 1; if (exp === 1'b0) bajos = bajos + 1; end
    task densidad(input integer ciclos_cpu);
        begin
            bajos = 0; total = 0; contar = 1;
            repeat (ciclos_cpu) cpu_read(16'h0000);
            contar = 0;
        end
    endtask

    initial begin
        repeat (4) cpu_read(16'h0000);

        // ##################################################################### VRC6 (24)
        start_game(8'd24, 5'b01111, 8'b011111, 8'd0);
        check(exp === 1'b1 || exp === 1'b0, "VRC6: el pin 97 se conduce con un mapper con sonido");
        medir(20, 0);
        check(mx == 0, "VRC6: silencio al arrancar");
        // pulso 1 en modo D7 (volumen fijo)
        cpu_write(16'h9000, 8'h8F);
        cpu_write(16'h9002, 8'h80);
        medir(50, 120);
        check(hi == 50, "VRC6: pulso en modo D7 = volumen 15 fijo (15 x 8)");
        // ciclo de trabajo 3 (4/16), periodo 9 -> 10 ciclos por paso, 160 por vuelta
        cpu_write(16'h9000, 8'h3F);
        cpu_write(16'h9001, 8'h09);
        cpu_write(16'h9002, 8'h80);
        medir(320, 120);
        check(hi >= 76 && hi <= 84, "VRC6: ciclo de trabajo 4/16");
        check(cambios >= 3 && cambios <= 5, "VRC6: 160 ciclos por vuelta");
        $display("      VRC6 pulso: %0d/320 ciclos arriba, %0d cambios", hi, cambios);
        // /16: periodo $090 >> 4 = 9 -> igual que antes
        cpu_write(16'h9001, 8'h90);
        cpu_write(16'h9003, 8'h02);
        medir(320, 120);
        check(hi >= 76 && hi <= 84 && cambios >= 3 && cambios <= 5, "VRC6: $9003 D1 divide el periodo entre 16");
        // detener: el paso no avanza (con /16, sin detener cambiaría cada 40-120 ciclos)
        cpu_write(16'h9003, 8'h03);
        medir(200, 120);
        check(cambios == 0, "VRC6: $9003 D0 detiene los canales");
        cpu_write(16'h9003, 8'h00);
        cpu_write(16'h9002, 8'h00);
        medir(30, 0);
        check(hi == 30, "VRC6: E = 0 apaga el pulso");
        // sierra: paso 42, periodo 0 (un paso por ciclo): 6 sumas -> 252 -> 31
        cpu_write(16'hB000, 8'h2A);
        cpu_write(16'hB001, 8'h00);
        cpu_write(16'hB002, 8'h80);
        medir(56, 0);
        check(mx == 31 * 8 && mn == 0, "VRC6: sierra de 0 a 31");
        $display("      VRC6 sierra: max %0d, min %0d", mx, mn);
        cpu_write(16'hB000, 8'h08);
        cpu_write(16'hB002, 8'h00);          // reinicia el acumulador
        cpu_write(16'hB002, 8'h80);
        medir(56, 0);
        check(mx == 6 * 8, "VRC6: sierra con paso 8 llega a 6");
        cpu_write(16'hB002, 8'h00);
        medir(20, 0);
        check(hi == 20, "VRC6: E = 0 pone la sierra a 0");
        // pulso 2 y suma
        cpu_write(16'hA000, 8'h85);
        cpu_write(16'hA002, 8'h80);
        cpu_write(16'h9000, 8'h83);
        cpu_write(16'h9002, 8'h80);
        medir(10, (5 + 3) * 8);
        check(hi == 10, "VRC6: suma de los dos pulsos");
        // densidad de pulsos en el pin: nivel 64/1024
        densidad(400);
        check(bajos * 1024 >= total * 63 && bajos * 1024 <= total * 65, "DAC: densidad de pulsos = nivel / 1024");
        $display("      DAC: %0d bajos de %0d (nivel 64 -> %0d)", bajos, total, total * 64 / 1024);
        back_to_menu;
        repeat (4) cpu_read(16'h0000);
        check(exp === 1'bz, "audio: en el menu, el pin 97 en Z");

        // ##################################################################### VRC6b (26)
        start_game(8'd26, 5'b01111, 8'b011111, 8'd0);
        cpu_write(16'h9000, 8'h8F);
        cpu_write(16'h9001, 8'h80);          // A0 -> A1: registro 2 (activar)
        medir(10, 120);
        check(hi == 10, "VRC6b: A0/A1 intercambiados también en el sonido");
        back_to_menu;

        // ##################################################################### Sunsoft 5B (69)
        start_game(8'd69, 5'b01111, 8'b011111, 8'd0);
        medir(20, 0);
        check(mx == 0, "5B: silencio al arrancar");
        r5b(4'h7, 8'h3E);                    // solo tono A
        r5b(4'h8, 8'h0F);
        r5b(4'h0, 8'h04);                    // periodo 4 -> 128 ciclos por vuelta
        r5b(4'h1, 8'h00);
        medir(512, 177);
        check(mx == 177 && mn == 0, "5B: tono A a volumen 15 = 177");
        check(hi >= 248 && hi <= 264 && cambios >= 7 && cambios <= 9, "5B: periodo de 32 x 4 ciclos");
        $display("      5B tono: %0d/512 arriba, %0d cambios", hi, cambios);
        r5b(4'h8, 8'h08);
        medir(256, 15);
        check(mx == 15, "5B: volumen 8 = 15 (1,5 dB por nivel)");
        r5b(4'h8, 8'h00);
        medir(64, 0);
        check(hi == 64, "5B: volumen 0 = silencio");
        // tono y ruido apagados: nivel fijo
        r5b(4'h7, 8'h3F);
        r5b(4'h8, 8'h0F);
        medir(64, 177);
        check(hi == 64, "5B: tono y ruido apagados = nivel fijo");
        // DAC con nivel fijo 177
        densidad(400);
        check(bajos * 1024 >= total * 176 && bajos * 1024 <= total * 178, "DAC: nivel 177 / 1024");
        // registro con bits altos: $E000 no escribe
        cpu_write(16'hC000, 8'h18);
        cpu_write(16'hE000, 8'h00);
        medir(16, 177);
        check(hi == 16, "5B: seleccion con bits altos no escribe");
        // envolvente /‾‾ (subir y mantener arriba), periodo 1 = un paso cada 16 ciclos
        r5b(4'hB, 8'h01);
        r5b(4'hC, 8'h00);
        r5b(4'h8, 8'h10);
        r5b(4'hD, 8'h0D);
        medir(4, 0);
        check(mx <= 1, "5B: la envolvente empieza abajo");
        medir(240, 0);
        check(mx >= 9 && mx <= 18, "5B: la envolvente sube (mitad de la rampa)");
        $display("      5B envolvente a mitad: %0d", mx);
        medir(400, 177);
        check(hi >= 100 && mx == 177, "5B: la envolvente llega a 31 y se mantiene");
        // forma 8 (\\\\): rampa de bajada que se repite
        r5b(4'hD, 8'h08);
        medir(1100, 177);
        check(hi >= 2 && mn <= 1, "5B: forma 8 se repite");
        // ruido en el canal A
        r5b(4'h8, 8'h0F);
        r5b(4'h6, 8'h01);
        r5b(4'h7, 8'h37);
        medir(2000, 177);
        check(hi > 300 && hi < 1700 && cambios > 20, "5B: ruido en el canal A");
        $display("      5B ruido: %0d/2000 arriba, %0d cambios", hi, cambios);
        back_to_menu;

        // ##################################################################### sin sonido
        start_game(8'd4, 5'b00111, 8'b000111, 8'd0);
        cpu_write(16'hC000, 8'h07);
        repeat (20) cpu_read(16'h0000);
        check(exp === 1'bz, "audio: MMC3 (sin sonido) deja el pin 97 en Z");
        back_to_menu;

        if (errors == 0) $display("OK: todas las pruebas pasaron (sonido)");
        else             $display("FALLARON %0d comprobaciones (sonido)", errors);
        $finish;
    end

endmodule
