`timescale 1ns/1ps
module mapper_jy (
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
    input  wire [5:0]  chr_size,

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
    output wire        chr_raw,    // 1 = chr_a sin la máscara del OS (CHR-RAM extra del 77)
    output wire [7:0]  cpu_dout,
    output wire [7:0]  cpu_doe
);

// Original RTL derived from behavior facts, not emulator implementation text.
// Primary: https://www.nesdev.org/wiki/J.Y._Company_ASIC
// Also consulted local tools/mesen2/.../JyCompany/{JyCompany,Mapper35}.h.
// Follow current NESdev for 35/211 (209-equivalent), masks, IRQ decrement,
// D001 extended mirroring, D002 write protection and D003 latch enable.
// Deliberate limits: only A18..A10 leave this interface (512 KiB PRG/CHR).
// Outer PRG bits therefore alias; outer CHR A18 works, A19/A20 alias.
// No DIP inputs (reads return zero); unknown C007 mode stored but inert.
// clk must oversample M2/PPU strobes and addresses; not a CDC signoff.
// Physical cartridge A0..A9 pass directly, never shifted or reconstructed.
reg [6:0] pb[0:3];
reg [15:0] cb[0:7], nb[0:3];
reg [7:0] mode, mirror, memctl, outer, mul0, mul1, scratch;
reg chrblk;    // CHR block mode: powers on false (non-block), set by $D003 bit5==0
reg [7:0] imode, pre, count, ixor, unknown_mode;
reg enabled, pending;
reg [1:0] latch;
reg [1:0] ms, rs, as;
wire active = map_id == 90 || map_id == 211 || map_id == 209;
wire m209 = map_id == 209;   // 209: mapper 90 + MMC2-style 4 KiB CHR latch (FD/FE)
wire rise_m = ms == 2'b01, fall_m = ms == 2'b10;
wire read_start = rs == 2'b10, read_end = rs == 2'b01;
wire rise_a12 = as == 2'b01;
// Bundle captured on the physical bus edge, before /ROMSEL is released.
// Stable across the delayed clk-domain fall_m consumer. Mapping stays live.
reg [14:0] write_a;
reg [7:0] write_d;
reg write_romsel_n, write_rw;
always @(negedge m2) begin
    write_a <= cpu_a;
    write_d <= cpu_d;
    write_romsel_n <= romsel_n;
    write_rw <= cpu_rw;
end
// Keep the last address seen during the read; the live PPU address can
// already belong to the next ALE cycle when synchronized read_end arrives.
reg [13:0] read_a;
always @(posedge clk) begin
    if (rst) read_a <= 0;
    else if (!ppu_rd_n) read_a <= ppu_a;
end
wire wr = fall_m && !write_rw && active;
wire hiwr = wr && !write_romsel_n;
wire write_lowreg = write_romsel_n && write_a[14:12] == 3'b101;
wire lowreg = romsel_n && cpu_a[14:12] == 3'b101;
wire [7:0] pmask = imode[2] ? 8'h07 : 8'hff;
wire tick = (imode[1:0] == 0 && rise_m) ||
            (imode[1:0] == 1 && rise_a12) ||
            (imode[1:0] == 2 && read_start) ||
            (imode[1:0] == 3 && fall_m && !write_rw);
wire [7:0] next_pre = imode[7:6] == 1 ? pre + 8'd1 : pre - 8'd1;
// Up: clock when the masked prescaler is full (wraps to 0). Down: Mesen does
// `if(--prescaler==0)`, so it clocks when the masked value is 1 (0 wraps to the
// mask without clocking), one step later than a plain ==0 test.
wire pre_wrap = imode[7:6] == 1 ? (pre & pmask) == pmask : (pre & pmask) == 8'd1;
integer i;
always @(posedge clk) begin
    ms <= {ms[0],m2}; rs <= {rs[0],ppu_rd_n}; as <= {as[0],ppu_a[12]};
    if (rst) begin
        ms <= 0; rs <= 3; as <= 0;
        for(i=0;i<4;i=i+1) begin pb[i]<=0; nb[i]<=0; end
        for(i=0;i<8;i=i+1) cb[i]<=0;
        mode<=0; mirror<=0; memctl<=0; outer<=0; chrblk<=0;
        mul0<=0; mul1<=0; scratch<=0; latch<=0;
        imode<=0; pre<=0; count<=0; ixor<=0; unknown_mode<=0;
        enabled<=0; pending<=0;
    end else if(active) begin
        // The prescaler and counter advance whenever the source ticks, even
        // while the IRQ is disabled; only raising the line is gated by enable
        // (Mesen clocks in ProcessCpuClock/TickIrqCounter regardless of enable).
        if(tick && (imode[7:6]==1 || imode[7:6]==2)) begin
            pre <= (pre & ~pmask) | (next_pre & pmask);
            if(pre_wrap) begin
                if(imode[7:6]==1) begin
                    count<=count+8'd1;
                    if(count==8'hff && enabled) pending<=1;
                end else begin
                    count<=count-8'd1;
                    if(count==0 && enabled) pending<=1;
                end
            end
        end
        // Apply a latch after the triggering read, so that read uses old bank.
        // 209: $0FD8-$0FDF / $0FE8-$0FEF (left), $1FD8.. / $1FE8.. (right); FE selects reg +2
        if(read_end && m209 && !read_a[13]) begin
            if(read_a[11:3]==9'h1fb) latch[read_a[12]]<=0;
            if(read_a[11:3]==9'h1fd) latch[read_a[12]]<=1;
        end
        if(wr && write_lowreg && write_a[11]) case(write_a[1:0])
            0: mul0<=write_d;
            1: mul1<=write_d;
            3: scratch<=write_d;
            default: ;
        endcase
        // Register decode matches the JY ASIC (addr & 0xF007): A3..A11 are
        // don't-care, only A14:A12 and A2:A0 select. $DBF9 therefore reaches
        // D001 (mapper 90 mirroring) and $BA02 the equivalent on 176's bus.
        if(hiwr) case(write_a[14:12])
            0: pb[write_a[1:0]]<=write_d[6:0];
            1: cb[write_a[2:0]][7:0]<=write_d;
            2: cb[write_a[2:0]][15:8]<=write_d;
            3: begin
                if(write_a[2]) nb[write_a[1:0]][15:8]<=write_d;
                else nb[write_a[1:0]][7:0]<=write_d;
            end
            4: case(write_a[2:0])
                0: begin enabled<=write_d[0]; if(!write_d[0]) begin pending<=0; pre<=0; end end
                1: imode<=write_d;
                2: begin enabled<=0; pending<=0; pre<=0; end
                3: enabled<=1;
                4: pre<=write_d ^ ixor;
                5: count<=write_d ^ ixor;
                6: ixor<=write_d;
                7: unknown_mode<=write_d;
            endcase
            5: if(!write_a[2]) case(write_a[1:0])   // D000-D003 (A2=0)
                0: mode<=write_d;
                1: mirror<=write_d;
                2: memctl<=write_d;
                3: begin outer<=write_d; chrblk<=!write_d[5]; end
            endcase
            default: ;
        endcase
    end
end
// PRG banking per the J.Y. ASIC D000 mode (prgMode = mode[2:0]): bits 1:0 pick
// the window size and bit2 swaps the fixed tail bank for prgReg3. InvertPrgBits
// applies only in mode 3 and drops bit3 of the register (out[3]=0). Window base
// defaults are 0x3C/0x3E/0x3F (last 32/16/8 KiB), not 0x7F.
function [6:0] invprg;
    input [6:0] b;
    begin invprg = {b[0],b[1],b[2],1'b0,b[4],b[5],b[6]}; end
endfunction
wire win6=romsel_n && cpu_a[14:13]==3;
wire [1:0] slot=cpu_a[14:13];
wire inv = (mode[1:0]==2'b11);
reg [6:0] p0,p1,p2,p3;
reg [7:0] bank8;        // banco de 8 KB de la ventana activa
always @* begin
    p0 = inv ? invprg(pb[0]) : pb[0];
    p1 = inv ? invprg(pb[1]) : pb[1];
    p2 = inv ? invprg(pb[2]) : pb[2];
    p3 = inv ? invprg(pb[3]) : pb[3];
    if(win6 && mode[7]) case(mode[1:0])          // PRG-ROM opcional en $6000
        0:       bank8 = {p3,2'b00} + 8'd3;       // prgReg3*4+3
        1:       bank8 = {p3,1'b0}  + 8'd1;       // prgReg3*2+1
        default: bank8 = {1'b0,p3};
    endcase
    else case(mode[1:0])
        0:       bank8 = {1'b0,(mode[2]?p3:7'h3c)} + {6'd0,slot};
        1:       bank8 = slot[1] ? ({1'b0,(mode[2]?p3:7'h3e)} + {7'd0,slot[0]})
                                 : ({p1,1'b0} + {7'd0,slot[0]});
        default: case(slot)
                    2'd0: bank8={1'b0,p0};
                    2'd1: bank8={1'b0,p1};
                    2'd2: bank8={1'b0,p2};
                    default: bank8={1'b0,(mode[2]?p3:7'h3f)};
                 endcase
    endcase
end
// Advanced nametable control: D000 bit5, but mapper 211 behaves as if it were
// always set and mapper 090 as if always clear (NESdev J.Y. ASIC).
wire extnt=(map_id==211 || mode[5]) && map_id!=90;
wire ntrom=active && ppu_a[13] && extnt && !ppu_rd_n &&
           (mode[6] || (nb[ppu_a[11:10]][7] != memctl[7]));
// CHR banking per the J.Y. ASIC (D003 = outer): mirrorChr=bit7, block mode when
// bit5 is clear, chrBlock = ((v&0x18)>>2)|(v&0x01). In block mode the register is
// (chrLow & mask) | (chrBlock<<shift) with (mask,shift) by chrMode; otherwise it is
// chrLow | chrHigh<<8. For mappers 90/211 the 4 KiB latch is fixed at {0,4}; 209 latches
// {0,2} / {4,6} on PPU reads of $xFD8/$xFE8 (powers on at {0,4}).
wire mirrorChr   = outer[7];
wire chrBlockMode= chrblk;
wire [2:0] chrBlock = {outer[4], outer[3], outer[0]};
// Note: a NT-via-CHR page beyond the physical CHR is read 0 by Mesen2; this
// hardware wraps chr_a to 9 bits (the real CHR SRAM address width). Games never
// set such pages, so the difference is a synthetic-test artifact only.
reg  [2:0] idx;
reg  [7:0] cmask;
reg  [3:0] cshift;
reg  [15:0] chrReg;
reg  [8:0] chrbank;
always @* begin
    case(mode[4:3])
        0: begin idx=3'd0;                cmask=8'h1f; cshift=4'd5; end
        1: begin idx=m209 ? {ppu_a[12],latch[ppu_a[12]],1'b0} : (ppu_a[12]?3'd4:3'd0); cmask=8'h3f; cshift=4'd6; end
        2: begin idx={ppu_a[12:11],1'b0}; cmask=8'h7f; cshift=4'd7; end
        default: begin idx=ppu_a[12:10];  cmask=8'hff; cshift=4'd8; end
    endcase
    if(mode[4:3]>=2 && mirrorChr && (idx==3'd2 || idx==3'd3)) idx=idx-3'd2;
    if(chrBlockMode) chrReg=(cb[idx][7:0] & cmask) | ({13'd0,chrBlock} << cshift);
    else             chrReg=cb[idx];
    case(mode[4:3])
        0: chrbank={chrReg[5:0],ppu_a[12:10]};
        1: chrbank={chrReg[6:0],ppu_a[11:10]};
        2: chrbank={chrReg[7:0],ppu_a[10]};
        default: chrbank=chrReg[8:0];
    endcase
    if(ntrom) chrbank=nb[ppu_a[11:10]][8:0];
end
assign prg_a=(win6 && !mode[7]) ? {6'd0,cpu_a[12:10]} : {bank8[5:0],cpu_a[12:10]};
assign prg_rom_en=active && (!romsel_n || (win6 && mode[7] && m2 && cpu_rw));
assign prg_ram_en=active && win6 && !mode[7] && (map_id==35 || cfg[1]) && m2;
assign prg_wr=prg_ram_en && !cpu_rw;
assign chr_a=chrbank;
assign chr_en=active && (!ppu_a[13] || ntrom);
assign chr_wr=active && !ppu_a[13] && cfg[7] && memctl[6] && !ppu_wr_n;
assign chr_raw=1'b0;
assign ciram_en=active && ppu_a[13] && !ntrom;
assign ciram_a10=extnt ? nb[ppu_a[11:10]][0] :
                 mirror[1] ? mirror[0] : mirror[0] ? ppu_a[11] : ppu_a[10];
assign irq=active && pending;
wire [15:0] product=mul0*mul1;
reg [7:0] rd,oe;
always @* begin
    rd=0; oe=0;
    if(active && lowreg && cpu_rw && m2) begin
        if(!cpu_a[11]) begin rd=0; oe=8'hff; end
        else case(cpu_a[1:0])
            0: begin rd=product[7:0]; oe=8'hff; end
            1: begin rd=product[15:8]; oe=8'hff; end
            3: begin rd=scratch; oe=8'hff; end
            default: ;
        endcase
    end
end
assign cpu_dout=rd;
assign cpu_doe=oe;
endmodule
