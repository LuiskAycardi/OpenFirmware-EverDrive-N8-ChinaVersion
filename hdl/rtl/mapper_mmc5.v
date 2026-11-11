`timescale 1ns/1ps
// mapper_mmc5.v — Nintendo MMC5 (mapper 5). Implementación propia (clean room), RBF 103.
//
// Hechos de NESdev Wiki (registros y bits) y de cómo el N8 aloja la ExRAM/nametables (leído de la fuente de Krikzz
// `ref/krikzz-n8-dev/x/mmc5-src` SOLO para entender el reparto de señales del N8; nada copiado). El Verilog es propio.
//
// Incluye bancos PRG/CHR, ExRAM de 1KB (M4K), fill, atributos extendidos,
// selección A/B por PPUCTRL y fase de fetch, detector de scanline, IRQ y audio.
// Split: NT/paleta y banco CHR implementados; la sustitución de fine-Y no es
// realizable con este mapa externo de SRAM (A0..A9 llegan directos de la NES).
// Ver docs/fase4-mappers.md: alcance de validación y diferencias aún abiertas.
//
// Registros ($5000-$5FFF, decodificados con A14-A13 = 10 y A12 = 1, es decir $5xxx):
//   $5100 modo PRG (1:0): 0=32K, 1=2x16K, 2=16K+8K+8K, 3=4x8K. Reset %11.
//   $5101 modo CHR (1:0): 0=8K, 1=4K, 2=2K, 3=1K.
//   $5102/$5103 protección PRG-RAM: escritura habilitada solo con $5102=%10 y $5103=%01.
//   $5104 modo ExRAM (1:0). $5105 mapeo de nametables (4 campos de 2 bits). $5106/$5107 tile/color del fill.
//   $5113-$5117 banca PRG (bit7 ROM/RAM en 5114-5116; 5113 siempre RAM; 5117 siempre ROM, reset $FF).
//   $5120-$5127 CHR sprites (o fondo en 8x8); $5128-$512B CHR fondo en 8x16; $5130 bits altos (9:8) de CHR.
//   $5203 línea de comparación IRQ; $5204 estado/activación IRQ (bit7). $5205/$5206 multiplicando/multiplicador.

module mapper_mmc5 (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,
    input  wire        ppu_wr_n,
    input wire [7:0] ppu_din,
    output wire [7:0] ppu_dout, ppu_doe,
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
    output wire        chr_raw,
    output wire [7:0]  cpu_dout,       // $5205/$5206 (producto), $5204 (estado IRQ), $5C00-$5FFF (ExRAM, futuro)
    output wire [7:0]  cpu_doe,
    output wire [9:0]  snd             // audio (futuro): nivel 0-1023; de momento 0
);

    wire audio_irq, split_active;
    wire [7:0] ex_ppu_q;
    // ------------------------------------------------------------ registros
    reg [1:0]  prg_mode, chr_mode;
    reg [1:0]  ram_prot1, ram_prot2;
    reg [1:0]  exram_mode;
    reg [7:0]  nt_map;                 // $5105
    reg [7:0]  fill_tile;
    reg [1:0]  fill_color;
    reg [7:0]  prg_bank [0:4];         // $5113-$5117 (índice 0..4)
    reg [9:0]  chr_a_set [0:7];        // $5120-$5127
    reg [9:0]  chr_b_set [0:3];        // $5128-$512B
    reg [1:0]  chr_hi;                 // $5130 (bits 9:8)
    reg sprite8x16 = 0;
    reg [7:0] split_ctrl=0, split_scroll=0, split_bank=0;
    reg        last_bg;               // 1 si la última escritura de CHR fue al juego de fondo ($5128-$512B)
    reg [7:0]  irq_line;               // $5203
    reg        irq_en;                 // $5204 bit7
    reg [7:0]  mul_a, mul_b;           // $5205/$5206
    integer i;

    initial begin
        prg_mode = 2'b11; chr_mode = 0; ram_prot1 = 2'b01; ram_prot2 = 2'b10; exram_mode = 2'b11;
        nt_map = 0; fill_tile = 0; fill_color = 0;
        for (i=0;i<5;i=i+1) prg_bank[i] = 0;
        prg_bank[4] = 8'hFF;           // $5117 reset $FF
        for (i=0;i<8;i=i+1) chr_a_set[i] = 0;
        for (i=0;i<4;i=i+1) chr_b_set[i] = 0;
        chr_hi = 0; last_bg = 0; irq_line = 0; irq_en = 0; mul_a = 0; mul_b = 0;
    end

    // escritura en $5000-$5FFF: A14-A13 = 2'b10 (es $4000-$5FFF) y A12 = 1 (es $5xxx)
    wire reg_sel = romsel_n && (cpu_a[14:13] == 2'b10) && cpu_a[12];
    wire reg_wr  = reg_sel && !cpu_rw;
    wire [11:0] ra = cpu_a[11:0];      // dirección dentro de $5000-$5FFF

    always @(negedge m2) begin
        if (rst) sprite8x16 <= 0;
        else if (romsel_n && !cpu_rw && cpu_a[14:13]==2'b01 && cpu_a[2:0]==0)
            sprite8x16 <= cpu_d[5];
    end

    always @(negedge m2) begin
        if (rst) begin
            prg_mode <= 2'b11; chr_mode <= 0; ram_prot1 <= 2'b01; ram_prot2 <= 2'b10; exram_mode <= 2'b11;
            nt_map <= 0; fill_tile <= 0; fill_color <= 0;
            split_ctrl<=0; split_scroll<=0; split_bank<=0;
            for (i=0;i<5;i=i+1) prg_bank[i] <= 0;
            prg_bank[4] <= 8'hFF;
            for (i=0;i<8;i=i+1) chr_a_set[i] <= 0;
            for (i=0;i<4;i=i+1) chr_b_set[i] <= 0;
            chr_hi <= 0; last_bg <= 0; irq_line <= 0; irq_en <= 0; mul_a <= 0; mul_b <= 0;
        end else if (reg_wr) begin
            case (ra)
                12'h100: prg_mode  <= cpu_d[1:0];
                12'h101: chr_mode  <= cpu_d[1:0];
                12'h102: ram_prot1 <= cpu_d[1:0];
                12'h103: ram_prot2 <= cpu_d[1:0];
                12'h104: exram_mode<= cpu_d[1:0];
                12'h105: nt_map    <= cpu_d;
                12'h106: fill_tile <= cpu_d;
                12'h107: fill_color<= cpu_d[1:0];
                12'h113: prg_bank[0] <= cpu_d;
                12'h114: prg_bank[1] <= cpu_d;
                12'h115: prg_bank[2] <= cpu_d;
                12'h116: prg_bank[3] <= cpu_d;
                12'h117: prg_bank[4] <= cpu_d;
                12'h130: chr_hi    <= cpu_d[1:0];
                12'h200: split_ctrl <= cpu_d;
                12'h201: split_scroll <= cpu_d;
                12'h202: split_bank <= cpu_d;
                12'h203: irq_line  <= cpu_d;
                12'h204: irq_en    <= cpu_d[7];
                12'h205: mul_a     <= cpu_d;
                12'h206: mul_b     <= cpu_d;
                default: ;
            endcase
            if (ra[11:4] == 8'h12 && ra[3] == 1'b0) begin           // $5120-$5127
                chr_a_set[ra[2:0]] <= {chr_hi, cpu_d}; last_bg <= 1'b0;
            end
            if (ra[11:2] == 10'b0001_0010_10) begin                 // $5128-$512B
                chr_b_set[ra[1:0]] <= {chr_hi, cpu_d}; last_bg <= 1'b1;
            end
        end
    end

    // PPU reads are sampled in the 50 MHz domain; never use /RD as a clock.
    reg [2:0] rd_sync=3'b111, m2_sync=0;
    reg [13:0] last_read=0;
    reg [1:0] repeated_nt=0, idle_cpu=0;
    reg [7:0] scanline=0;
    reg irq_pend=0, in_frame=0, need_frame=0;
    reg [5:0] tile_fetch=0;
    reg read_consumed=0;
    reg [9:0] nt_offset=0;
    wire read_event = rd_sync[2:1]==2'b10;
    wire cpu_tick = m2_sync[2:1]==2'b01;
    wire nt_tile = ppu_a[13:12]==2'b10 && ppu_a[9:6]!=4'hf;
    wire [5:0] fetch_index=tile_fetch + ((nt_tile && !read_consumed)?6'd1:6'd0);
    wire attr_fetch = ppu_a[13:12]==2'b10 && ppu_a[9:6]==4'hf;
    wire rd_5204 = reg_sel && cpu_rw && ra==12'h204;
    reg ack_toggle=0;
    always @(negedge m2) if (rd_5204 && !rst) ack_toggle<=~ack_toggle;
    reg [2:0] ack_sync=0;
    wire nmi_vector = !romsel_n && cpu_rw && (cpu_a==15'h7ffa || cpu_a==15'h7ffb);
    always @(posedge clk) begin
        rd_sync<={rd_sync[1:0],ppu_rd_n}; m2_sync<={m2_sync[1:0],m2};
        ack_sync<={ack_sync[1:0],ack_toggle};
        if(ppu_rd_n) read_consumed<=0;
        else if(read_event) read_consumed<=1;
        if(rst || nmi_vector) begin
            scanline<=0; in_frame<=0; irq_pend<=0; repeated_nt<=0;
            need_frame<=0; idle_cpu<=0; last_read<=0; tile_fetch<=0; nt_offset<=0;
        end else begin
            if(ack_sync[2]!=ack_sync[1]) irq_pend<=0;
            if(cpu_tick) begin
                if(idle_cpu<3) idle_cpu<=idle_cpu+1'b1;
                if(idle_cpu>=2) begin in_frame<=0; need_frame<=0; repeated_nt<=0; end
            end
            if(read_event) begin
                idle_cpu<=0;
                if(nt_tile) begin
                    nt_offset<=ppu_a[9:0];
                    tile_fetch<=tile_fetch+1'b1;
                    if(need_frame) begin in_frame<=1; need_frame<=0; end
                end
                // Three equal NT reads arm a line; the following read clocks it.
                if(repeated_nt==2) begin
                    if(!in_frame && !need_frame) begin need_frame<=1; scanline<=0; end
                    else begin
                        scanline<=scanline+1'b1;
                        if(scanline+8'd1==irq_line) irq_pend<=1;
                    end
                end else if(ppu_a[13:12]==2'b10 && last_read==ppu_a) begin
                    repeated_nt<=repeated_nt+1'b1;
                    if(repeated_nt==1) tile_fetch<=0;
                end
                if(last_read!=ppu_a) repeated_nt<=0;
                last_read<=ppu_a;
            end
        end
    end
    assign irq = (irq_pend && irq_en) | audio_irq;

    // ------------------------------------------------------------ banca PRG
    // ventana actual por cpu_a[14:13]: 0=$8000,1=$A000,2=$C000,3=$E000
    wire [1:0] win = cpu_a[14:13];
    reg [7:0]  pbk;                    // registro de banco elegido
    reg        is_ram;                 // la ventana es RAM (bit7=0 en 5114-5116, o $6000 con 5113)
    reg [1:0]  wsize;                  // 0=8K,1=16K,2=32K (de la ventana actual)
    always @(*) begin
        pbk = prg_bank[4]; is_ram = 0; wsize = 0;
        case (prg_mode)
            2'd0: begin pbk = prg_bank[4]; wsize = 2'd2; is_ram = 0; end                 // 32K: $5117
            2'd1: begin                                                                   // 2x16K
                if (!cpu_a[14]) begin pbk = prg_bank[2]; is_ram = ~prg_bank[2][7]; end     // $8000: $5115
                else            begin pbk = prg_bank[4]; is_ram = 0; end                   // $C000: $5117
                wsize = 2'd1;
            end
            2'd2: begin                                                                   // 16K+8K+8K
                if (!cpu_a[14]) begin pbk = prg_bank[2]; is_ram = ~prg_bank[2][7]; wsize = 2'd1; end  // $8000 16K: $5115
                else if (win == 2'd2) begin pbk = prg_bank[3]; is_ram = ~prg_bank[3][7]; wsize = 2'd0; end // $C000: $5116
                else begin pbk = prg_bank[4]; is_ram = 0; wsize = 2'd0; end                // $E000: $5117
            end
            2'd3: begin                                                                   // 4x8K
                wsize = 2'd0;
                case (win)
                    2'd0: begin pbk = prg_bank[1]; is_ram = ~prg_bank[1][7]; end           // $8000: $5114
                    2'd1: begin pbk = prg_bank[2]; is_ram = ~prg_bank[2][7]; end           // $A000: $5115
                    2'd2: begin pbk = prg_bank[3]; is_ram = ~prg_bank[3][7]; end           // $C000: $5116
                    2'd3: begin pbk = prg_bank[4]; is_ram = 0; end                         // $E000: $5117
                endcase
            end
        endcase
    end

    // $6000-$7FFF siempre RAM por $5113
    wire win_6000 = romsel_n && (cpu_a[14:13] == 2'b11);
    wire [7:0] bank6 = prg_bank[0];
    // dirección PRG de 8 KB: según el tamaño de ventana, los bits bajos vienen de la CPU
    reg [6:0] pa8;                     // página de 8 KB (A19..A13 → usamos A18..A13 para el N8)
    always @(*) begin
        case (wsize)
            2'd1: pa8 = {pbk[6:1], cpu_a[13]};             // 16K: bit0 ignorado, A13 de la CPU
            2'd2: pa8 = {pbk[6:2], cpu_a[14:13]};          // 32K: A14-A13 de la CPU
            default: pa8 = pbk[6:0];                        // 8K
        endcase
    end

    assign prg_rom_en = (!romsel_n && !is_ram) ;
    assign prg_ram_en = ((!romsel_n && is_ram) || (win_6000)) && m2;
    wire wr_ok = (ram_prot1 == 2'b10) && (ram_prot2 == 2'b01);
    assign prg_wr = !cpu_rw && prg_ram_en && wr_ok;
    assign prg_a  = win_6000 ? {3'd0, bank6[2:0], cpu_a[12:10]}        // $6000 8K: $5113
                              : is_ram ? {3'd0,pa8[2:0],cpu_a[12:10]} : {pa8[5:0], cpu_a[12:10]};

    // ------------------------------------------------------------ banca CHR
    wire [2:0] s = ppu_a[12:10];
    reg [9:0] cbk;
    wire use_b = sprite8x16 && (in_frame ? (fetch_index<32 || fetch_index>=40) : last_bg);

    always @(*) begin
        // juego de registros: en 8x8 siempre A; en 8x16, sprites=A, fondo=B (simplificado con last_bg)
        // tamaño CHR: elige qué registro y cuántos bits bajos pasan de ppu_a
        case (chr_mode)
            2'd0: cbk = chr_a_set[7];                         // 8K
            2'd1: cbk = ppu_a[12] ? chr_a_set[7] : chr_a_set[3];   // 4K
            2'd2: cbk = chr_a_set[{ppu_a[12:11],1'b1}];      // 2K: 1,3,5,7
            default: cbk = chr_a_set[ppu_a[12:10]];          // 1K
        endcase
        if(use_b) case(chr_mode)
            0,1: cbk=chr_b_set[3];
            2: cbk=ppu_a[10+1] ? chr_b_set[3] : chr_b_set[1];
            3: cbk=chr_b_set[ppu_a[11:10]];
        endcase
    end
    reg [8:0] chr_page;                // página 1 KB (A18..A10)
    always @(*) begin
        case (chr_mode)
            2'd0: chr_page = {cbk[5:0], ppu_a[12:10]};       // 8K
            2'd1: chr_page = {cbk[6:0], ppu_a[11:10]};       // 4K
            2'd2: chr_page = {cbk[7:0], ppu_a[10]};          // 2K
            default: chr_page = cbk[8:0];                    // 1K
        endcase
    end
    wire bg_fetch = in_frame && (fetch_index<32 || fetch_index>=40);
    wire extended = exram_mode==1 && bg_fetch;
    wire [8:0] extended_page={chr_hi[0],ex_ppu_q[5:0],ppu_a[11:10]};
    // Split CHR bank is representable; fine-Y substitution is constrained by
    // the board wiring (SRAM A0..A9 are direct NES signals). See documentation.
    assign chr_a = split_active ? {split_bank[6:0],ppu_a[11:10]} :
                   extended ? extended_page : chr_page;
    assign chr_en  = !ppu_a[13];
    assign chr_wr  = cfg[7] && !ppu_wr_n && !ppu_a[13];      // CHR-RAM si la cabecera lo pide
    assign chr_raw = 1'b0;

    // 1 KB ExRAM in two M4Ks, avoiding a reserved CHR-SRAM page and preserving
    // simultaneous CPU/PPU addressability. RAM is not cleared by console reset.
    wire cpu_ex_sel=reg_sel && cpu_a[11:10]==2'b11;
    reg [1:0] ex_write_guard=0;
    wire cpu_write_now=cpu_ex_sel && !cpu_rw && m2;
    always @(posedge clk) ex_write_guard<={ex_write_guard[0],cpu_write_now};
    wire cpu_ex_write=cpu_write_now && (&ex_write_guard) && exram_mode!=3;
    wire [7:0] ex_cpu_q;
    wire [7:0] ex_cpu_data=(!exram_mode[1] && !in_frame) ? 8'd0 : cpu_d;
    wire [1:0] nt_field=(nt_map >> {ppu_a[11:10],1'b0});
    wire split_bg=in_frame && (fetch_index<32 || fetch_index>=40);
    wire [5:0] split_column=(fetch_index+6'd2)>=42 ? fetch_index-6'd40 : fetch_index+6'd2;
    wire [8:0] split_sum={1'b0,scanline}+{1'b0,split_scroll};
    wire [8:0] split_y=split_sum>=480 ? split_sum-480 : split_sum>=240 ? split_sum-240 : split_sum;
    wire split_region=split_ctrl[6] ? split_column>={1'b0,split_ctrl[4:0]} : split_column<{1'b0,split_ctrl[4:0]};
    assign split_active=split_ctrl[7] && !exram_mode[1] && split_bg && split_column<32 && split_region;
    wire split_fine_y_conflict=split_active && !ppu_a[13] && split_y[2:0]!=ppu_a[2:0];
    wire [9:0] split_tile={split_y[7:3],split_column[4:0]};
    wire [9:0] split_attr={4'b1111,split_tile[9:7],split_tile[4:2]};
    wire [9:0] ex_ppu_addr=split_active ? (attr_fetch ? split_attr : split_tile) :
                          extended ? (nt_tile ? ppu_a[9:0] : nt_offset) : ppu_a[9:0];
    wire ex_ppu_write=!ppu_wr_n && ppu_a[13] && nt_field==2 && !exram_mode[1];
    mmc5_exram exram(.clk(clk),.we_a(cpu_ex_write),.addr_a(cpu_a[9:0]),.d_a(ex_cpu_data),.q_a(ex_cpu_q),
                    .we_b(ex_ppu_write),.addr_b(ex_ppu_addr),.d_b(ppu_din),.q_b(ex_ppu_q));
    wire [1:0] split_palette=(ex_ppu_q >> {split_tile[6],split_tile[1],1'b0});
    wire nt_internal=ppu_a[13] && (nt_field[1] || split_active || (extended && attr_fetch));
    assign ciram_en=ppu_a[13] && !nt_internal;
    assign ciram_a10=nt_field[0];
    assign ppu_dout=split_active && ppu_a[13] ? (attr_fetch ? {4{split_palette}} : ex_ppu_q) :
                    extended && attr_fetch ? {4{ex_ppu_q[7:6]}} :
                    nt_field==3 ? (attr_fetch ? {4{fill_color}} : fill_tile) :
                    !exram_mode[1] ? ex_ppu_q : 8'd0;
    assign ppu_doe=nt_internal && !ppu_rd_n ? 8'hff : 8'h00;

    wire [15:0] prod = mul_a * mul_b;
    wire [7:0] audio_do,audio_oe;
    snd_mmc5 sound(.cpu_a(cpu_a),.cpu_d(cpu_d),.romsel_n(romsel_n),.cpu_rw(cpu_rw),
                   .m2(m2),.rst(rst),.snd(snd),.cpu_dout(audio_do),.cpu_doe(audio_oe),.irq(audio_irq));
    assign cpu_dout=audio_oe!=0 ? audio_do : cpu_ex_sel ? ex_cpu_q :
                   ra==12'h205 ? prod[7:0] : ra==12'h206 ? prod[15:8] :
                   ra==12'h204 ? {irq_pend,in_frame,6'd0} : 8'd0;
    assign cpu_doe=audio_oe | ((reg_sel && cpu_rw) ?
                   ((ra==12'h205 || ra==12'h206) ? 8'hff :
                    ra==12'h204 ? 8'hc0 : cpu_ex_sel && exram_mode[1] ? 8'hff : 8'd0) : 8'd0);
endmodule
