`default_nettype none

// UART receiver: 8N1 frame format, configurable clock frequency and
// baud rate. Detects the start bit, samples each bit at the center of
// its period, and pulses `valid` for one clock cycle when a full byte
// has been received into `data`.
module uart_rx #(
    parameter CLK_FREQ  = 10_000_000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);

    localparam CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT       = CYCLES_PER_BIT / 2;
    localparam CNT_W          = $clog2(CYCLES_PER_BIT);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]       state;
    reg [CNT_W-1:0] cnt;
    reg [2:0]       bit_idx;
    reg [7:0]       shift_reg;
    reg             rx_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cnt       <= {CNT_W{1'b0}};
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            data      <= 8'd0;
            valid     <= 1'b0;
            rx_sync   <= 1'b1;
        end else begin
            rx_sync <= rx;
            valid   <= 1'b0;

            case (state)
                S_IDLE: begin
                    cnt <= {CNT_W{1'b0}};
                    if (rx_sync == 1'b0) begin
                        state <= S_START;
                    end
                end

                S_START: begin
                    // Sample at the center of the start bit to confirm
                    // it is a real start bit (filters short glitches).
                    if (cnt == HALF_BIT - 1) begin
                        cnt <= {CNT_W{1'b0}};
                        if (rx_sync == 1'b0) begin
                            state   <= S_DATA;
                            bit_idx <= 3'd0;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    // A full bit period after the start-bit center lands
                    // on the center of each data bit, LSB first.
                    if (cnt == CYCLES_PER_BIT - 1) begin
                        cnt <= {CNT_W{1'b0}};
                        shift_reg[bit_idx] <= rx_sync;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    if (cnt == CYCLES_PER_BIT - 1) begin
                        cnt   <= {CNT_W{1'b0}};
                        data  <= shift_reg;
                        valid <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
