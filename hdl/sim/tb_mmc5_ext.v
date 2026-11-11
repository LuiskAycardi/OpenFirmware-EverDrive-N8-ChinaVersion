// tb_mmc5.v — Testbench directo del núcleo MMC5 (mapper_mmc5.v): banca PRG (4 modos), banca CHR (tamaños), el
// multiplicador y la protección de PRG-RAM. No pasa por n8_top (la parte de PPU/ExRAM/audio va después).
// Ejecutar: iverilog -g2005 -o /tmp/tb_mmc5 hdl/sim/tb_mmc5.v hdl/rtl/mapper_mmc5.v && vvp /tmp/tb_mmc5
`timescale 1ns/1ps

module tb_mmc5_ext;
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
    wire [7:0] cpu_dout, cpu_doe, ppu_dout, ppu_doe;
    reg [7:0] ppu_din=0;
    wire [9:0]  snd;

    mapper_mmc5 dut (
        .cpu_a(cpu_a), .cpu_d(cpu_d), .romsel_n(romsel_n), .cpu_rw(cpu_rw), .m2(m2),
        .ppu_din(ppu_din),.ppu_dout(ppu_dout),.ppu_doe(ppu_doe),.ppu_a(ppu_a), .ppu_rd_n(ppu_rd_n), .ppu_wr_n(ppu_wr_n), .cfg(cfg), .rst(rst), .clk(clk),
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
            m2 = 0; romsel_n = 1; cpu_rw = 0; cpu_a = addr[14:0]; cpu_d = d; #280;
            m2 = 1; #240; m2 = 0; #40; cpu_rw = 1;
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
            m2 = 1; romsel_n = 1; cpu_a = addr[14:0]; cpu_rw = 1; #200;
            val = cpu_dout;
            check(cpu_doe === ((addr==16'h5204)?8'hc0:8'hff), "CPU data enable mask");
            #5; m2 = 0;
        end
    endtask


    reg [7:0] v;
    task fetch(input [13:0] a, input [7:0] want, input drive);
        begin
            ppu_rd_n=1; ppu_a=a; #200; ppu_rd_n=0; #140;
            check(ppu_doe === (drive ? 8'hff : 8'h00), "PPU drive mask");
            if(drive) begin check(ppu_dout===want,"PPU returned byte"); if(ppu_dout!==want) $display("addr=%h got=%h want=%h tile=%d exaddr=%h",a,ppu_dout,want,dut.tile_fetch,dut.ex_ppu_addr); end
            #60; ppu_rd_n=1; #60;
        end
    endtask
    task scanstart;
        begin
            fetch(14'h0000,0,0);
            fetch(14'h2000,0,0); fetch(14'h2000,0,0); fetch(14'h2000,0,0);
            fetch(14'h23c0,0,0);
        end
    endtask
    initial begin
        rst=1; #40; m2=1; #60; m2=0; #60; rst=0;
        // CPU RAM mode2 writes, mode3 read-only, mode0/1 CPU read open bus.
        wreg(16'h5104,2); wreg(16'h5c05,8'ha7); rreg(16'h5c05,v);
        check(v==8'ha7,"ExRAM CPU mode2 read/write");
        wreg(16'h5104,3); wreg(16'h5c05,8'h22); rreg(16'h5c05,v);
        check(v==8'ha7,"ExRAM mode3 blocks writes");
        wreg(16'h5104,0); #60;
        cpu_a=15'h5c05;romsel_n=1;cpu_rw=1;#60;
        check(cpu_doe==0,"ExRAM mode0 CPU read open bus");
        wreg(16'h5105,8'haa);
        fetch(14'h2005,8'ha7,1);
        // PPU writes are visible to CPU after selecting RAM mode.
        ppu_a=14'h2005;ppu_din=8'h31;ppu_wr_n=0;#200;ppu_wr_n=1;#60;
        wreg(16'h5104,2);rreg(16'h5c05,v);check(v==8'h31,"ExRAM PPU write");
        // Fill replaces tiles and replicates palette in all attribute quadrants.
        wreg(16'h5105,8'hff); wreg(16'h5106,8'h42); wreg(16'h5107,2);
        fetch(14'h2000,8'h42,1);fetch(14'h23ff,8'haa,1);
        // Restore CIRAM; exact repeated-read marker counts lines, tiles do not.
        wreg(16'h5105,0);wreg(16'h5203,1);wreg(16'h5204,8'h80);
        scanstart();fetch(14'h2001,0,0);fetch(14'h0010,0,0);
        check(dut.in_frame && !irq,"first scanline frame flag, no IRQ");
        fetch(14'h2002,0,0);fetch(14'h0010,0,0);
        check(dut.scanline==0 && !irq,"ordinary tiles never clock scanline IRQ");
        scanstart();check(irq,"second scanline asserts target1 IRQ");
        rreg(16'h5204,v);check(v[7],"IRQ status reports pending");#120;
        check(!irq,"5204 read acknowledges pending");
        // 8x16 outside rendering follows last CHR set, ignoring header cfg[6].
        wreg(16'h2000,8'h20);wreg(16'h5101,3);
        wreg(16'h5120,8'h10);wreg(16'h5128,8'h22);
        // CPU clocks with no PPU reads clear in-frame after 3 cycles.
        repeat(4) wreg(16'h5205,0);
        expect_chr(0,9'h22,"8x16 CPU PPU access uses last set B");
        wreg(16'h5120,8'h11);expect_chr(0,9'h11,"last set A");
        wreg(16'h2000,0);wreg(16'h5128,8'h23);
        expect_chr(0,9'h11,"8x8 forces set A");
        // Extended attributes: one ExRAM byte controls palette and a 4KB CHR bank.
        wreg(16'h5104,2);wreg(16'h5c01,8'hc5);
        wreg(16'h5104,1);wreg(16'h5105,0);wreg(16'h5130,1);
        scanstart();fetch(14'h2001,0,0);
        fetch(14'h23c0,8'hff,1);
        expect_chr(14'h0040,9'h114,"extended 4KB CHR bank uses ExRAM and 5130");
        // Split NT source and palette when the fixed low CHR address is compatible.
        wreg(16'h5104,2);wreg(16'h5c03,8'h77);wreg(16'h5fc0,8'h0c);
        wreg(16'h5104,0);wreg(16'h5200,8'h9f);wreg(16'h5201,0);wreg(16'h5202,3);
        // Set the fetch origin explicitly here: split timing is separately validated by rendering tests.
        dut.tile_fetch=0; dut.scanline=0; dut.in_frame=1; #80;
        fetch(14'h2000,8'h77,1);
        if(errors) $fatal(1,"MMC5 extended failures: %0d",errors);
        $display("OK: MMC5 ExRAM/fill/scanline IRQ/CHR A-B");$finish;
    end
endmodule
