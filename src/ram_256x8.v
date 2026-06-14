`default_nettype none

// Synchronous single-port RAM built entirely from flip-flops (no memory
// macros). Write on the rising edge when `we` is high; the read output
// is registered (one cycle of latency).
//
// NOTE: full 256 x 8 storage, using all 8 address bits. This is a
// 2048 flip-flop FF array (plus 256:1 read/write muxes), which is
// unlikely to fit in a 1x1 Tiny Tapeout tile - see info.yaml.
module ram_256x8 (
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] waddr,
    input  wire [7:0] wdata,
    input  wire [7:0] raddr,
    output reg  [7:0] rdata
);

    localparam DEPTH = 256;

    reg [7:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
        rdata <= mem[raddr];
    end

endmodule
