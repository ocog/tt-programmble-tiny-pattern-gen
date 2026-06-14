`default_nettype none

// Synchronous single-port RAM built entirely from flip-flops (no memory
// macros). Write on the rising edge when `we` is high; the read output
// is registered (one cycle of latency).
//
// NOTE: the address ports are 8 bits wide per the project interface,
// but only the low 7 bits are decoded, giving 128 x 8 bits of storage
// (1024 flip-flops plus 128:1 read/write muxes).
module ram_256x8 (
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] waddr,
    input  wire [7:0] wdata,
    input  wire [7:0] raddr,
    output reg  [7:0] rdata
);

    localparam DEPTH = 128;

    reg [7:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            mem[waddr[6:0]] <= wdata;
        end
        rdata <= mem[raddr[6:0]];
    end

endmodule
