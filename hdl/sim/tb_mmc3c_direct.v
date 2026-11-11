`timescale 1ns/1ps
// Direct test of mapper_mmc3c (MMC3 GRUPO 2): 165, 219 and the legacy 248 alias.
// Standalone, no top/SD/cartridge dependencies (also built by `make -C hdl sim`).
// 176 is the FK23C and is tested in tb_fk23c_direct.v. 219 follows the A9461 register
// scheme validated against Mesen2 (er0/er1/er2 indirection through $8000/$8002/$8001).
module tb_mmc3c_direct;
    reg [14:0] cpu_a=0;
    reg [7:0] cpu_d=0, cfg=1, map_id=165;
    reg romsel_n=1, cpu_rw=1, m2=0, rst=0, clk=0;
    reg [13:0] ppu_a=0;
    reg ppu_rd_n=1, ppu_wr_n=1;
    wire [5:0] chr_size=6'h3f;
    wire [18:10] prg_a, chr_a;
    wire prg_rom_en, prg_ram_en, prg_wr, chr_en, chr_wr;
    wire ciram_en, ciram_a10, irq, chr_raw;
    wire [7:0] cpu_dout,cpu_doe;
    mapper_mmc3c dut(.*);
    // Same pins into groups 0/1: group 2 IDs must not enable new banking.
    wire [18:10] p0,p1,c0,c1;
    mapper_mmc3 #(.GRUPO(0)) old0(
        .cpu_a(cpu_a),.cpu_d(cpu_d),.cfg(cfg),.map_id(map_id),
        .romsel_n(romsel_n),.cpu_rw(cpu_rw),.m2(m2),.rst(rst),.clk(clk),
        .ppu_a(ppu_a),.ppu_rd_n(ppu_rd_n),.ppu_wr_n(ppu_wr_n),.chr_size(chr_size),
        .prg_a(p0),.chr_a(c0));
    mapper_mmc3 #(.GRUPO(1)) old1(
        .cpu_a(cpu_a),.cpu_d(cpu_d),.cfg(cfg),.map_id(map_id),
        .romsel_n(romsel_n),.cpu_rw(cpu_rw),.m2(m2),.rst(rst),.clk(clk),
        .ppu_a(ppu_a),.ppu_rd_n(ppu_rd_n),.ppu_wr_n(ppu_wr_n),.chr_size(chr_size),
        .prg_a(p1),.chr_a(c1));
    always #10 clk=~clk;
    integer checks=0, i,j,k;
    task check(input ok,input [640:0] msg);
        begin checks=checks+1; if (!ok) $fatal(1,"mapper %0d: %0s",map_id,msg); end
    endtask
    task cycle;
        begin #100; m2=1; #500; m2=0; #400; end
    endtask
    task reset_map(input [7:0] id);
        begin
            map_id=id; cfg=1; rst=1; romsel_n=1; cpu_rw=1;
            ppu_a=0; ppu_rd_n=1; ppu_wr_n=1;
            repeat(3) cycle; rst=0; cycle;
        end
    endtask
    task wr(input [15:0] a,input [7:0] d);
        begin cpu_a=a[14:0]; romsel_n=!a[15]; cpu_d=d; cpu_rw=0;
            cycle; cpu_rw=1; #100;
        end
    endtask
    task bank(input [7:0] n,input [7:0] d);
        begin wr(16'h8000,n); wr(16'h8001,d); end
    endtask
    task ep(input [15:0] a,input [5:0] b);
        begin cpu_a=a[14:0]; romsel_n=!a[15]; cpu_rw=1; #100;
            check(prg_a=={b,a[12:10]},"PRG bank/offset");
            check(prg_rom_en==a[15],"PRG ROM enable");
        end
    endtask
    task ec(input [13:0] a,input [8:0] b,input raw);
        begin ppu_a=a; #100; check(chr_a==b,"CHR bank");
            check(chr_raw==raw,"CHR raw selection");
            check(chr_en==!a[13] && ciram_en==a[13],"pattern/nametable enables");
        end
    endtask
    task fetch(input [13:0] a);
        begin ppu_a=a; #100; ppu_rd_n=0; #200; ppu_rd_n=1; #200; end
    endtask
    task a12pulse;
        begin ppu_a=0; repeat(5) cycle; ppu_a=14'h1000; #400; end
    endtask
    task ram_checks;
        begin
            ep(16'h6000,0); m2=1; #100;
            check(!prg_ram_en,"RAM initially disabled"); m2=0;
            wr(16'ha001,8'h80); cpu_a=15'h6000; romsel_n=1; cpu_rw=0; m2=1; #100;
            check(prg_ram_en && prg_wr,"RAM enabled writable");
            cpu_rw=1; #100; check(!prg_wr,"RAM reads do not write"); m2=0; #100;
            check(!prg_ram_en,"RAM M2 gated");
            wr(16'ha001,8'hc0); cpu_a=15'h6000; romsel_n=1; cpu_rw=0; m2=1; #100;
            check(prg_ram_en && !prg_wr,"RAM write protection");
            cpu_rw=1; m2=0; wr(16'ha001,0);
        end
    endtask
    task irq_checks;
        begin
            wr(16'hc000,2); wr(16'hc001,0); wr(16'he001,0);
            a12pulse; check(!irq,"IRQ reload does not fire latch 2");
            // Too short a low A12 interval must not count.
            ppu_a=0; cycle; ppu_a=14'h1000; #400;
            check(!irq,"IRQ filters short low A12");
            a12pulse; check(!irq,"IRQ count 1");
            a12pulse; check(irq,"IRQ count 0 asserts");
            repeat(2) cycle; check(irq,"IRQ held until acknowledge");
            wr(16'he000,0); #200; check(!irq,"IRQ E000 acknowledges");
            wr(16'hc000,0); wr(16'hc001,0); wr(16'he001,0);
            a12pulse; check(irq,"Sharp-style zero reload IRQ");
            wr(16'he000,0); a12pulse; check(!irq,"disabled IRQ stays clear");
        end
    endtask
    initial begin
        #200;
        reset_map(165);
        ram_checks;
        bank(6,17); ep(16'h8000,17); bank(8'h46,19);
        ep(16'h8000,62); ep(16'hc400,19); ep(16'he000,63);
        // Independent 4 KiB latches; 0 selects the same 4 KiB RAM in both halves.
        bank(0,0); bank(1,8'h14); bank(2,8'h28); bank(4,0);
        ec(0,9'h1f0,1); ec(14'h1000,40,0);
        ppu_a=14'h0fe8; #100; ppu_rd_n=0; #200;
        check(chr_raw && chr_a==9'h1f3,"165 triggering read uses old RAM bank");
        // Address can change at /RD release; sampled trigger must survive.
        ppu_rd_n=1; ppu_a=0; #200; ec(0,20,0);
        ec(14'h1000,40,0); fetch(14'h1fef); ec(14'h1000,9'h1f0,1);
        ppu_wr_n=0; #100; check(chr_wr,"165 mixed RAM writable");
        ppu_wr_n=1; ec(0,20,0); ppu_wr_n=0; #100;
        check(!chr_wr,"165 ROM protected"); ppu_wr_n=1;
        fetch(14'h0fd7); ec(0,9'h1f0,1);
        fetch(14'h0fe0); ec(0,9'h1f0,1); // not FE8
        ppu_a=14'h0fe8; #400; ec(0,9'h1f0,1); // address only
        ppu_a=14'h0fe8; ppu_wr_n=0; #200; ppu_wr_n=1; #200;
        ec(0,9'h1f0,1); // write must not latch
        fetch(14'h2fe8); ec(0,9'h1f0,1); // nametable must not latch
        fetch(14'h0fe8); ec(0,20,0);
        fetch(14'h1fd0); ec(14'h1000,40,0); // independent upper FD latch
        bank(8'h80,8'h34); ec(0,20,0); // inversion ignored by SH2 CHR
        fetch(14'h0fd0); ec(0,52,0);
        bank(0,1); ec(0,0,0); // nonzero raw register, even if 4 KiB page = 0
        irq_checks;

        reset_map(219);
        // Power-on: the last four 8 KiB PRG banks (-4) and CHR 0-7.
        ep(16'h8000,60); ep(16'ha000,61); ep(16'hc000,62); ep(16'he000,63);
        for (i=0;i<8;i=i+1) ec(i*1024,i,0);
        ep(16'h8000,60); check(p0==0 && p1==0,"219 group isolation PRG");
        ram_checks;
        // PRG: $8002 = $26-slot selects the window, $8001 D5..D2 -> bank bits 0..3.
        for (i=0;i<4;i=i+1) for (j=0;j<16;j=j+1) begin
            wr(16'h8002,8'h26-i);
            wr(16'h8001,((j&1)<<5)|((j&2)<<3)|((j&4)<<1)|((j&8)>>1));
            ep(16'h8000+i*8192,j);
        end
        // $8000 clears er0, so a following $8001 leaves PRG alone.
        wr(16'h8002,8'h26); wr(16'h8001,8'h04); ep(16'h8000,8);
        wr(16'h8000,8'h00); wr(16'h8001,8'h3c); ep(16'h8000,8);
        // CHR: command in er1 ($8000), base er2 from commands 08/0A/0E/12/16/1A/1E.
        bank(8'h08,8'h03);                                  // er2 = $30
        bank(8'h09,8'h24); ec(14'h0000,9'h032,0);          // (D>>1) & $0E
        bank(8'h0b,8'h24); ec(14'h0400,9'h033,0);          // (D>>1) | 1
        bank(8'h0d,8'h24); ec(14'h0800,9'h032,0);
        bank(8'h0f,8'h24); ec(14'h0c00,9'h033,0);
        for (i=0;i<4;i=i+1) begin
            bank(8'h10+i*4,8'h0a); ec(14'h1000+i*1024,9'h035,0);  // (D>>1) & $0F
        end
        bank(8'h1e,8'h01); bank(8'h1d,8'h1e); ec(14'h1c00,9'h01f,0); // new base $10
        // $8002 clears er1: the next $8001 is not a CHR command.
        wr(16'h8002,8'h00); wr(16'h8001,8'hff); ec(14'h1c00,9'h01f,0);
        // $A000+ goes to the plain MMC3 core.
        wr(16'ha000,1); ppu_a=14'h2800; #100; check(ciram_a10,"219 horizontal mirroring");
        wr(16'ha000,0); #100; check(!ciram_a10,"219 vertical mirroring");
        irq_checks;

        // 192: plain MMC3; 1 KiB CHR banks $08-$0B are 4 KiB of CHR-RAM (raw region $1F0-$1F3)
        reset_map(192);
        bank(2,8'h07); ec(14'h1000,9'h007,0);                  // ROM below $08
        bank(2,8'h08); ec(14'h1000,9'h1f0,1);
        ppu_wr_n=0; #100; check(chr_wr,"192 CHR-RAM writable"); ppu_wr_n=1;
        bank(3,8'h0b); ec(14'h1400,9'h1f3,1);
        bank(4,8'h0c); ec(14'h1800,9'h00c,0);                  // ROM above $0B
        ppu_wr_n=0; #100; check(!chr_wr,"192 CHR-ROM protected"); ppu_wr_n=1;
        bank(0,8'h0a); ec(14'h0000,9'h1f2,1); ec(14'h0400,9'h1f3,1);   // 2 KiB register: $0A/$0B
        bank(6,5); ep(16'h8000,5); ep(16'he000,63);             // MMC3 PRG unchanged
        irq_checks;

        reset_map(248);
        bank(6,9); ep(16'h8000,9); wr(16'h6000,8'h83);
        ep(16'h8000,6); ep(16'ha000,7); ep(16'hc000,6);
        wr(16'h6000,8'ha6); ep(16'h8000,12); ep(16'ha000,13); ep(16'hc000,14); ep(16'he000,15);
        bank(2,8'h35); wr(16'h6001,1); ec(14'h1000,309,0);
        wr(16'h5080,8'h5a); cpu_a=15'h5000; romsel_n=1; #100;
        check(cpu_doe==8'hff && cpu_dout==8'h5a,"248 protection read");
        cpu_a=15'h4000; #100; check(cpu_doe==0,"248 no read drive outside $5xxx");
        cpu_a=15'h6000; m2=1; #100; check(!prg_ram_en,"248 has no PRG RAM"); m2=0;
        // New group must not contaminate old groups for legacy alias 248.
        ep(16'h8000,12); check(p0==9*8 && p1==9*8,"group 0/1 ignore 248 outer PRG");
        ppu_a=14'h1000; #100; check(c0==53 && c1==53,"group 0/1 ignore 248 outer CHR");
        irq_checks;
        wr(16'ha000,1); ppu_a=14'h2800; #100; check(ciram_a10,"horizontal mirroring");
        wr(16'ha000,0); #100; check(!ciram_a10,"vertical mirroring");
        rst=1; cycle; #200; check(!irq,"reset clears IRQ");
        $display("PASS tb_mmc3c_direct: %0d checks",checks); $finish;
    end
    initial begin #10000000; $fatal(1,"watchdog"); end
endmodule
