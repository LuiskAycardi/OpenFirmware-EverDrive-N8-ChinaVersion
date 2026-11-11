`timescale 1ns/1ps
// eeprom_24c0x.v — serial EEPROM of the Bandai LZ93D50 boards (mappers 16 and 159).
// Own implementation from the X24C01/X24C02 data sheet protocol and the NESdev "Bandai FCG board"
// notes; the step-by-step behaviour (incl. its simplifications) matches Mesen2, the bench oracle.
//
// The CPU bit-bangs the bus by writing SCL/SDA; each write is one sample (ev). Per sample:
//   START: SDA falls while SCL stays high.  STOP: SDA rises while SCL stays high.
//   otherwise an SCL rise shifts a bit in/out and an SCL fall advances the protocol.
// c01 = 0 (24C02, 256 bytes): START, chip address 1010xxxR (MSB first), word address, then
//   sequential write or read; the master's ACK after a read byte loads the next one.
// c01 = 1 (24C01, 128 bytes): START, 7-bit word address + R/W bit (LSB first), one data byte.
// Contents live in one M4K (256 x 8), all zero at power-on. They are not kept across power-off,
// and the N8 OS reloads the RBF on every game start, which clears them too: saves last for one
// play session. The serial output starts at 0 until the first START/STOP.
module eeprom_24c0x (
    input  wire clk,
    input  wire rst,
    input  wire c01,      // 1 = 24C01 protocol, 0 = 24C02
    input  wire ev,       // one-clk pulse: a new SCL/SDA sample
    input  wire scl,
    input  wire sda,
    output reg  out = 1'b0     // 0 until the first START/STOP (as the bench oracle)
);
    localparam IDLE = 3'd0, CHIP = 3'd1, ADDR = 3'd2, READ = 3'd3, WRITE = 3'd4, SACK = 3'd5, WACK = 3'd6;
    reg [2:0] mode = IDLE, nmode = IDLE;
    reg [7:0] chip = 0, addr = 0, data = 0;
    reg [3:0] cnt = 0;
    reg       pscl = 0, psda = 0;

    // ---- storage: single-port, synchronous (infers an M4K)
    reg [7:0] mem [0:255];
    integer k;
    initial for (k = 0; k < 256; k = k + 1) mem[k] = 8'h00;
    reg [7:0] ram_a = 0, ram_d = 0, ram_q = 0;
    reg       ram_we = 0;
    always @(posedge clk) begin
        if (ram_we) mem[ram_a] <= ram_d;
        ram_q <= mem[ram_a];
    end
    reg ld1 = 0, ld2 = 0;                 // data <= mem[addr] two clocks after a load request

    wire start = pscl && scl && psda && !sda;
    wire stop  = pscl && scl && !psda && sda;
    wire rise  = !pscl && scl;
    wire fall  = pscl && !scl;
    wire [2:0] msb = 3'd7 - cnt[2:0];     // 24C02 shifts MSB first, 24C01 LSB first

    always @(posedge clk) begin
        ram_we <= 1'b0;
        ld2 <= ld1; ld1 <= 1'b0;
        if (ld2) data <= ram_q;
        if (rst) begin
            mode <= IDLE; nmode <= IDLE; cnt <= 0; out <= 1'b0; pscl <= 0; psda <= 0;
            ld1 <= 0; ld2 <= 0;
        end else if (ev) begin
            pscl <= scl; psda <= sda;
            if (start) begin
                mode <= c01 ? ADDR : CHIP; cnt <= 0; out <= 1'b1;
                if (c01) addr <= 8'd0;
            end else if (stop) begin
                mode <= IDLE; out <= 1'b1;
            end else if (!c01) begin
                // ------------------------------------------------ 24C02
                if (rise) case (mode)
                    CHIP:  if (cnt < 8) begin chip[msb] <= sda; cnt <= cnt + 1'b1; end
                    ADDR:  if (cnt < 8) begin addr[msb] <= sda; cnt <= cnt + 1'b1; end
                    WRITE: if (cnt < 8) begin data[msb] <= sda; cnt <= cnt + 1'b1; end
                    READ:  if (cnt < 8) begin out <= data[msb]; cnt <= cnt + 1'b1; end
                    SACK:  out <= 1'b0;
                    WACK:  if (!sda) begin nmode <= READ; ram_a <= addr; ld1 <= 1'b1; end
                    default: ;
                endcase
                else if (fall) case (mode)
                    CHIP: if (cnt == 8) begin
                        cnt <= 0; out <= 1'b1;
                        if (chip[7] && chip[5]) begin
                            mode <= SACK;
                            if (chip[0]) begin nmode <= READ; ram_a <= addr; ld1 <= 1'b1; end
                            else nmode <= ADDR;
                        end else mode <= IDLE;
                    end
                    ADDR:  if (cnt == 8) begin cnt <= 0; mode <= SACK; nmode <= WRITE; out <= 1'b1; end
                    READ:  if (cnt == 8) begin mode <= WACK; addr <= addr + 8'd1; end
                    WRITE: if (cnt == 8) begin
                        cnt <= 0; mode <= SACK; nmode <= WRITE;
                        ram_a <= addr; ram_d <= data; ram_we <= 1'b1;
                        addr <= addr + 8'd1;
                    end
                    SACK, WACK: begin mode <= nmode; cnt <= 0; out <= 1'b1; end
                    default: ;
                endcase
            end else begin
                // ------------------------------------------------ 24C01
                if (rise) case (mode)
                    ADDR: if (cnt < 7) begin addr[cnt[2:0]] <= sda; cnt <= cnt + 1'b1; end
                          else if (cnt == 7) begin
                              cnt <= 4'd8;
                              if (sda) begin nmode <= READ; ram_a <= {1'b0, addr[6:0]}; ld1 <= 1'b1; end
                              else nmode <= WRITE;
                          end
                    SACK:  out <= 1'b0;
                    READ:  if (cnt < 8) begin out <= data[cnt[2:0]]; cnt <= cnt + 1'b1; end
                    WRITE: if (cnt < 8) begin data[cnt[2:0]] <= sda; cnt <= cnt + 1'b1; end
                    WACK:  if (!sda) nmode <= IDLE;
                    default: ;
                endcase
                else if (fall) case (mode)
                    ADDR:  if (cnt == 8) begin mode <= SACK; out <= 1'b1; end
                    SACK:  begin mode <= nmode; cnt <= 0; out <= 1'b1; end
                    READ:  if (cnt == 8) begin mode <= WACK; addr <= {1'b0, addr[6:0] + 7'd1}; end
                    WRITE: if (cnt == 8) begin
                        mode <= SACK; nmode <= IDLE;
                        ram_a <= {1'b0, addr[6:0]}; ram_d <= data; ram_we <= 1'b1;
                        addr <= {1'b0, addr[6:0] + 7'd1};
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
