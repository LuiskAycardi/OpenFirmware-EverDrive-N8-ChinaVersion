// tb_mmc5.v — Testbench directo del núcleo MMC5 (mapper_mmc5.v): banca PRG (4 modos), banca CHR (tamaños), el
// multiplicador y la protección de PRG-RAM. No pasa por n8_top (la parte de PPU/ExRAM/audio va después).
// Ejecutar: iverilog -g2005 -o /tmp/tb_mmc5 hdl/sim/tb_mmc5.v hdl/rtl/mapper_mmc5.v && vvp /tmp/tb_mmc5
`timescale 1ns/1ps

module tb_mmc5;
    reg  [14:0] cpu_a = 0;
    reg  [7:0]  cpu_d = 0;
    reg         romsel_n = 1, cpu_rw = 1, m2 = 0;
    reg  [13:0] ppu_a = 0;
    reg         ppu_rd_n = 1, ppu_wr_n = 1;
    reg  [7:0]  cfg = 0;
    reg         rst = 0, clk = 0;
    wire [18:10] prg_a;
    wire        prg_rom_en, prg_ram_en, prg_wr;
    wire [18:10] chr_a;
    wire        chr_en, chr_wr, ciram_en, ciram_a10, irq, chr_raw;
    wire [7:0]  cpu_dout, cpu_doe;
    wire [9:0]  snd;

    mapper_mmc5 dut (
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(romsel_n), .cpu_rw(cpu_rw), .m2(m2),
        .ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(rst), .clk(clk),
        .map_id(8'd5), .chr_size(6'h3F),
        .prg_a(prg_a), .prg_rom_en(prg_rom_en), .prg_ram_en(prg_ram_en), .prg_wr(prg_wr),
        .chr_a(chr_a), .chr_en(chr_en), .chr_wr(chr_wr), .ciram_en(ciram_en), .ciram_a10(ciram_a10),
        .irq(irq), .chr_raw(chr_raw), .cpu_dout(cpu_dout), .cpu_doe(cpu_doe), .snd(snd));

    always #10 clk = ~clk;

    integer errors = 0;
    task check(input cond, input [8*72-1:0] msg);
        if (!cond) begin errors = errors + 1; $display("FALLO: %0s", msg); end
    endtask

    // escritura de registro ($5xxx): romsel_n=1, A14:13=10, A12=1
    task wreg(input [15:0] addr, input [7:0] d);
        begin
            m2 = 0; romsel_n = 1; cpu_rw = 0; cpu_a = addr[14:0]; cpu_d = d; #5;
            m2 = 1; #20; m2 = 0; #5; cpu_rw = 1;
        end
    endtask

    // lee la dirección de PRG de una lectura de CPU en $8000-$FFFF (romsel_n=0)
    task expect_prg(input [15:0] addr, input [18:10] want, input [8*72-1:0] msg);
        begin
            m2 = 1; romsel_n = (addr[15]==0); cpu_a = addr[14:0]; cpu_rw = 1; #5;
            check(prg_a === want && (romsel_n ? 1'b1 : (prg_rom_en||prg_ram_en)), msg);
            if (prg_a !== want) $display("   prg_a=%05h esperado %05h", {prg_a,10'd0}>>10, {want,10'd0}>>10);
            #5; m2 = 0;
        end
    endtask

    task expect_chr(input [13:0] a, input [18:10] want, input [8*72-1:0] msg);
        begin
            ppu_a = a; ppu_rd_n = 0; #5;
            check(chr_a === want, msg);
            if (chr_a !== want) $display("   chr_a=%05h esperado %05h", {chr_a,10'd0}>>10, {want,10'd0}>>10);
            #5; ppu_rd_n = 1;
        end
    endtask

    task rreg(input [15:0] addr, output [7:0] val);
        begin
            m2 = 1; romsel_n = 1; cpu_a = addr[14:0]; cpu_rw = 1; #5;
            val = cpu_dout;
            check(cpu_doe === 8'hFF, "lectura de registro debe conducir el bus");
            #5; m2 = 0;
        end
    endtask

    integer ma, mb, mode, window;
    integer expected_product;
    reg [7:0] v;
    initial begin
        rst = 1; #40; rst = 0; #20;

        // ---------------- multiplicador
        wreg(16'h5205, 8'd7); wreg(16'h5206, 8'd9);
        rreg(16'h5205, v); check(v == 8'd63, "mult 7*9 byte bajo = 63");
        rreg(16'h5206, v); check(v == 8'd0,  "mult 7*9 byte alto = 0");
        wreg(16'h5205, 8'hFF); wreg(16'h5206, 8'hFF);
        rreg(16'h5205, v); check(v == 8'h01, "mult FF*FF byte bajo = 01");
        rreg(16'h5206, v); check(v == 8'hFE, "mult FF*FF byte alto = FE");

        // ---------------- banca PRG modo 3 (4x8K)
        wreg(16'h5100, 8'd3);
        wreg(16'h5114, 8'h82);   // $8000: ROM banco 2 (bit7=1)
        wreg(16'h5115, 8'h83);   // $A000: ROM banco 3
        wreg(16'h5116, 8'h84);   // $C000: ROM banco 4
        wreg(16'h5117, 8'h87);   // $E000: ROM banco 7
        expect_prg(16'h8000, 19'h04000 >> 10, "modo3 $8000 = banco 2 (8K)");
        expect_prg(16'hA000, 19'h06000 >> 10, "modo3 $A000 = banco 3");
        expect_prg(16'hC000, 19'h08000 >> 10, "modo3 $C000 = banco 4");
        expect_prg(16'hE000, 19'h0E000 >> 10, "modo3 $E000 = banco 7");
        check(prg_rom_en, "modo3 $E000 es ROM");

        // RAM en $8000 (bit7=0)
        wreg(16'h5114, 8'h01);   // RAM banco 1
        expect_prg(16'h8000, 19'h02000 >> 10, "modo3 $8000 RAM banco 1");
        check(prg_ram_en && !prg_rom_en, "modo3 $8000 con bit7=0 es RAM");

        // ---------------- modo 0 (32K por $5117)
        wreg(16'h5100, 8'd0);
        wreg(16'h5117, 8'h84);   // 32K: bits 6:2 = banco; 0x84>>2 = 0x21 -> A15.. ; banco de 32K = 0x84[6:2]=1
        // comprobación directa del alineamiento 32K: $8000 y $E000 difieren en A14-A13
        expect_prg(16'h8000, 19'h08000 >> 10, "modo0 $8000 = inicio del banco de 32K");
        expect_prg(16'hE000, 19'h0E000 >> 10, "modo0 $E000 = fin del banco de 32K");

        // ---------------- modo 2 (16K + 8K + 8K)
        wreg(16'h5100, 8'd2);
        wreg(16'h5115, 8'h82);   // $8000-$BFFF 16K: banco 2 (16K) -> páginas 8K 2 y 3
        wreg(16'h5116, 8'h85);   // $C000 8K
        wreg(16'h5117, 8'h87);   // $E000 8K
        expect_prg(16'h8000, 19'h04000 >> 10, "modo2 $8000 (16K) pág baja");
        expect_prg(16'hA000, 19'h06000 >> 10, "modo2 $A000 (16K) pág alta");
        expect_prg(16'hC000, 19'h0A000 >> 10, "modo2 $C000 (8K) = banco 5");
        expect_prg(16'hE000, 19'h0E000 >> 10, "modo2 $E000 (8K) = banco 7");

        // ---------------- $6000 siempre RAM por $5113
        wreg(16'h5113, 8'd3);
        expect_prg(16'h6000, 19'h06000 >> 10, "$6000 = RAM banco 3 ($5113)");
        check(prg_ram_en, "$6000 habilita RAM");

        wreg(16'h5113,8'hfb);
        expect_prg(16'h6000,9'd24,"WRAM ignores bits7:3, preserving OS-reserved SRAM");
        // ---------------- protección de PRG-RAM
        wreg(16'h5102, 8'd2); wreg(16'h5103, 8'd1);   // desbloqueada
        m2=1; romsel_n=1; cpu_a=15'h6000; cpu_rw=0; #5;
        check(prg_wr, "RAM escribible con 5102=2 y 5103=1"); #5; m2=0; cpu_rw=1;
        wreg(16'h5102, 8'd0);                          // bloqueada
        m2=1; romsel_n=1; cpu_a=15'h6000; cpu_rw=0; #5;
        check(!prg_wr, "RAM protegida con 5102!=2"); #5; m2=0; cpu_rw=1;

        // ---------------- banca CHR (8x8, juego A)
        wreg(16'h5101, 8'd3);    // 1K
        wreg(16'h5120, 8'h10); wreg(16'h5121, 8'h11); wreg(16'h5127, 8'h17);
        wreg(16'h5130, 8'd0);
        expect_chr(14'h0000, 19'h04000 >> 10, "CHR 1K $0000 = banco $10");
        expect_chr(14'h0400, 19'h04400 >> 10, "CHR 1K $0400 = banco $11");
        expect_chr(14'h1C00, 19'h05C00 >> 10, "CHR 1K $1C00 = banco $17");
        wreg(16'h5101, 8'd0);    // 8K por $5127
        wreg(16'h5127, 8'h02);
        expect_chr(14'h0000, 19'h04000 >> 10, "CHR 8K $0000");
        expect_chr(14'h1FFF, (19'h05FFF) >> 10, "CHR 8K $1FFF (misma pág de 8K)");

        // Mode 1 has two independently selected, aligned 16 KB PRG windows.
        wreg(16'h5100, 8'd1);
        wreg(16'h5115, 8'h87); wreg(16'h5117, 8'h8B);
        expect_prg(16'h8000, 9'd48, "PRG mode1 lower alignment");
        expect_prg(16'hA000, 9'd56, "PRG mode1 lower second half");
        expect_prg(16'hC000, 9'd80, "PRG mode1 upper alignment");
        expect_prg(16'hE000, 9'd88, "PRG mode1 upper second half");

        // Check every protection-key combination; exactly 2/1 permits writes.
        for (ma=0; ma<4; ma=ma+1) for (mb=0; mb<4; mb=mb+1) begin
            wreg(16'h5102, ma); wreg(16'h5103, mb);
            m2=1; romsel_n=1; cpu_a=15'h6000; cpu_rw=0; #5;
            check(prg_wr === ((ma==2)&&(mb==1)), "RAM protection key combination");
            #5; m2=0; cpu_rw=1;
        end

        // All 8 PPU windows in each CHR size; chosen banks keep low-bit errors visible.
        for (ma=0; ma<8; ma=ma+1) wreg(16'h5120+ma, ma+3);
        for (mode=0; mode<4; mode=mode+1) begin
            wreg(16'h5101,mode);
            for (window=0; window<8; window=window+1) begin
                case(mode)
                    0: expected_product = 10*8+window;
                    1: expected_product = ((window<4)?6:10)*4+(window%4);
                    2: expected_product = (4+2*(window/2))*2+(window%2);
                    3: expected_product = window+3;
                endcase
                expect_chr(window*1024, expected_product, "CHR size/window table");
            end
        end

        // Exhaustive multiplication, both result bytes, through CPU read decoding.
        for (ma=0; ma<256; ma=ma+1) begin
            wreg(16'h5205, ma);
            for (mb=0; mb<256; mb=mb+1) begin
                wreg(16'h5206, mb); expected_product=ma*mb;
                rreg(16'h5205,v); check(v === (expected_product & 255), "product low exhaustive");
                rreg(16'h5206,v); check(v === ((expected_product>>8) & 255), "product high exhaustive");
            end
        end

        if (errors == 0) $display("OK: todas las pruebas pasaron (MMC5 núcleo)");
        else             $fatal(1, "FALLARON %0d comprobaciones (MMC5)", errors);
        $finish;
    end
endmodule
