// tb_fds.v — Testbench autoverificable del mapper FDS (254, mapper_fds.v): BIOS, RAM de 32 KB, zona del parche,
// ventana del disco, temporizador IRQ, mirroring, CHR-RAM y lecturas conducidas. tb_bus.vh vigila además que la FPGA
// solo conduzca en lecturas de registro. Ejecutar: make -C hdl sim
`timescale 1ns/1ps
`define FDS_FOTOGRAMA 200                     // fotogramas cortos para el banco

module tb_fds;

`include "tb_bus.vh"

    // RAM del FDS: dirección que ve la PRG-RAM en el último ciclo
    task expect_ram(input [15:0] addr, input wr, input [18:0] want, input [8*64-1:0] msg);
        begin
            cpu_cycle(addr, !wr, 8'h5A);
            check(last_ram_ce && !last_prg_ce && last_prg_addr == want && (last_ram_we == wr) && !last_prg_we, msg);
            if (!(last_ram_ce && last_prg_addr == want))
                $display("      ram_ce %b prg_ce %b dir 0x%05h, esperada 0x%05h", last_ram_ce, last_prg_ce,
                         last_prg_addr, want);
        end
    endtask

    // Una lectura en la que el dato lo pone la consola (el mando en $4016: D0 y los bits altos del bus abierto).
    task lee_consola(input [15:0] addr, input [7:0] dato);
        begin
            m2 = 0; cpu_a = addr[14:0]; cur_a15 = addr[15]; cpu_rw = 1; cpu_drive = 1; cpu_dout = dato;
            #280; m2 = 1; #25; romsel_n = !addr[15]; #255; m2 = 0; #15; romsel_n = 1; #5; cpu_drive = 0;
        end
    endtask
    // Lectura completa del mando 1 como un juego: strobe y 8 lecturas (A, B, Select, Start, arriba ... derecha).
    task mando(input [7:0] botones);
        integer i;
        begin
            cpu_write(16'h4016, 8'h01);
            cpu_write(16'h4016, 8'h00);
            for (i = 7; i >= 0; i = i - 1) lee_consola(16'h4016, {7'b0100000, botones[i]});
        end
    endtask

    integer k;

    task ciclos(input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) cpu_read(16'h0000); end
    endtask

    wire irq_on = (irq_n === 1'b0);

    initial begin
        repeat (4) cpu_read(16'h0000);
        start_game(8'd254, 5'b00000, CHR_RAM, 8'd0);

        // ================================================= memoria
        expect_prg(16'hE000, 19'h7E000, "FDS: $E000 = BIOS (0x7E000)");
        expect_prg(16'hFFFC, 19'h7FFFC, "FDS: vectores de la BIOS");
        cpu_write(16'hE123, 8'h00);
        check(!last_prg_we && !last_ram_we, "FDS: la BIOS no se escribe");
        expect_ram(16'h6000, 0, 19'h00000, "FDS: $6000 = RAM 0x0000");
        expect_ram(16'h7FFF, 1, 19'h01FFF, "FDS: escribir $7FFF = RAM 0x1FFF");
        expect_ram(16'h8000, 1, 19'h02000, "FDS: escribir $8000 = RAM 0x2000");
        expect_ram(16'hC123, 0, 19'h06123, "FDS: $C123 = RAM 0x6123");
        expect_ram(16'hDFFF, 1, 19'h07FFF, "FDS: escribir $DFFF = RAM 0x7FFF");
        expect_prg(16'h5000, 19'h7D000, "FDS: $5000 = parche (0x7D000)");
        expect_prg(16'h5FFF, 19'h7DFFF, "FDS: $5FFF = parche (0x7DFFF)");
        cpu_write(16'h5000, 8'h00);
        check(!last_prg_we && !last_ram_ce, "FDS: el parche no se escribe");

        // ================================================= ventana del disco y cabeza
        cpu_read(16'h4800);
        check(!last_prg_ce && !last_ram_ce, "FDS: ventana apagada al empezar");
        cpu_write(16'h4212, 8'hFD);
        cpu_write(16'h4213, 8'hFF);
        cpu_write(16'h4214, 8'hFB);
        expect_read(16'h4212, 8'hFF, 8'h05, "FDS: $4212 = cara (3 bits)");
        expect_read(16'h4213, 8'hFF, 8'hFF, "FDS: $4213 = cabeza, byte bajo");
        expect_read(16'h4214, 8'hFF, 8'hFB, "FDS: $4214 = cabeza, byte alto");
        cpu_write(16'h4215, 8'h00);
        expect_read(16'h4213, 8'hFF, 8'h00, "FDS: $4215 avanza la cabeza (bajo)");
        expect_read(16'h4214, 8'hFF, 8'hFC, "FDS: y lleva al byte alto");
        cpu_write(16'h4210, 8'h01);
        expect_prg(16'h4800, 19'h5FC00, "FDS: ventana = cara 5, banco de 1 KB de la cabeza ($FC00)");
        expect_prg(16'h4BFF, 19'h5FFFF, "FDS: final de la ventana");
        cpu_read(16'h4C00);
        check(!last_prg_ce, "FDS: $4C00 ya no es ventana");
        cpu_write(16'h4A01, 8'h77);
        check(last_prg_we && last_prg_ce && !last_ram_ce && last_prg_addr == 19'h5FE01, "FDS: escribir el disco");
        cpu_write(16'h4216, 8'h3C);
        expect_read(16'h4216, 8'hFF, 8'h3C, "FDS: $4216 byte de apoyo");
        cpu_write(16'h4212, 8'h00);
        cpu_write(16'h4213, 8'h00);
        cpu_write(16'h4214, 8'h00);
        expect_prg(16'h4800, 19'h00000, "FDS: cara 0, cabeza 0 = 0x00000");
        cpu_write(16'h4210, 8'h00);
        cpu_read(16'h4800);
        check(!last_prg_ce, "FDS: ventana apagada otra vez");

        // ================================================= temporizador
        check(!irq_on, "FDS: sin IRQ al empezar");
        cpu_write(16'h4020, 8'h05);
        cpu_write(16'h4021, 8'h00);
        cpu_write(16'h4022, 8'h02);                 // activa, sin repetir: cuenta 5..0 y pide en el 6.º ciclo
        ciclos(5);
        check(!irq_on, "FDS: 5 ciclos: aun sin IRQ");
        ciclos(1);
        check(irq_on, "FDS: 6.o ciclo: IRQ");
        expect_read(16'h4030, 8'hDB, 8'h01, "FDS: $4030 D0 = IRQ");
        check(!irq_on, "FDS: leer $4030 reconoce");
        ciclos(20);
        check(!irq_on, "FDS: sin repetir no vuelve");
        cpu_write(16'h4022, 8'h03);                 // repetir
        ciclos(6);
        check(irq_on, "FDS: repetir: IRQ a los 6");
        expect_read(16'h422E, 8'hDB, 8'h01, "FDS: $422E = estado");
        check(!irq_on, "FDS: leer $422E reconoce");
        ciclos(4);
        check(!irq_on, "FDS: repetir: recarga con $4020/$4021 (aun sin IRQ)");
        ciclos(1);
        check(irq_on, "FDS: repetir: otra IRQ (periodo 6 contando la lectura)");
        cpu_write(16'h4022, 8'h00);
        check(!irq_on, "FDS: $4022 con D1 = 0 reconoce");
        cpu_write(16'h4022, 8'h03);
        ciclos(3);
        cpu_write(16'h4023, 8'h00);
        check(!irq_on, "FDS: $4023 D0 = 0 para");
        ciclos(20);
        check(!irq_on, "FDS: y no vuelve");
        cpu_write(16'h4022, 8'h02);
        ciclos(20);
        check(!irq_on, "FDS: con el disco apagado ($4023) no se activa");
        cpu_write(16'h4023, 8'h83);
        cpu_write(16'h4020, 8'h00);
        cpu_write(16'h4021, 8'h01);                 // 256
        cpu_write(16'h4022, 8'h02);
        ciclos(256);
        check(!irq_on, "FDS: recarga de 16 bits: 256 ciclos sin IRQ");
        ciclos(1);
        check(irq_on, "FDS: y al 257.o, IRQ");
        cpu_read(16'h4030);

        // ================================================= mirroring, CHR, estado
        cpu_write(16'h4025, 8'h00);
        expect_a10(14'h2400, 1'b1, "FDS: vertical: $2400 = A10");
        expect_a10(14'h2800, 1'b0, "FDS: vertical: $2800 = 0");
        cpu_write(16'h4025, 8'h08);
        expect_a10(14'h2400, 1'b0, "FDS: horizontal: $2400 = 0");
        expect_a10(14'h2800, 1'b1, "FDS: horizontal: $2800 = A11");
        expect_read(16'h4030, 8'hDB, 8'h08, "FDS: $4030 D3 = mirroring");
        expect_read(16'h4032, 8'h07, 8'h00, "FDS: $4032 = dentro, listo, sin proteccion");
        expect_read(16'h4033, 8'h80, 8'h80, "FDS: $4033 D7 = bateria bien");
        expect_read(16'h4031, 8'h00, 8'h00, "FDS: $4031 no se conduce");
        expect_read(16'h4210, 8'h00, 8'h00, "FDS: $4210 no se lee");

        // ================================================= $4231 y disco fuera ($4230)
        expect_read(16'h4217, 8'hFF, 8'h00, "FDS: $4217 cuenta del boton, legible (a cero)");
        expect_read(16'h4219, 8'h00, 8'h00, "FDS: $4219 no se conduce");
        expect_read(16'h4231, 8'h80, 8'h80, "FDS: $4231 = $80");
        expect_read(16'h4230, 8'hFF, 8'h40, "FDS: $4230 = dentro");
        cpu_write(16'h4215, 8'h00);                 // actividad del disco: 77 fotogramas sin poder salir
        repeat (30) cpu_read(16'h4230);
        expect_read(16'h4230, 8'hFF, 8'h40, "FDS: recien leido el disco no sale");
        ciclos(77 * 200);
        repeat (22) cpu_read(16'h4230);
        expect_read(16'h4230, 8'hFF, 8'h47, "FDS: 22 lecturas seguidas: disco fuera");
        expect_read(16'h4032, 8'h07, 8'h00, "FDS: $4032 (la BIOS) sigue viendo el disco");
        ciclos(70 * 200);
        expect_read(16'h4230, 8'hFF, 8'h47, "FDS: 70 fotogramas despues sigue fuera");
        ciclos(10 * 200);
        expect_read(16'h4230, 8'hFF, 8'h40, "FDS: a los 78 vuelve a estar dentro");
        repeat (30) cpu_read(16'h4230);
        expect_read(16'h4230, 8'hFF, 8'h40, "FDS: y no vuelve a salir enseguida");
        cpu_write(16'h4218, 8'h00);                 // cambio de cara a mano: fuera aunque no pueda salir
        expect_read(16'h4230, 8'hFF, 8'h47, "FDS: $4218 saca el disco al momento");
        ciclos(70 * 200);
        expect_read(16'h4230, 8'hFF, 8'h47, "FDS: $4218: 70 fotogramas despues sigue fuera");
        ciclos(10 * 200);
        expect_read(16'h4230, 8'hFF, 8'h40, "FDS: $4218: a los 78 vuelve a estar dentro");

        // ================================================= cambio de cara a mano (B + Select 45 fotogramas)
        cpu_write(16'h4219, 8'h02);                 // 2 caras
        cpu_write(16'h4212, 8'h00);
        repeat (40) begin cpu_write(16'h4217, 8'h00); ciclos(199); end      // aviso del parche, uno por fotograma
        expect_read(16'h4212, 8'hFF, 8'h00, "FDS: boton: 40 fotogramas, aun la cara 0");
        repeat (10) begin cpu_write(16'h4217, 8'h00); ciclos(199); end
        expect_read(16'h4212, 8'hFF, 8'h01, "FDS: boton: 50 fotogramas, cara 1");
        expect_read(16'h4230, 8'hFF, 8'h47, "FDS: boton: y el disco fuera");
        repeat (30) begin cpu_write(16'h4217, 8'h00); ciclos(199); end
        expect_read(16'h4212, 8'hFF, 8'h01, "FDS: boton mantenido: una sola vuelta");
        ciclos(15 * 200);
        expect_read(16'h4217, 8'hFF, 8'h00, "FDS: boton soltado: la cuenta vuelve a cero");
        repeat (5) begin cpu_write(16'h4217, 8'h00); ciclos(199); end
        ciclos(3 * 200);                            // un hueco corto (juego que no lee el mando) no la borra
        repeat (5) begin cpu_write(16'h4217, 8'h00); ciclos(199); end
        check(dut.m254.boton >= 6'd9, "FDS: boton: un hueco de 3 fotogramas no pone la cuenta a cero");
        ciclos(15 * 200);
        // espiando el mando: strobe y A, B, Select, ... en D0
        repeat (50) begin mando(8'b0110_0000); ciclos(190); end
        expect_read(16'h4212, 8'hFF, 8'h00, "FDS: espiando $4016 (B + Select): cara 0, dando la vuelta");
        ciclos(15 * 200);
        repeat (50) begin mando(8'b0100_0000); ciclos(190); end
        expect_read(16'h4212, 8'hFF, 8'h00, "FDS: espiando $4016 (solo B): no cambia");
        repeat (50) begin mando(8'b1010_0000); ciclos(190); end
        expect_read(16'h4212, 8'hFF, 8'h00, "FDS: espiando $4016 (A + Select): no cambia");
        expect_chr(14'h1FFF, 19'h01FFF, "FDS: CHR-RAM de 8 KB");
        ppu_access(14'h0123, 1);
        check(!chr_we_n && !chr_ce_n, "FDS: la CHR-RAM se escribe");
        ppu_access(14'h0000, 0);

        // ================================================= sonido ($4040-$408A, snd_fds.v)
        cpu_write(16'h4023, 8'h03);                 // registros del disco y del sonido
        cpu_write(16'h4089, 8'h80);                 // escribir la onda: rampa 0-63
        for (k = 0; k < 64; k = k + 1) cpu_write(16'h4040 + k, k[7:0]);
        expect_read(16'h4045, 8'h3F, 8'h05, "FDS sonido: la onda se lee (escritura activa)");
        cpu_write(16'h4089, 8'h00);                 // volumen 2/2
        cpu_write(16'h4080, 8'hA0);                 // envolvente apagada, ganancia 32
        expect_read(16'h4090, 8'h3F, 8'h20, "FDS sonido: $4090 = ganancia 32");
        cpu_write(16'h4087, 8'h80);                 // modulador parado
        cpu_write(16'h4082, 8'h00);
        cpu_write(16'h4083, 8'h04);                 // frecuencia $400: un paso de la onda cada 64 ciclos
        ciclos(64 * 10);
        check(dut.m254.sonido.o_pos >= 6'd9 && dut.m254.sonido.o_pos <= 6'd11,
              "FDS sonido: la onda avanza un paso cada 64 ciclos");
        check(dut.m254.snd_nivel + 6'd1 >= dut.m254.sonido.o_pos && dut.m254.snd_nivel <= dut.m254.sonido.o_pos,
              "FDS sonido: con ganancia 32 y volumen 2/2 el nivel es el valor de la onda");
        check(dut.snd_level == {dut.m254.snd_nivel, 4'b0000} && dut.snd_on, "FDS sonido: sale por audio_dac (x 16)");
        cpu_write(16'h4089, 8'h03);                 // volumen 2/5: 32 x 14 / 1152 de la onda
        ciclos(64 * 20);
        check(dut.m254.snd_nivel == (dut.m254.sonido.onda[dut.m254.sonido.o_pos] * 448) / 1152 ||
              dut.m254.snd_nivel == (dut.m254.sonido.onda[dut.m254.sonido.o_pos - 6'd1] * 448) / 1152,
              "FDS sonido: volumen 2/5");
        cpu_write(16'h4083, 8'h84);                 // onda parada: vuelve al paso 0
        ciclos(10);
        check(dut.m254.sonido.o_pos == 6'd0 && dut.m254.snd_nivel == 6'd0, "FDS sonido: $4083 D7 para la onda");
        cpu_write(16'h4023, 8'h01);                 // sonido desactivado: no se escribe
        cpu_write(16'h4080, 8'h85);
        cpu_write(16'h4023, 8'h03);
        expect_read(16'h4090, 8'h3F, 8'h20, "FDS sonido: con $4023 D1 = 0 no se escriben sus registros");
        cpu_write(16'h4083, 8'h04);                 // la onda otra vez en marcha (parada, las envolventes no avanzan)
        cpu_write(16'h4080, 8'h05);                 // envolvente que baja, velocidad 5
        ciclos(8 * 6 * 232 - 20);                   // $408A = $E8: un paso cada 8 x 6 x 232 ciclos
        expect_read(16'h4090, 8'h3F, 8'h20, "FDS sonido: la envolvente aún no ha bajado");
        ciclos(40);
        expect_read(16'h4090, 8'h3F, 8'h1F, "FDS sonido: la envolvente baja un paso");

        // ================================================= vuelta al menú
        back_to_menu;
        check(!irq_on, "OS: sin IRQ en el menu");
        expect_read(16'h4213, 8'h00, 8'h00, "OS: $4213 no conduce");
        cpu_write(16'h4C00, 8'h01);
        check(last_prg_we && last_prg_ce, "OS: $4C00 vuelve a ser la ventana del OS (escribe)");

        if (errors == 0) $display("tb_fds: todo bien");
        else $display("tb_fds: %0d FALLO(S)", errors);
        $finish;
    end
endmodule
