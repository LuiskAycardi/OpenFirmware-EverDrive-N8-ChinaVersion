// tb_bus.vh — Parte común de los testbenches: DUT, señales y tareas de bus.
// Se incluye dentro del módulo del testbench.

    // reloj del sistema: frecuencia real desconocida, se asume 50 MHz
    reg clk = 0;
    always #10 clk = ~clk;

    // bus CPU
    reg  [14:0] cpu_a = 0;
    reg  [7:0]  cpu_dout = 0;
    reg         cpu_drive = 0;
    reg         romsel_n = 1, cpu_rw = 1, m2 = 0;
    wire [7:0]  cpu_d = cpu_drive ? cpu_dout : 8'hzz;
    wire        irq_n, exp;

    // bus PPU
    reg  [13:0] ppu_a = 0;
    reg         ppu_rd_n = 1, ppu_wr_n = 1;
    wire [7:0]  ppu_d;
    wire        ciram_ce_n, ciram_a10, ppu_dir, ppu_ex;

    wire [8:0] prg_map, chr_map;
    wire prg_ce_n, prg_oe_n, prg_we_n, chr_ce_n, chr_oe_n, chr_we_n;
    wire ram_ce, ram_oe_n, ram_we_n, mode0, mode1;
    reg  bios_off = 1;

    pullup(irq_n);

    n8_top dut (
        .cpu_d(cpu_d), .cpu_a(cpu_a), .cpu_romsel_n(romsel_n), .cpu_rw(cpu_rw),
        .cpu_m2(m2), .cpu_m2_gclk(m2), .cpu_irq_n(irq_n), .cpu_exp(exp),
        .ppu_d(ppu_d), .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n),
        .ciram_ce_n(ciram_ce_n), .ciram_a10(ciram_a10), .ppu_dir(ppu_dir), .ppu_ex(ppu_ex),
        .prg_map(prg_map), .prg_ce_n(prg_ce_n), .prg_oe_n(prg_oe_n), .prg_we_n(prg_we_n),
        .chr_map(chr_map), .chr_ce_n(chr_ce_n), .chr_oe_n(chr_oe_n), .chr_we_n(chr_we_n),
        .ram_ce(ram_ce), .ram_oe_n(ram_oe_n), .ram_we_n(ram_we_n),
        .clk(clk), .cpld_bios_off(bios_off), .cpld_mode0(mode0), .cpld_mode1(mode1)
    );

    integer errors = 0;
    task check(input cond, input [8*64-1:0] msg);
        if (!cond) begin
            errors = errors + 1;
            $display("FALLO @%0t: %0s", $time, msg);
        end
    endtask

    // ------------------------------------------------------------------ ciclo de CPU
    // M2 ~1.79 MHz: 280 ns bajo, 280 ns alto. /ROMSEL = !(A15 & M2) sale del decodificador 74139 de la
    // consola: baja ~25 ns después de que sube M2 y sube ~15 ns después de que baja; el testbench lo
    // reproduce (fase 3d: durante esos 25 ns una lectura de ROM parece de $4000-$7FFF).
    // Las comprobaciones se hacen al final de la fase alta, cuando la CPU captura el dato.
    reg [18:0] last_prg_addr;   // dirección completa vista por la SRAM (A18..A10 + A9..A0)
    reg        last_prg_ce, last_ram_ce, last_prg_we, last_ram_we;
    reg [7:0]  last_cpu_d;     // lo que hay en el bus de datos al final de la fase alta (lecturas: la FPGA)
    reg        cur_a15 = 1'b0;  // A15 del ciclo en curso (la FPGA no la ve: solo /ROMSEL)

    task cpu_cycle(input [15:0] addr, input rw, input [7:0] data);
        begin
            m2 = 0;
            cpu_a = addr[14:0];
            cur_a15 = addr[15];
            cpu_rw = rw;
            cpu_drive = !rw;
            cpu_dout = data;
            #280;
            m2 = 1;
            #25;
            romsel_n = !addr[15];
            #225;
            last_prg_addr = {prg_map, addr[9:0]};
            last_cpu_d = cpu_d;
            if (!rw && (^cpu_d === 1'bx)) check(1'b0, "BUS: choque en una escritura (la FPGA conduce)");
            last_prg_ce = !prg_ce_n;
            last_ram_ce = ram_ce;
            last_prg_we = !prg_we_n;
            last_ram_we = !ram_we_n;
            #30;
            m2 = 0;
            #15;
            romsel_n = 1;
            #5;
            cpu_drive = 0;
            cpu_rw = 1;
        end
    endtask

    task cpu_write(input [15:0] addr, input [7:0] data); cpu_cycle(addr, 0, data); endtask

    // ------------------------------------------------------------------ seguridad del bus (fase 3d)
    // La FPGA solo puede conducir el bus de datos de la CPU en una lectura, con M2 alto, fuera de la ROM
    // y con las SRAM sin sacar datos; y tiene que soltarlo al bajar M2. Vale para todos los testbenches.
    always @(cpu_d) if (!cpu_drive && (cpu_d !== 8'hzz) &&
                        !(m2 === 1'b1 && cpu_rw === 1'b1 && romsel_n === 1'b1 && !cur_a15 &&
                          prg_oe_n === 1'b1 && ram_oe_n === 1'b1))
        check(1'b0, "BUS: la FPGA conduce fuera de una lectura de registro");
    always @(negedge m2) begin
        #2;
        if (!cpu_drive && (cpu_d !== 8'hzz)) check(1'b0, "BUS: la FPGA no suelta el bus al bajar M2");
    end

    // Lectura de un registro: comprueba los bits que conduce la FPGA (máscara) y que el resto queda en Z.
    task expect_read(input [15:0] addr, input [7:0] mask, input [7:0] want, input [8*64-1:0] msg);
        integer b; reg ok;
        begin
            cpu_read(addr);
            ok = 1'b1;
            for (b = 0; b < 8; b = b + 1)
                if (mask[b] ? (last_cpu_d[b] !== want[b]) : (last_cpu_d[b] !== 1'bz)) ok = 1'b0;
            check(ok, msg);
            if (!ok) $display("      bus %b, esperado %b (mascara %b)", last_cpu_d, want, mask);
        end
    endtask
    task cpu_read (input [15:0] addr);                   cpu_cycle(addr, 1, 8'h00); endtask

    task os_reg(input [7:0] r, input [7:0] v);
        begin cpu_write(16'h4400, r); cpu_write(16'h4401, v); end
    endtask

    // Configura y arranca un juego como lo haría el OS (OS v13, rutina en $BB7E):
    //   prg_mask = bancos de 16 KB - 1 (A18..A14)
    //   chr      = bancos de 8 KB - 1 (A18..A13); con CHR-RAM el OS envía $FF
    //              (bit 7 = CHR-RAM y máscara abierta del todo).
    localparam CHR_RAM = 8'hFF;
    task start_game(input [7:0] mapper, input [4:0] prg_mask, input [7:0] chr, input [7:0] cfg_v);
        begin
            os_reg(8'd132, {3'd0, prg_mask});
            os_reg(8'd133, chr);
            os_reg(8'd134, cfg_v);
            os_reg(8'd136, 8'd0);
            os_reg(8'd131, mapper);
            cpu_read(16'h0000);
        end
    endtask

    // Vuelve al menú simulando RESET (M2 parado).
    task back_to_menu;
        begin
            m2 = 0;
            #(20 * 200);
            repeat (2) cpu_read(16'h0000);
        end
    endtask

    // ------------------------------------------------------------------ PPU
    task ppu_access(input [13:0] addr, input wr);
        begin
            ppu_a = addr;
            ppu_rd_n = wr;
            ppu_wr_n = !wr;
            #50;
        end
    endtask

    // Dirección CHR completa (A18..A0) que ve la SRAM en el acceso actual.
    wire [18:0] chr_addr_now = {chr_map, ppu_a[9:0]};

    // ------------------------------------------------------------------ comprobaciones
    task expect_prg(input [15:0] addr, input [18:0] want, input [8*64-1:0] msg);
        begin
            cpu_read(addr);
            check(last_prg_ce && last_prg_addr == want, msg);
            if (!(last_prg_ce && last_prg_addr == want))
                $display("      leido 0x%05h, esperado 0x%05h", last_prg_addr, want);
        end
    endtask

    task expect_chr(input [13:0] addr, input [18:0] want, input [8*64-1:0] msg);
        begin
            ppu_access(addr, 0);
            check(!chr_ce_n && chr_addr_now == want, msg);
            if (!(!chr_ce_n && chr_addr_now == want))
                $display("      CHR 0x%05h, esperado 0x%05h", chr_addr_now, want);
        end
    endtask

    task expect_a10(input [13:0] addr, input want, input [8*64-1:0] msg);
        begin
            ppu_access(addr, 0);
            check(!ciram_ce_n && ciram_a10 == want, msg);
        end
    endtask
