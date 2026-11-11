`timescale 1ns/1ps
// Mapper 176 = Waixing FK23C multicart ASIC (iNES 1.0 behaviour, submapper not selectable).
// Clean-room from NESdev "INES Mapper 176" facts; local Mesen2 Fk23C.h was read only to confirm
// register layout and behaviour, no code copied.
//
// Registers
//   $5000-$5FFF with A4=1 (addr & $5010 == $5010), only while FK regs are enabled or WRAM config
//   is off: A1:0 = 0 PRG mode/CHR options/base bits 8:7, 1 base bits 6:0, 2 CHR base + PRG base
//   bit 9, 3 extended MMC3 / CNROM mode. $6000-$7FFF and $4020-$4FFF are never registers.
//   $8000/$8001 MMC3 bank select/data (12 registers in extended mode), $A000 mirroring,
//   $A001 WRAM/FK-register config, $C000/$C001/$E000/$E001 MMC3 A12 IRQ (asserts 2 CPU cycles
//   after the counter reaches 0; $E000 is the only acknowledge).
// N8 mapping
//   - PRG modes 5-7 keep the previous PRG mapping, so the four 8 KiB PRG pages are latched and
//     only follow the registers while the mode is 0-4.
//   - WRAM is 32 KiB in 4 banks of PRG-RAM: $6000 = bank sel, $4020-$5FFF = bank sel+1 when the
//     WRAM config is on; otherwise $6000 = bank 0 (write-protectable) or unmapped.
//   - CHR-RAM (no CHR-ROM, $5010.5 select, or "RAM in first CHR bank" for pages 0-7) is 256 KiB
//     in the upper half of the CHR SRAM (chr_raw), so a CHR-ROM used together with CHR-RAM must
//     be <= 256 KiB. Pages $F8-$FF of that RAM overlap the area the OS uses for 4-screen/menu.
module mapper_fk23c (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,
    input  wire        ppu_wr_n,
    input  wire [7:0]  cfg,
    input  wire        rst,
    input  wire        clk,
    input  wire [7:0]  map_id,
    output wire [18:10] prg_a,
    output wire        prg_rom_en,
    output wire        prg_ram_en,
    output wire        prg_wr,
    output wire [18:10] chr_a,
    output wire        chr_en,
    output wire        chr_wr,
    output wire        ciram_en,
    output wire        ciram_a10,
    output wire        irq,
    output wire        chr_raw
);
    // ---------------------------------------------------------------- registers (M2 fall)
    reg [2:0] prgmode;
    reg       outerchr, selchrram, mmc3chr, extmode, cnrom;
    reg [9:0] prgbase;
    reg [7:0] chrbase;
    reg [1:0] cnromreg, mirr, wrambank;
    reg       raminchr, allowss, wramcfg, fkregs, wramwp, wramen;
    reg       invprg, invchr;
    reg [3:0] curreg;
    reg [7:0] r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11;
    reg [7:0] irq_latch;
    reg       irq_en, reload_tgl, ack_tgl;

    task defaults;
    begin
        prgmode <= 0; outerchr <= 0; selchrram <= 0; mmc3chr <= 1; extmode <= 0; cnrom <= 0;
        prgbase <= 0; chrbase <= 0; cnromreg <= 0; mirr <= 0; wrambank <= 0;
        raminchr <= 0; allowss <= 0; wramcfg <= 0; fkregs <= 0; wramwp <= 0; wramen <= 0;
        invprg <= 0; invchr <= 0; curreg <= 0; irq_latch <= 0; irq_en <= 0;
        r0 <= 8'h00; r1 <= 8'h02; r2 <= 8'h04; r3 <= 8'h05; r4 <= 8'h06; r5 <= 8'h07;
        r6 <= 8'h00; r7 <= 8'h01; r8 <= 8'hFE; r9 <= 8'hFF; r10 <= 8'hFF; r11 <= 8'hFF;
    end
    endtask

    initial begin
        prgmode = 0; outerchr = 0; selchrram = 0; mmc3chr = 1; extmode = 0; cnrom = 0;
        prgbase = 0; chrbase = 0; cnromreg = 0; mirr = 0; wrambank = 0;
        raminchr = 0; allowss = 0; wramcfg = 0; fkregs = 0; wramwp = 0; wramen = 0;
        invprg = 0; invchr = 0; curreg = 0; irq_latch = 0; irq_en = 0; reload_tgl = 0; ack_tgl = 0;
        r0 = 8'h00; r1 = 8'h02; r2 = 8'h04; r3 = 8'h05; r4 = 8'h06; r5 = 8'h07;
        r6 = 8'h00; r7 = 8'h01; r8 = 8'hFE; r9 = 8'hFF; r10 = 8'hFF; r11 = 8'hFF;
    end

    wire [7:0] d     = cpu_d;
    wire       wr    = !cpu_rw;
    wire       in5   = romsel_n && cpu_a[14:12] == 3'b101;          // $5000-$5FFF
    wire       cfgw  = wr && in5 && cpu_a[4] && (fkregs || !wramcfg); // FK23 config write
    wire       romw  = wr && !romsel_n;                              // $8000-$FFFF
    wire [3:0] wreg  = extmode ? curreg : {1'b0, curreg[2:0]};

    always @(negedge m2) begin
        if (rst) defaults;
        else begin
            if (cfgw) case (cpu_a[1:0])
                2'd0: begin
                    prgmode   <= d[2:0];
                    outerchr  <= d[4];
                    selchrram <= d[5];
                    mmc3chr   <= !d[6];
                    prgbase   <= (prgbase & ~10'h180) | {1'b0, d[7], d[3], 7'd0};
                end
                2'd1: prgbase <= (prgbase & ~10'h07F) | {3'd0, d[6:0]};
                2'd2: begin
                    prgbase  <= (prgbase & ~10'h200) | {d[6], 9'd0};
                    chrbase  <= d;
                    cnromreg <= 2'd0;
                end
                2'd3: begin extmode <= d[1]; cnrom <= d[6] | d[2]; end
            endcase
            if (romw) begin
                // CNROM latch on $8000-$9FFF and $C000-$FFFF (not $A000-$BFFF)
                if (cnrom && (cpu_a[14:13] == 2'b00 || cpu_a[14])) cnromreg <= d[1:0];
                case ({cpu_a[14:13], cpu_a[0]})
                    3'b000: begin invprg <= d[6]; invchr <= d[7]; curreg <= d[3:0]; end
                    3'b001: if (wreg < 4'd12) case (wreg)
                        4'd0: r0 <= d;  4'd1: r1 <= d;  4'd2: r2 <= d;   4'd3: r3 <= d;
                        4'd4: r4 <= d;  4'd5: r5 <= d;  4'd6: r6 <= d;   4'd7: r7 <= d;
                        4'd8: r8 <= d;  4'd9: r9 <= d;  4'd10: r10 <= d; default: r11 <= d;
                    endcase
                    3'b010: mirr <= d[1:0];
                    3'b011: begin
                        // with bit 5 clear only bits 7:6 are taken (the rest read as 0)
                        wrambank <= d[5] ? d[1:0] : 2'd0;
                        raminchr <= d[5] & d[2];
                        allowss  <= d[5] & d[3];
                        wramcfg  <= d[5];
                        fkregs   <= d[6];
                        wramwp   <= d[6];
                        wramen   <= d[7];
                    end
                    3'b100: irq_latch <= d;
                    3'b101: reload_tgl <= ~reload_tgl;
                    3'b110: begin irq_en <= 1'b0; ack_tgl <= ~ack_tgl; end
                    3'b111: irq_en <= 1'b1;
                endcase
            end
        end
    end

    // ---------------------------------------------------------------- PRG
    wire [10:0] pB   = {prgbase, 1'b0};                 // base bits << 1
    wire [7:0]  pim  = 8'h3f >> prgmode;                // inner mask (modes 0-2)
    wire [10:0] pout = pB & ~{3'd0, pim};
    wire [10:0] L0 = extmode ? ({3'd0, r6} | pB) : ({3'd0, r6 & pim}    | pout);
    wire [10:0] L1 = extmode ? ({3'd0, r7} | pB) : ({3'd0, r7 & pim}    | pout);
    wire [10:0] L2 = extmode ? ({3'd0, r8} | pB) : ({3'd0, 8'hFE & pim} | pout);
    wire [10:0] L3 = extmode ? ({3'd0, r9} | pB) : ({3'd0, 8'hFF & pim} | pout);
    wire [10:0] b4 = {prgbase & 10'h3FE, 1'b0};         // mode 4: 32 KiB base
    reg  [10:0] pc0, pc1, pc2, pc3;
    always @(*) begin
        case (prgmode)
            3'd3:    begin pc0 = pB;      pc1 = pB | 11'd1; pc2 = pB;      pc3 = pB | 11'd1; end
            3'd4:    begin pc0 = b4;      pc1 = b4 | 11'd1; pc2 = b4 | 11'd2; pc3 = b4 | 11'd3; end
            default: begin pc0 = invprg ? L2 : L0; pc1 = L1; pc2 = invprg ? L0 : L2; pc3 = L3; end
        endcase
    end
    reg [5:0] ps0 = 6'h00, ps1 = 6'h01, ps2 = 6'h3E, ps3 = 6'h3F;   // power-on: mode 0
    always @(posedge clk)
        if (prgmode <= 3'd4) begin
            ps0 <= pc0[5:0]; ps1 <= pc1[5:0]; ps2 <= pc2[5:0]; ps3 <= pc3[5:0];
        end
    reg [5:0] pbank;
    always @(*) case (cpu_a[14:13])
        2'd0: pbank = ps0; 2'd1: pbank = ps1; 2'd2: pbank = ps2; default: pbank = ps3;
    endcase

    // WRAM
    wire win6  = romsel_n && cpu_a[14:13] == 2'b11;                        // $6000-$7FFF
    wire win45 = romsel_n && cpu_a[14:13] == 2'b10 && cpu_a[12:5] != 8'd0; // $4020-$5FFF
    wire [1:0] rbank = win6 ? (wramcfg ? wrambank : 2'd0) : (wrambank + 2'd1);
    wire ram_sel = (win6 && (wramcfg || wramen)) || (win45 && wramcfg);
    // writes: $6000 honours the protect bit only without the config; $5xxx is a register
    // (not RAM) while the FK registers are enabled
    wire ram_wok = win6 ? (wramcfg || !wramwp) : !(cpu_a[12] && fkregs);
    assign prg_ram_en = m2 && ram_sel && (cpu_rw || ram_wok);
    assign prg_wr     = prg_ram_en && !cpu_rw;
    assign prg_a      = (win6 || win45) ? {4'd0, rbank, cpu_a[12:10]} : {pbank, cpu_a[12:10]};
    assign prg_rom_en = !romsel_n;

    // ---------------------------------------------------------------- CHR
    wire [2:0]  cL   = ppu_a[12:10] ^ (invchr ? 3'd4 : 3'd0);
    wire [10:0] cB   = {chrbase, 3'd0};
    wire [7:0]  cim  = outerchr ? 8'h7f : 8'hff;
    wire [1:0]  cnin = cnrom ? (outerchr ? 2'd1 : 2'd3) : 2'd0;
    reg  [7:0]  cr;
    reg  [10:0] cpage;
    always @(*) begin
        if (extmode) case (cL)
            3'd0: cr = r0;  3'd1: cr = r10; 3'd2: cr = r1; 3'd3: cr = r11;
            3'd4: cr = r2;  3'd5: cr = r3;  3'd6: cr = r4; default: cr = r5;
        endcase
        else case (cL)
            3'd0: cr = r0 & 8'hFE; 3'd1: cr = r0 | 8'h01; 3'd2: cr = r1 & 8'hFE; 3'd3: cr = r1 | 8'h01;
            3'd4: cr = r2;  3'd5: cr = r3;  3'd6: cr = r4; default: cr = r5;
        endcase
        if (!mmc3chr) cpage = {({6'd0, cnromreg & cnin} | chrbase), 3'd0} | {8'd0, ppu_a[12:10]};
        else if (extmode) cpage = {3'd0, cr} | cB;
        else cpage = {3'd0, cr & cim} | (cB & ~{3'd0, cim});
    end
    wire useram = cfg[7] || selchrram || (wramcfg && raminchr && cpage <= 11'd7);
    assign chr_raw   = useram;
    assign chr_a     = useram ? {1'b1, cpage[7:0]} : cpage[8:0];
    assign chr_en    = !ppu_a[13];
    assign chr_wr    = useram && !ppu_wr_n && !ppu_a[13];
    assign ciram_en  = ppu_a[13];
    wire [1:0] mm    = mirr & (allowss ? 2'b11 : 2'b01);
    assign ciram_a10 = mm[1] ? mm[0] : (mm[0] ? ppu_a[11] : ppu_a[10]);

    // ---------------------------------------------------------------- IRQ (clk domain)
    wire a12_clk, m2f;
    a12_filter #(.LOW_M2(4), .W(3)) flt (.clk(clk), .m2(m2), .a12(ppu_a[12]), .a12_clk(a12_clk), .m2_fall(m2f));
    reg [2:0] rel_s = 0, ack_s = 0;
    reg [1:0] en_s = 0;
    reg [7:0] counter = 0;
    reg       reload = 0, pending = 0;
    reg [1:0] delay = 0;
    wire [7:0] next = (counter == 8'd0 || reload) ? irq_latch : counter - 8'd1;
    always @(posedge clk) begin
        rel_s <= {rel_s[1:0], reload_tgl};
        ack_s <= {ack_s[1:0], ack_tgl};
        en_s  <= {en_s[0], irq_en};
        if (rst) begin counter <= 0; reload <= 0; pending <= 0; delay <= 0; end
        else begin
            if (m2f && delay != 2'd0) begin
                delay <= delay - 2'd1;
                if (delay == 2'd1) pending <= 1'b1;
            end
            if (rel_s[2] != rel_s[1]) begin counter <= 0; reload <= 1'b1; end
            else if (a12_clk) begin
                counter <= next;
                reload  <= 1'b0;
                if (next == 8'd0 && en_s[1]) delay <= 2'd2;
            end
            if (ack_s[2] != ack_s[1]) pending <= 1'b0;
        end
    end
    assign irq = pending;
endmodule
