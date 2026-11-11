`timescale 1ns/1ps
// Mapper 35 (J.Y. Company simple ASIC / SMB2j-type pirate board).
// Clean-room from NESdev iNES Mapper 035 facts; local Mesen2 Mapper35.h was
// read only to confirm register addresses and behaviour, no code copied.
//   $8000-$8003 (addr&0xF007): 8 KiB PRG page for that window (4 banks).
//   $9000-$9007 (addr&0xF007): 1 KiB CHR page for that window (8 banks).
//   $C002: IRQ disable + acknowledge.  $C003: IRQ enable.  $C005: IRQ counter.
//   $D001: bit0 mirroring (1 = horizontal, 0 = vertical).
//   IRQ: MMC3-style A12 rise decrements the counter; fires at 0 and self-disables.
// A14:A12 and A2:A0 decode (A3..A11 don't-care), matching the ASIC's $F007 mask.
module mapper35 (
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
    output wire        irq
);
    reg [7:0] pr[0:3], ch[0:7];
    reg horizontal=0;
    reg [7:0] reload=0;
    reg load_tgl=0, en_tgl=0, dis_tgl=0;
    integer i;
    wire [14:0] a = cpu_a & 15'h7007;      // A14:A12 + A2:A0
    wire wr8 = !romsel_n && !cpu_rw;
    initial begin
        for(i=0;i<4;i=i+1) pr[i]=8'hff;
        for(i=0;i<8;i=i+1) ch[i]=0;
    end
    always @(negedge m2) begin
        if(rst) begin
            for(i=0;i<4;i=i+1) pr[i]<=8'hff;   // slot 3 defaults to the last bank
            for(i=0;i<8;i=i+1) ch[i]<=0;
            horizontal<=!cfg[0]; reload<=0; load_tgl<=0; en_tgl<=0; dis_tgl<=0;
        end else if(wr8) begin
            if(a[14:12]==3'd0 && !a[2]) pr[a[1:0]]<=cpu_d;          // $8000-$8003
            else if(a[14:12]==3'd1)     ch[a[2:0]]<=cpu_d;          // $9000-$9007
            else if(a==15'h4002)        dis_tgl<=~dis_tgl;          // $C002 disable+ack
            else if(a==15'h4003)        en_tgl<=~en_tgl;            // $C003 enable
            else if(a==15'h4005)      begin reload<=cpu_d; load_tgl<=~load_tgl; end  // $C005
            else if(a==15'h5001)        horizontal<=cpu_d[0];       // $D001
        end
    end

    // IRQ counter in the clk domain, fed by the filtered A12 rise.
    wire a12_line, m2_fall_u;
    a12_filter filt(.clk(clk), .m2(m2), .a12(ppu_a[12]), .a12_clk(a12_line), .m2_fall(m2_fall_u));
    reg [2:0] load_s=0, en_s=0, dis_s=0;
    reg [7:0] cnt=0;
    reg en=0, pending=0;
    always @(posedge clk) begin
        load_s<={load_s[1:0],load_tgl};
        en_s  <={en_s[1:0],en_tgl};
        dis_s <={dis_s[1:0],dis_tgl};
        if(rst) begin cnt<=0; en<=0; pending<=0; end
        else begin
            if(load_s[2]!=load_s[1]) cnt<=reload;
            if(en_s[2]!=en_s[1])     en<=1;
            if(dis_s[2]!=dis_s[1])   begin en<=0; pending<=0; end
            else if(en && a12_line) begin
                cnt<=cnt-1'b1;
                if(cnt==8'd1) begin pending<=1; en<=0; end
            end
        end
    end

    wire [1:0] slot = cpu_a[14:13];
    assign prg_a      = romsel_n ? {6'd0, cpu_a[12:10]} : {pr[slot][5:0], cpu_a[12:10]};
    assign prg_rom_en = !romsel_n;
    assign prg_ram_en = 1'b0;
    assign prg_wr     = 1'b0;
    assign chr_a      = cfg[7] ? {6'd0, ppu_a[12:10]} : {1'b0, ch[ppu_a[12:10]]};
    assign chr_en     = !ppu_a[13];
    assign chr_wr     = cfg[7] && !ppu_wr_n && !ppu_a[13];
    assign ciram_en   = ppu_a[13];
    assign ciram_a10  = horizontal ? ppu_a[11] : ppu_a[10];
    assign irq        = pending;
endmodule
