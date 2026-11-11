`timescale 1ns/1ps
// vrc7_fm.v — FM sound of the Konami VRC7 (6-channel, 2-operator YM2413 derivative). Own implementation.
// Behaviour follows the public YM2413/VRC7 descriptions (register map, envelope rates and step patterns,
// LFOs, log-sine/exponent synthesis, VRC7 instrument set measured by Nuke.YKT) and is checked sample by
// sample against the bench oracle emu2413 as configured by Mesen2 (tools/fm/fmref). Tables: vrc7_tables.v.
//
// `wr` writes register `wreg` with `wdata` ($9010 index + $9030 data of the mapper); writes are queued and
// applied between samples. `tick` requests one sample (49716 Hz); `sample` is updated and `valid` pulses
// when ready. One sample takes ~6 x 22 clk cycles; at 50 MHz there are ~1000 cycles per sample.
module vrc7_fm (
    input  wire        clk,
    input  wire        rst,
    input  wire        wr,
    input  wire [7:0]  wreg,
    input  wire [7:0]  wdata,
    input  wire        tick,
    output reg  signed [15:0] sample = 16'sd0,
    output reg         valid = 1'b0
);
    localparam ATTACK = 3'd0, DECAY = 3'd1, SUSTAIN = 3'd2, RELEASE = 3'd3, DAMP = 3'd4;

    // ------------------------------------------------------------------ registers
    reg [7:0] up  [0:7];                        // user instrument ($00-$07)
    reg [7:0] r10 [0:5];
    reg [7:0] r20 [0:5];
    reg [7:0] r30 [0:5];
    reg [7:0] test = 8'd0;
    reg [5:0] kst  = 6'd0;                      // key status per channel

    // ------------------------------------------------------------------ slot state, index {ch, car}
    reg [18:0] ph   [0:11];
    reg [6:0]  eo   [0:11];
    reg [2:0]  st   [0:11];
    reg [3:0]  pend [0:11];                     // {EG, RKS, TLL, WS} update requests
    reg [3:0]  rh   [0:11];
    reg [1:0]  rl   [0:11];
    reg [3:0]  sh   [0:11];
    reg [7:0]  tll  [0:11];
    reg [3:0]  rks  [0:11];
    reg        ws   [0:11];
    reg        keyf [0:11];
    reg        susf [0:11];
    reg signed [13:0] o0 [0:5];                 // modulator output history (feedback)
    reg signed [13:0] o1 [0:5];

    // ------------------------------------------------------------------ LFOs and envelope counter
    reg [12:0] pmph  = 13'd0;
    reg [5:0]  amsub = 6'd0;
    reg [7:0]  amidx = 8'd0;
    reg [15:0] egcnt = 16'd0;
    wire [3:0] lfo_am;
    vrc7_rom_am u_am (.idx(amidx), .q(lfo_am));

    integer k;
    initial begin
        for (k = 0; k < 8; k = k + 1) up[k] = 8'd0;
        for (k = 0; k < 6; k = k + 1) begin r10[k] = 0; r20[k] = 0; r30[k] = 0; o0[k] = 0; o1[k] = 0; end
        for (k = 0; k < 12; k = k + 1) begin
            ph[k] = 0; eo[k] = 7'd127; st[k] = RELEASE; pend[k] = 4'hF; rh[k] = 0; rl[k] = 0; sh[k] = 0;
            tll[k] = 0; rks[k] = 0; ws[k] = 0; keyf[k] = 0; susf[k] = 0;
        end
    end

    // ------------------------------------------------------------------ current slot
    reg  [2:0] ch = 3'd0;
    reg        sl = 1'b0;                       // 0 modulator, 1 carrier
    wire [3:0] cur = {ch, sl};
    wire [3:0] im  = {ch, 1'b0};
    wire [8:0] fnum = {r20[ch][0], r10[ch]};
    wire [2:0] blk  = r20[ch][3:1];
    wire [3:0] inst = r30[ch][7:4];

    wire [7:0] rp [0:7];
    genvar gi;
    generate for (gi = 0; gi < 8; gi = gi + 1) begin : g_patch
        vrc7_rom_patch u_p (.inst(inst), .idx(gi[2:0]), .q(rp[gi]));
    end endgenerate
    wire uu = (inst == 4'd0);
    wire [7:0] b0 = uu ? up[0] : rp[0], b1 = uu ? up[1] : rp[1], b2 = uu ? up[2] : rp[2];
    wire [7:0] b3 = uu ? up[3] : rp[3], b4 = uu ? up[4] : rp[4], b5 = uu ? up[5] : rp[5];
    wire [7:0] b6 = uu ? up[6] : rp[6], b7 = uu ? up[7] : rp[7];
    // fields of the current slot
    wire [7:0] bs = sl ? b1 : b0;
    wire       f_am = bs[7], f_pm = bs[6], f_eg = bs[5], f_kr = bs[4];
    wire [3:0] f_ml = bs[3:0];
    wire [1:0] f_kl = sl ? b3[7:6] : b2[7:6];
    wire [5:0] f_tl = sl ? {r30[ch][3:0], 2'b00} : b2[5:0];        // carrier: volume << 2
    wire       f_ws = sl ? b3[4] : b3[3];
    wire [2:0] m_fb = b3[2:0];
    wire [3:0] f_ar = sl ? b5[7:4] : b4[7:4], f_dr = sl ? b5[3:0] : b4[3:0];
    wire [3:0] f_sl = sl ? b7[7:4] : b6[7:4], f_rr = sl ? b7[3:0] : b6[3:0];
    wire       c_am = b1[7];

    wire [6:0] klp;
    vrc7_rom_kl u_kl (.fnum4(fnum[8:5]), .blk(blk), .kl(f_kl), .q(klp));

    function [4:0] ml_val;                      // frequency multiplier x2
        input [3:0] ml;
        case (ml)
            4'd0: ml_val = 1;   4'd1: ml_val = 2;   4'd2: ml_val = 4;   4'd3: ml_val = 6;
            4'd4: ml_val = 8;   4'd5: ml_val = 10;  4'd6: ml_val = 12;  4'd7: ml_val = 14;
            4'd8: ml_val = 16;  4'd9: ml_val = 18;  4'd10: ml_val = 20; 4'd11: ml_val = 20;
            4'd12: ml_val = 24; 4'd13: ml_val = 24; default: ml_val = 30;
        endcase
    endfunction
    function step_bit;                          // envelope step pattern [rate_l][i]
        input [1:0] l; input [2:0] i;
        case (l)
            2'd0: step_bit = i[0];
            2'd1: step_bit = i[0] | (i == 3'd4);
            2'd2: step_bit = i[0] | i[1];
            default: step_bit = (i != 3'd0);
        endcase
    endfunction
    function signed [3:0] pm_off;               // vibrato offset added to fnum*2
        input [2:0] row; input [2:0] col;
        reg [3:0] a;
        begin
            a = {2'b00, row[2:1]};
            case (col)
                3'd1, 3'd3: pm_off = a;
                3'd2:       pm_off = {1'b0, row};
                3'd5, 3'd7: pm_off = -a;
                3'd6:       pm_off = -{1'b0, row};
                default:    pm_off = 4'sd0;
            endcase
        end
    endfunction

    // ---- working copy of the current slot (loaded from the arrays, stored back at the end) and its
    //      instrument fields, so the per-slot logic below starts from registers (timing at 50 MHz)
    reg [18:0] w_ph; reg [6:0] w_eo; reg [2:0] w_st; reg [3:0] w_pend, w_rh, w_sh, w_rks; reg [1:0] w_rl;
    reg [7:0] w_tll; reg w_ws, w_key, w_sus, w_reset; reg [18:0] w_inc;
    reg q_pm, q_eg, q_kr, q_ws; reg [3:0] q_ml, q_ar, q_dr, q_sl, q_rr; reg [5:0] q_tl; reg [6:0] q_klp;
    reg [8:0] q_fnum; reg [2:0] q_blk;

    // ---- stage C: commit pending parameter updates
    reg [3:0] c_pend, c_rh, c_sh, c_rks; reg [1:0] c_rl; reg [7:0] c_tll; reg c_ws;
    reg [3:0] prate, rr_h; reg [4:0] rsum;
    always @(*) begin
        c_pend = w_pend; c_rh = w_rh; c_rl = w_rl; c_sh = w_sh; c_tll = w_tll; c_rks = w_rks; c_ws = w_ws;
        prate = 4'd0; rsum = 5'd0; rr_h = 4'd0;
        if (w_pend != 4'd0) begin
            if (w_pend[0]) c_ws = q_ws;
            if (w_pend[1]) c_tll = {1'b0, q_tl, 1'b0} + {1'b0, q_klp};
            if (w_pend[2]) c_rks = q_kr ? {q_blk, q_fnum[8]} : {2'b00, q_blk[2:1]};
            if (w_pend[2] | w_pend[3]) begin
                if (!sl && !w_key) prate = 4'd0;
                else case (w_st)
                    ATTACK:  prate = q_ar;
                    DECAY:   prate = q_dr;
                    SUSTAIN: prate = q_eg ? 4'd0 : q_rr;
                    RELEASE: prate = w_sus ? 4'd5 : (q_eg ? q_rr : 4'd7);
                    DAMP:    prate = 4'd12;
                    default: prate = 4'd0;
                endcase
                if (prate == 4'd0) begin
                    c_sh = 4'd0; c_rh = 4'd0; c_rl = 2'd0;                   // requests stay pending
                end else begin
                    rsum = {1'b0, prate} + {3'b000, c_rks[3:2]};
                    rr_h = (rsum > 5'd15) ? 4'd15 : rsum[3:0];
                    c_rh = rr_h; c_rl = c_rks[1:0];
                    if (w_st == ATTACK) c_sh = (rr_h != 0 && rr_h < 12) ? (4'd13 - rr_h) : 4'd0;
                    else                c_sh = (rr_h < 13) ? (4'd13 - rr_h) : 4'd0;
                    c_pend = 4'd0;
                end
            end else c_pend = 4'd0;
        end
    end

    // ---- phase increment (from the latched fields; the vibrato LFO is already advanced)
    reg signed [3:0] e_pm; reg [11:0] e_x; reg [21:0] e_inc;
    always @(*) begin
        e_pm = q_pm ? pm_off(q_fnum[8:6], pmph[12:10]) : 4'sd0;
        e_x = {2'b00, q_fnum, 1'b0} + {{8{e_pm[3]}}, e_pm};
        e_inc = (({10'd0, e_x} * {17'd0, ml_val(q_ml)}) << q_blk) >> 2;
    end

    // ---- stage E: envelope and state transitions (after the commit)
    reg [15:0] e_mask; reg [2:0] e_idx; reg [3:0] e_s; reg [7:0] e_v; reg [6:0] e_eo; reg [2:0] e_st;
    reg e_egreq, e_reset; reg [4:0] e_ars;
    always @(*) begin
        e_mask = (16'd1 << w_sh) - 16'd1;
        e_v = {1'b0, w_eo};
        e_s = 4'd0; e_idx = 3'd0;
        if (w_st == ATTACK) begin
            if (w_eo != 0 && w_rh != 0 && ((egcnt & e_mask & ~16'd3) == 16'd0)) begin
                e_idx = {egcnt[3:2], 1'b0};
                case (w_rh)
                    4'd12: e_s = 4'd4 - {3'b000, step_bit(w_rl, e_idx)};
                    4'd13: e_s = 4'd3 - {3'b000, step_bit(w_rl, e_idx)};
                    4'd14: e_s = 4'd2 - {3'b000, step_bit(w_rl, e_idx)};
                    4'd0, 4'd15: e_s = 4'd0;
                    default: e_s = step_bit(w_rl, egcnt[w_sh +: 3]) ? 4'd4 : 4'd0;
                endcase
                if (e_s != 0)
                    e_v = (e_v > ((e_v >> e_s) + 8'd1)) ? (e_v - (e_v >> e_s) - 8'd1) : 8'd0;
            end
        end else begin
            if (w_rh != 0 && ((egcnt & e_mask) == 16'd0)) begin
                case (w_rh)
                    4'd13: e_s = {3'b000, step_bit(w_rl, {egcnt[3:2], egcnt[0]})};
                    4'd14: e_s = {3'b000, step_bit(w_rl, {egcnt[3:2], 1'b0})} + 4'd1;
                    4'd15: e_s = 4'd2;
                    default: e_s = {3'b000, step_bit(w_rl, egcnt[w_sh +: 3])};
                endcase
                e_v = (e_v + {4'b0, e_s} > 8'd127) ? 8'd127 : (e_v + {4'b0, e_s});
            end
        end
        e_eo = e_v[6:0]; e_st = w_st; e_egreq = 1'b0; e_reset = 1'b0;
        e_ars = {1'b0, q_ar} + {3'b000, w_rks[3:2]};
        case (w_st)
            DAMP: if (e_eo >= 7'd123 && ((egcnt & e_mask) == 16'd0)) begin
                if (e_ars >= 5'd15) begin e_st = DECAY; e_eo = 7'd0; end
                else e_st = ATTACK;
                e_egreq = 1'b1;
                e_reset = sl;
            end
            ATTACK: if (e_eo == 7'd0) begin e_st = DECAY; e_egreq = 1'b1; end
            DECAY:  if (e_eo[6:3] == q_sl) begin e_st = SUSTAIN; e_egreq = 1'b1; end
            default: ;
        endcase
        if (test[0]) e_eo = 7'd0;
    end

    // ------------------------------------------------------------------ operator output
    reg  [7:0] sin_a = 8'd0;  wire [11:0] sin_q;
    reg  [7:0] exp_a = 8'd0;  wire [9:0]  exp_q;
    vrc7_sinrom u_sin (.clk(clk), .a(sin_a), .q(sin_q));
    vrc7_exprom u_exp (.clk(clk), .a(exp_a), .q(exp_q));

    reg [9:0]  pg_m, pg_c;            // phase outputs of this channel's slots
    reg [9:0]  wx;                    // wave index of the operator in flight
    reg        wws;
    reg [10:0] att;
    reg        mute;
    reg        hhalf;
    reg [15:0] hi;
    reg signed [15:0] acc = 16'sd0;

    function [10:0] attn;
        input [6:0] eov; input [7:0] tl; input [3:0] amv;
        reg [8:0] a;
        begin a = {2'b0, eov} + {1'b0, tl} + {5'b0, amv}; attn = (a > 9'd127) ? {7'd127, 4'd0} : {a[6:0], 4'd0}; end
    endfunction

    // linear operator output of the exponent lookup in flight
    wire [10:0] lt = {1'b0, exp_q} + 11'd1024;
    wire [10:0] lr = (hi[14:8] >= 7'd11) ? 11'd0 : (lt >> hi[14:8]);
    wire signed [13:0] lpos = $signed({2'b00, lr, 1'b0});
    wire signed [13:0] lout = mute ? 14'sd0 : (hi[15] ? (-lpos - 14'sd2) : lpos);
    // modulator feedback
    wire signed [14:0] fbsum = o1[ch] + o0[ch];
    wire signed [14:0] fbsh  = fbsum >>> (4'd9 - {1'b0, m_fb});
    wire [9:0] fmv = (m_fb != 3'd0) ? fbsh[9:0] : 10'd0;
    wire signed [15:0] lout16 = lout;
    wire signed [15:0] chout = (-lout16) >>> 1;

    // ------------------------------------------------------------------ write queue
    reg [15:0] fifo [0:7];
    reg [2:0]  fw = 3'd0, fr = 3'd0;
    reg [3:0]  fcount = 4'd0;
    reg        tick_pend = 1'b0;
    wire       push = wr && fcount != 4'd8;

    localparam S_IDLE = 4'd0, S_GLOB = 4'd1, S_COMMIT = 4'd2, S_ENV = 4'd3,
               S_O0 = 4'd4, S_O1 = 4'd5, S_O2 = 4'd6, S_O3 = 4'd7, S_O4 = 4'd8, S_NEXT = 4'd9,
               S_LOAD = 4'd10, S_PH = 4'd11, S_STORE = 4'd12;
    reg [3:0] fsm = S_IDLE;
    reg       pop;
    reg [7:0] r, d;
    integer c;

    always @(posedge clk) begin
        valid <= 1'b0;
        pop = 1'b0;
        if (push) begin fifo[fw] <= {wreg, wdata}; fw <= fw + 3'd1; end
        if (tick) tick_pend <= 1'b1;
        if (rst) begin
            for (k = 0; k < 8; k = k + 1) up[k] <= 8'd0;
            for (k = 0; k < 6; k = k + 1) begin
                r10[k] <= 8'd0; r20[k] <= 8'd0; r30[k] <= 8'd0; o0[k] <= 14'sd0; o1[k] <= 14'sd0;
            end
            for (k = 0; k < 12; k = k + 1) begin
                ph[k] <= 19'd0; eo[k] <= 7'd127; st[k] <= RELEASE; pend[k] <= 4'hF;
                rh[k] <= 4'd0; rl[k] <= 2'd0; sh[k] <= 4'd0; tll[k] <= 8'd0; rks[k] <= 4'd0;
                ws[k] <= 1'b0; keyf[k] <= 1'b0; susf[k] <= 1'b0;
            end
            test <= 8'd0; kst <= 6'd0; pmph <= 13'd0; amsub <= 6'd0; amidx <= 8'd0; egcnt <= 16'd0;
            fsm <= S_IDLE; fw <= 3'd0; fr <= 3'd0; tick_pend <= 1'b0; sample <= 16'sd0;
        end else begin
            case (fsm)
            S_IDLE:
                if (fcount != 4'd0) begin
                    // ------------------------------------------------ apply one register write
                    pop = 1'b1;
                    r = fifo[fr][15:8]; d = fifo[fr][7:0];
                    fr <= fr + 3'd1;
                    if ((r >= 8'h19 && r <= 8'h1f) || (r >= 8'h29 && r <= 8'h2f) || (r >= 8'h39 && r <= 8'h3f))
                        r = r - 8'd9;
                    if (r <= 8'h07) begin
                        up[r[2:0]] <= d;
                        for (c = 0; c < 6; c = c + 1) if (r30[c][7:4] == 4'd0) case (r[2:0])
                            3'd0: pend[c*2]   <= pend[c*2]   | 4'b1100;             // MOD RKS|EG
                            3'd1: pend[c*2+1] <= pend[c*2+1] | 4'b1100;             // CAR RKS|EG
                            3'd2: pend[c*2]   <= pend[c*2]   | 4'b0010;             // MOD TLL
                            3'd3: begin pend[c*2] <= pend[c*2] | 4'b0011; pend[c*2+1] <= pend[c*2+1] | 4'b0011; end
                            3'd4, 3'd6: pend[c*2] <= pend[c*2] | 4'b1000;           // MOD EG
                            default:    pend[c*2+1] <= pend[c*2+1] | 4'b1000;       // CAR EG
                        endcase
                    end else if (r == 8'h0f) test <= d;
                    else if (r >= 8'h10 && r <= 8'h15) begin
                        r10[r[2:0]] <= d;
                        pend[{r[2:0], 1'b0}] <= pend[{r[2:0], 1'b0}] | 4'b1110;
                        pend[{r[2:0], 1'b1}] <= pend[{r[2:0], 1'b1}] | 4'b1110;
                    end else if (r >= 8'h20 && r <= 8'h25) begin
                        r20[r[2:0]] <= d;
                        susf[{r[2:0], 1'b1}] <= d[5];
                        pend[{r[2:0], 1'b0}] <= pend[{r[2:0], 1'b0}] | 4'b1110;
                        pend[{r[2:0], 1'b1}] <= pend[{r[2:0], 1'b1}] | 4'b1110;
                        if (d[4] != kst[r[2:0]]) begin
                            kst[r[2:0]] <= d[4];
                            keyf[{r[2:0], 1'b0}] <= d[4]; keyf[{r[2:0], 1'b1}] <= d[4];
                            st[{r[2:0], 1'b1}] <= d[4] ? DAMP : RELEASE;
                            if (d[4]) st[{r[2:0], 1'b0}] <= DAMP;
                        end
                    end else if (r >= 8'h30 && r <= 8'h35) begin
                        r30[r[2:0]] <= d;
                        pend[{r[2:0], 1'b0}] <= 4'hF; pend[{r[2:0], 1'b1}] <= 4'hF;
                    end
                end else if (tick_pend) begin
                    tick_pend <= tick;
                    fsm <= S_GLOB;
                end
            S_GLOB: begin
                if (test[1]) begin pmph <= 13'd0; amsub <= 6'd0; amidx <= 8'd0; end
                else if (test[3]) begin
                    pmph <= pmph + 13'd1024; amidx <= (amidx == 8'd209) ? 8'd0 : amidx + 8'd1;
                end else begin
                    pmph <= pmph + 13'd1;
                    amsub <= amsub + 6'd1;
                    if (amsub == 6'd63) amidx <= (amidx == 8'd209) ? 8'd0 : amidx + 8'd1;
                end
                egcnt <= egcnt + 16'd1;
                ch <= 3'd0; sl <= 1'b0; acc <= 16'sd0;
                fsm <= S_LOAD;
            end
            S_LOAD: begin
                w_ph <= ph[cur]; w_eo <= eo[cur]; w_st <= st[cur]; w_pend <= pend[cur]; w_rh <= rh[cur];
                w_rl <= rl[cur]; w_sh <= sh[cur]; w_tll <= tll[cur]; w_rks <= rks[cur]; w_ws <= ws[cur];
                w_key <= keyf[cur]; w_sus <= susf[cur];
                q_pm <= f_pm; q_eg <= f_eg; q_kr <= f_kr; q_ws <= f_ws; q_ml <= f_ml; q_ar <= f_ar;
                q_dr <= f_dr; q_sl <= f_sl; q_rr <= f_rr; q_tl <= f_tl; q_klp <= klp; q_fnum <= fnum; q_blk <= blk;
                fsm <= S_COMMIT;
            end
            S_COMMIT: begin
                w_pend <= c_pend; w_rh <= c_rh; w_rl <= c_rl; w_sh <= c_sh;
                w_tll <= c_tll; w_rks <= c_rks; w_ws <= c_ws;
                w_inc <= e_inc[18:0];
                fsm <= S_ENV;
            end
            S_ENV: begin
                w_eo <= e_eo; w_st <= e_st; w_reset <= e_reset;
                if (e_egreq) w_pend <= w_pend | 4'b1000;
                fsm <= S_PH;
            end
            S_PH: begin
                w_ph <= ((w_reset || test[2]) ? 19'd0 : w_ph) + w_inc;
                fsm <= S_STORE;
            end
            S_STORE: begin
                ph[cur] <= w_ph; eo[cur] <= w_eo; st[cur] <= w_st; pend[cur] <= w_pend; rh[cur] <= w_rh;
                rl[cur] <= w_rl; sh[cur] <= w_sh; tll[cur] <= w_tll; rks[cur] <= w_rks; ws[cur] <= w_ws;
                if (w_reset) ph[im] <= 19'd0;                        // carrier start resets both phases
                if (sl) begin pg_c <= w_ph[18:9]; sl <= 1'b0; fsm <= S_O0; end
                else    begin pg_m <= w_ph[18:9]; sl <= 1'b1; fsm <= S_LOAD; end
            end
            S_O0: begin
                // wave index, attenuation, sine address (quarter-wave symmetry)
                wx  = sl ? (pg_c + o0[ch][9:0]) : (pg_m + fmv);
                wws <= ws[cur];
                att <= attn(eo[cur], tll[cur], (sl ? c_am : b0[7]) ? lfo_am : 4'd0);
                mute <= (eo[cur] > 7'd123);
                sin_a <= wx[8] ? ~wx[7:0] : wx[7:0];
                hhalf <= ws[cur] & wx[9];
                hi[15] <= wx[9] & ~ws[cur];
                fsm <= S_O1;
            end
            S_O1: fsm <= S_O2;                                       // sine ROM latency
            S_O2: begin
                hi <= (hhalf ? 16'h0FFF : {hi[15], 3'b000, sin_q}) + {5'b0, att};
                exp_a <= ((hhalf ? 8'hFF : sin_q[7:0]) + att[7:0]) ^ 8'hFF;
                fsm <= S_O3;
            end
            S_O3: fsm <= S_O4;                                       // exponent ROM latency
            S_O4: begin
                if (!sl) begin
                    o1[ch] <= o0[ch]; o0[ch] <= lout;
                    sl <= 1'b1; fsm <= S_O0;
                end else begin
                    acc <= acc + chout;
                    fsm <= S_NEXT;
                end
            end
            S_NEXT: begin
                if (ch == 3'd5) begin sample <= acc; valid <= 1'b1; fsm <= S_IDLE; end
                else begin ch <= ch + 3'd1; sl <= 1'b0; fsm <= S_LOAD; end
            end
            default: fsm <= S_IDLE;
            endcase
            fcount <= fcount + (push ? 4'd1 : 4'd0) - (pop ? 4'd1 : 4'd0);
        end
        if (rst) fcount <= 4'd0;
    end
endmodule
