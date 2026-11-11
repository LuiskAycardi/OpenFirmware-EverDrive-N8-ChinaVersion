`timescale 1ns/1ps
// Nintendo World Championships mapper105. Own extension of our MMC1 serial logic.
// DIP defaults to zero, matching Mesen2; alternate physical switches are a build parameter.
// Counter is tested at the terminal boundary rather than simulating five minutes.
module mapper_nwc105 #(parameter [3:0] TIMER_DIP=0) (
    input  wire [14:0] cpu_a,
    input  wire [7:0]  cpu_d,
    input  wire        romsel_n,
    input  wire        cpu_rw,
    input  wire        m2,
    input  wire [13:0] ppu_a,
    input  wire        ppu_rd_n,   // PPU /RD (solo lo usa el MMC2/MMC4)
    input  wire        ppu_wr_n,
    input  wire [7:0]  cfg,
    input  wire        rst,
    input  wire        clk,        // reloj del sistema (sin uso en este mapper)
    input  wire [7:0]  map_id,     // número de mapper (variantes de una misma familia)

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

    reg [1:0] init_stage=0;
    reg [29:0] timer_count=0;
    reg timer_pending=0;
    localparam [29:0] TIMER_LIMIT=30'h20000000 | ({26'd0,TIMER_DIP} <<25);
    reg [4:0] ctrl, chr0, chr1, prg;
    reg [4:0] shift;
    reg [2:0] count;
    reg       prev_wr;      // el ciclo anterior fue una escritura en $8000+

    initial begin
        ctrl = 5'h0C; chr0 = 5'h10; chr1 = 5'd0; prg = 5'd0;
        shift = 5'd0; count = 3'd0; prev_wr = 1'b0;
    end

    wire rom_wr = !romsel_n && !cpu_rw;
    wire [4:0] value = {cpu_d[0], shift[4:1]};

    always @(negedge m2) begin
        prev_wr <= rom_wr;
        if(rst) begin init_stage<=0;timer_count<=0;timer_pending<=0;end
        else if(chr0[4])begin timer_count<=0;timer_pending<=0;end
        else if(!timer_pending)begin
            if(timer_count==TIMER_LIMIT-1'b1)timer_pending<=1;
            else timer_count<=timer_count+1'b1;
        end
        if (rst) begin
            ctrl  <= 5'h0C;
            chr0  <= 5'h10;
            chr1  <= 5'd0;
            prg   <= 5'd0;
            shift <= 5'd0;
            count <= 3'd0;
        end else if (rom_wr && !prev_wr) begin
            if (cpu_d[7]) begin
                shift <= 5'd0;
                count <= 3'd0;
                ctrl  <= ctrl | 5'h0C;
            end else if (count == 3'd4) begin
                case (cpu_a[14:13])
                    2'd0: ctrl <= value;
                    2'd1: begin
                        chr0 <= value;
                        if(init_stage==0 && !value[4])init_stage<=1;
                        else if(init_stage==1 && value[4])init_stage<=2;
                        if(value[4])begin timer_count<=0;timer_pending<=0;end
                    end
                    2'd2: chr1 <= value;
                    2'd3: prg  <= value;
                endcase
                shift <= 5'd0;
                count <= 3'd0;
            end else begin
                shift <= value;
                count <= count + 3'd1;
            end
        end
    end

    // ---------------------------------------------------------------- PRG
    reg [3:0] bank16;
    always @*begin
        bank16={3'd0,cpu_a[14]};
        if(init_stage==2)begin
            if(!chr0[3])bank16={1'b0,chr0[2:1],cpu_a[14]};
            else case(ctrl[3:2])
                2: bank16=cpu_a[14] ? {1'b1,prg[2:0]} : 4'd8;
                3: bank16=cpu_a[14] ? 4'd15 : {1'b1,prg[2:0]};
                default:bank16={1'b1,prg[2:1],cpu_a[14]};
            endcase
        end
    end
    wire win_6000=romsel_n && cpu_a[14:13]==3;
    assign prg_a=romsel_n ? {6'd0,cpu_a[12:10]} : {1'b0,bank16,cpu_a[13:10]};
    assign prg_rom_en=!romsel_n;
    assign prg_ram_en=win_6000 && m2 && !prg[4];
    assign prg_wr=prg_ram_en && !cpu_rw;
    assign chr_a={6'd0,ppu_a[12:10]};
    assign chr_en=!ppu_a[13];
    assign chr_wr=!ppu_a[13] && !ppu_wr_n;

    // ---------------------------------------------------------------- mirroring
    reg a10;
    always @(*) begin
        case (ctrl[1:0])
            2'd0: a10 = 1'b0;
            2'd1: a10 = 1'b1;
            2'd2: a10 = ppu_a[10];
            2'd3: a10 = ppu_a[11];
        endcase
    end

    assign ciram_en  = ppu_a[13];
    assign ciram_a10 = a10;
    assign irq       = timer_pending;

endmodule
