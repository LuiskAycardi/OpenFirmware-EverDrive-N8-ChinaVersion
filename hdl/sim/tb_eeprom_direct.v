`timescale 1ns/1ps
// Direct test of the Bandai serial EEPROM through mapper_bandaifcg.v:
// mapper 16 = 24C02 (256 bytes, I2C chip address), mapper 159 = 24C01 (128 bytes, no chip address),
// 153 (SRAM + outer PRG bit) and 157 (Datach: base 24C02 + the cartridge 24C01 of Battle Rush, whose SCL
// is bit 3 of the $8000-$8003 writes; the read is the AND of both outputs).
// SCL/SDA are written to $800D (D5/D6); the EEPROM output is read at $6000 (D4). Standalone.
module tb_eeprom_direct;
    reg [14:0] cpu_a = 0;
    reg [7:0]  cpu_d = 0, cfg = 8'h01, map_id = 16;
    reg romsel_n = 1, cpu_rw = 1, m2 = 0, rst = 0, clk = 0;
    reg [13:0] ppu_a = 0;
    reg ppu_rd_n = 1, ppu_wr_n = 1;
    wire [5:0] chr_size = 6'h3f;
    wire [18:10] prg_a, chr_a;
    wire prg_rom_en, prg_ram_en, prg_wr, chr_en, chr_wr, ciram_en, ciram_a10, irq;
    wire [7:0] cpu_dout, cpu_doe;
    mapper_bandaifcg dut(.*);
    always #10 clk = ~clk;

    integer checks = 0, i, j;
    reg [7:0] v;
    task check(input ok, input [640:0] msg);
        begin checks = checks + 1; if (!ok) $fatal(1, "EEPROM %0d: %0s", map_id, msg); end
    endtask
    task cycle; begin #100; m2 = 1; #500; m2 = 0; #400; end endtask
    task wr(input [15:0] a, input [7:0] d);
        begin cpu_a = a[14:0]; romsel_n = !a[15]; cpu_d = d; cpu_rw = 0; cycle; cpu_rw = 1; #100; end
    endtask
    reg sda_now = 1, xmode = 0;
    // xmode (157 cartridge 24C01): SDA = $800D D6 (D5 = 0 keeps the base 24C02 still), SCL = $8000 D3;
    // the SCL edge is written last when it rises and first when it falls, so SDA never moves under SCL high
    task bus(input scl, input sda);
        begin
            sda_now = sda;
            if (!xmode) wr(16'h800D, {1'b0, sda, scl, 5'd0});
            else if (scl) begin wr(16'h800D, {1'b0, sda, 6'd0}); wr(16'h8000, {4'd0, scl, 3'd0}); end
            else begin wr(16'h8000, {4'd0, scl, 3'd0}); wr(16'h800D, {1'b0, sda, 6'd0}); end
        end
    endtask
    // read the EEPROM output bit at $6000
    task rdbit(output b);
        begin cpu_a = 15'h6000; romsel_n = 1; cpu_rw = 1; #100; m2 = 1; #200;
              check(cpu_doe == 8'h18, "$6000 drives only D4/D3");
              check(cpu_dout[3] == 1'b0, "D3 reads 0");
              b = cpu_dout[4]; m2 = 0; #300; end
    endtask
    task i2c_start; begin bus(1, 1); bus(1, 0); bus(0, 0); end endtask
    task i2c_stop;  begin bus(0, 0); bus(1, 0); bus(1, 1); end endtask
    task sbit(input b); begin bus(0, b); bus(1, b); bus(0, b); end endtask
    // 9th clock: device ACK expected as 0 while SCL is high
    task ack_dev(input expect_ack);
        reg b;
        begin bus(0, 1); bus(1, 1); rdbit(b);
              check(b == !expect_ack, expect_ack ? "device ACK" : "no ACK (not selected)");
              bus(0, 1); end
    endtask
    task sbyte_msb(input [7:0] d); begin for (j = 7; j >= 0; j = j - 1) sbit(d[j]); end endtask
    task sbyte_lsb(input [7:0] d); begin for (j = 0; j < 8; j = j + 1) sbit(d[j]); end endtask
    task rbyte_msb(output [7:0] d);
        reg b;
        begin for (j = 7; j >= 0; j = j - 1) begin bus(0, 1); bus(1, 1); rdbit(b); d[j] = b; end bus(0, 1); end
    endtask
    task rbyte_lsb(output [7:0] d);
        reg b;
        begin for (j = 0; j < 8; j = j + 1) begin bus(0, 1); bus(1, 1); rdbit(b); d[j] = b; end bus(0, 1); end
    endtask
    task mack(input a); begin bus(0, !a); bus(1, !a); bus(0, !a); end endtask   // master ACK/NACK

    // 24C02 helpers
    task c02_write(input [7:0] a, input [7:0] d);
        begin i2c_start; sbyte_msb(8'hA0); ack_dev(1); sbyte_msb(a); ack_dev(1);
              sbyte_msb(d); ack_dev(1); i2c_stop; end
    endtask
    task c02_read(input [7:0] a, output [7:0] d);
        begin i2c_start; sbyte_msb(8'hA0); ack_dev(1); sbyte_msb(a); ack_dev(1);
              i2c_start; sbyte_msb(8'hA1); ack_dev(1); rbyte_msb(d); mack(0); i2c_stop; end
    endtask
    // 24C01 helpers: 7 address bits + R/W, LSB first
    task c01_write(input [6:0] a, input [7:0] d);
        begin i2c_start; sbyte_lsb({1'b0, a}); ack_dev(1); sbyte_lsb(d); ack_dev(1); i2c_stop; end
    endtask
    task c01_read(input [6:0] a, output [7:0] d);
        begin i2c_start; sbyte_lsb({1'b1, a}); ack_dev(1); rbyte_lsb(d); mack(0); i2c_stop; end
    endtask

    reg b;
    initial begin
        rst = 1; repeat (3) cycle; rst = 0; cycle;

        // ---------------------------------------------------------------- 24C02 (mapper 16)
        rdbit(b); check(b == 0, "output 0 before the first START");
        c02_read(8'h10, v); check(v == 8'h00, "erased (zero) at power-on");
        c02_write(8'h10, 8'hA6); c02_read(8'h10, v); check(v == 8'hA6, "byte write / random read");
        c02_write(8'hFF, 8'h3D); c02_read(8'hFF, v); check(v == 8'h3D, "last byte");
        // sequential write then sequential read with master ACKs
        i2c_start; sbyte_msb(8'hA0); ack_dev(1); sbyte_msb(8'h40); ack_dev(1);
        for (i = 0; i < 5; i = i + 1) begin sbyte_msb(8'h11 * (i + 1)); ack_dev(1); end
        i2c_stop;
        i2c_start; sbyte_msb(8'hA0); ack_dev(1); sbyte_msb(8'h40); ack_dev(1);
        i2c_start; sbyte_msb(8'hA1); ack_dev(1);
        for (i = 0; i < 5; i = i + 1) begin
            rbyte_msb(v); check(v == 8'h11 * (i + 1), "sequential read");
            mack(i != 4);
        end
        i2c_stop;
        // current-address read continues after the last address read (0x45)
        c02_write(8'h45, 8'h71);
        c02_read(8'h44, v);                                 // leaves the address at $45
        i2c_start; sbyte_msb(8'hA1); ack_dev(1); rbyte_msb(v); mack(0); i2c_stop;
        check(v == 8'h71, "current address read");
        // a chip address without bits 7/5 set is not acknowledged and changes nothing
        i2c_start; sbyte_msb(8'h50); ack_dev(0); i2c_stop;
        c02_read(8'h10, v); check(v == 8'hA6, "data kept after unselected access");
        // $600D belongs to the FCG-1/2 range, whose boards have no EEPROM: with the output at 0
        // (ACK clock high) a START pattern written there must leave it at 0; via $800D it raises it.
        i2c_start; sbyte_msb(8'hA0); bus(0, 1); bus(1, 1); rdbit(b); check(b == 0, "ACK drives 0");
        wr(16'h600D, 8'h20); rdbit(b); check(b == 0, "$600D does not reach the EEPROM");
        bus(1, 0); rdbit(b); check(b == 1, "START through $800D");
        i2c_stop;
        // IRQ by range: $600B/$600C load the counter directly (FCG-1/2), $600A does not reload;
        // $800B/$800C load the latch that $800A copies (LZ93D50).
        wr(16'h800A, 8'h00); wr(16'h800B, 8'h05); wr(16'h800C, 8'h00);   // latch = 5
        wr(16'h600B, 8'h02); wr(16'h600C, 8'h00);                        // counter = 2
        wr(16'h600A, 8'h01);                                             // enable, keep 2
        check(!irq, "FCG: not yet"); cycle; check(!irq, "FCG: 1 left"); cycle; check(irq, "FCG: fires from the direct count");
        wr(16'h800A, 8'h01);                                             // ack + copy latch 5
        check(!irq, "LZ: acknowledged"); repeat (4) cycle; check(!irq, "LZ: counting the latch");
        cycle; check(irq, "LZ: fires from the latch");
        wr(16'h800A, 8'h00);
        // contents survive the mapper reset (only the protocol state is reset)
        rst = 1; cycle; rst = 0; cycle;
        rdbit(b); check(b == 0, "output 0 after reset");
        c02_read(8'h10, v); check(v == 8'hA6, "contents kept across reset");

        // ---------------------------------------------------------------- 24C01 (mapper 159)
        map_id = 159; rst = 1; cycle; rst = 0; cycle;
        c01_write(7'h05, 8'h1E); c01_read(7'h05, v); check(v == 8'h1E, "24C01 write/read");
        c01_write(7'h7F, 8'h9C); c01_read(7'h7F, v); check(v == 8'h9C, "24C01 last byte");
        c01_read(7'h06, v); check(v == 8'h00, "24C01 neighbour untouched");
        // a read leaves the chip waiting for STOP/START: further clocks return nothing new
        i2c_start; sbyte_lsb({1'b1, 7'h05}); ack_dev(1); rbyte_lsb(v); check(v == 8'h1E, "24C01 read");
        // after the byte the chip waits for STOP/START; the output holds the last bit ($1E.7 = 0)
        mack(1); rbyte_lsb(v); check(v == 8'h00, "24C01 has no sequential read");
        i2c_stop;
        // $6000 writes are not registers on mapper 159: with the output at 0 (ACK clock high),
        // a START pattern written to $600D must leave it at 0
        i2c_start; sbyte_lsb({1'b0, 7'h00}); bus(0, 1); bus(1, 1); rdbit(b); check(b == 0, "24C01 ACK drives 0");
        wr(16'h600D, 8'h20); rdbit(b); check(b == 0, "$600D is not a register on 159");
        i2c_stop;
        c01_read(7'h05, v); check(v == 8'h1E, "24C01 unaffected by $600D");

        // ---------------------------------------------------------------- mapper 153
        // SRAM at $6000 (on at power-on, $800D D5), registers only at $8000+, PRG outer bit =
        // OR of the CHR registers' bit 0, linear CHR-RAM, no EEPROM drive on $6000.
        map_id = 153; cfg = 8'h81; rst = 1; cycle; rst = 0; cycle;
        cpu_a = 15'h6000; romsel_n = 1; cpu_rw = 0; #100; m2 = 1; #100;
        check(prg_ram_en && prg_wr && prg_a == 9'd0, "153 SRAM writable at power-on"); m2 = 0; cpu_rw = 1; #100;
        cpu_rw = 1; m2 = 1; #100; check(prg_ram_en && cpu_doe == 0, "153 SRAM read, no EEPROM drive"); m2 = 0; #100;
        wr(16'h800D, 8'h00);
        m2 = 1; cpu_a = 15'h6000; romsel_n = 1; #100; check(!prg_ram_en, "153 SRAM disabled by $800D"); m2 = 0; #100;
        wr(16'h600D, 8'h20);                                       // $6000 is RAM, not a register
        m2 = 1; cpu_a = 15'h6000; romsel_n = 1; #100; check(!prg_ram_en, "153 $600D is not a register"); m2 = 0; #100;
        wr(16'h800D, 8'h20);
        m2 = 1; cpu_a = 15'h7c00; romsel_n = 1; #100; check(prg_ram_en && prg_a == 9'd7, "153 SRAM re-enabled"); m2 = 0; #100;
        wr(16'h8008, 8'h03);
        cpu_a = 15'h0000; romsel_n = 0; #100; check(prg_a == {5'd3, 4'd0}, "153 PRG inner bank");
        cpu_a = 15'h4000; #100; check(prg_a == {5'd15, 4'd0}, "153 fixed last bank (inner)");
        wr(16'h8005, 8'h01);                                       // any CHR register bit 0 -> outer
        cpu_a = 15'h0000; romsel_n = 0; #100; check(prg_a == {5'd19, 4'd0}, "153 PRG outer bit");
        cpu_a = 15'h4000; #100; check(prg_a == {5'd31, 4'd0}, "153 last bank of the outer half");
        wr(16'h8005, 8'h00); cpu_a = 15'h0000; romsel_n = 0; #100; check(prg_a == {5'd3, 4'd0}, "153 outer cleared");
        wr(16'h8002, 8'h05); ppu_a = 14'h0800; #100; check(chr_a == 9'd2, "153 CHR-RAM is not banked");
        ppu_wr_n = 0; #100; check(chr_wr, "153 CHR-RAM writable"); ppu_wr_n = 1;
        // ---------------------------------------------------------------- mapper 157 (Datach)
        map_id = 157; cfg = 8'h81; rst = 1; cycle; rst = 0; cycle;
        c02_read(8'h10, v); check(v == 8'hA6, "157 base 24C02 (shared chip, data kept)");
        c02_write(8'h20, 8'h5B); c02_read(8'h20, v); check(v == 8'h5B, "157 base 24C02 write/read");
        wr(16'h8008, 8'h02); wr(16'h6008, 8'h07);
        cpu_a = 15'h0000; romsel_n = 0; #100; check(prg_a == {5'd2, 4'd0}, "157 $6008 is not a register");
        cpu_a = 15'h4000; #100; check(prg_a == {5'd15, 4'd0}, "157 fixed last bank");
        wr(16'h8002, 8'h05); ppu_a = 14'h0800; #100; check(chr_a == 9'd2, "157 CHR-RAM is not banked");
        ppu_wr_n = 0; #100; check(chr_wr, "157 CHR-RAM writable"); ppu_wr_n = 1;
        // without the battery bit there is no cartridge 24C01: nothing answers on the $8000 D3 bus
        xmode = 1; i2c_start; sbyte_lsb({1'b0, 7'h12}); ack_dev(0); i2c_stop; xmode = 0;
        // Battle Rush (battery): the cartridge 24C01 answers and its output is ANDed into D4
        cfg = 8'h83; rst = 1; cycle; rst = 0; cycle;
        // like the 24C02 (and the bench oracle) the cartridge chip outputs 0 until its first START/STOP,
        // and the AND hides the base chip until then
        rdbit(b); check(b == 0, "157 D4 = 0 before the cartridge chip's first START");
        xmode = 1; i2c_start; i2c_stop; xmode = 0;
        c02_read(8'h20, v); check(v == 8'h5B, "157 base 24C02 with the cartridge chip present");
        xmode = 1;
        c01_write(7'h12, 8'hC5); c01_read(7'h12, v); check(v == 8'hC5, "157 cartridge 24C01 write/read");
        c01_write(7'h7E, 8'h3A); c01_read(7'h7E, v); check(v == 8'h3A, "157 cartridge 24C01 last bytes");
        // only $8000-$8003 carry the cartridge SCL: a D3 pulse on $8004 mid-transfer is not a clock
        i2c_start; sbyte_lsb({1'b0, 7'h33}); ack_dev(1); wr(16'h8004, 8'h08); wr(16'h8004, 8'h00);
        sbyte_lsb(8'h96); ack_dev(1); i2c_stop;
        c01_read(7'h33, v); check(v == 8'h96, "157 $8004-$8007 do not clock the cartridge chip");
        xmode = 0;
        c02_read(8'h20, v); check(v == 8'h5B, "157 base 24C02 unaffected by the cartridge chip");
        xmode = 1; c01_read(7'h12, v); check(v == 8'hC5, "157 cartridge 24C01 unaffected by the base chip");
        // AND: the base chip at 1 (idle after STOP) and the cartridge chip driving its ACK 0 read as 0
        i2c_start; sbyte_lsb({1'b1, 7'h12}); bus(0, 1); bus(1, 1); rdbit(b); check(b == 0, "157 D4 = AND (cartridge ACK)");
        bus(0, 1); rbyte_lsb(v); mack(0); i2c_stop; xmode = 0;
        cfg = 8'h01;

        $display("PASS tb_eeprom_direct: %0d checks", checks); $finish;
    end
    initial begin #400000000; $fatal(1, "watchdog"); end
endmodule
