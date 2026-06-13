`default_nettype none

// Synchronous single-port RAM built entirely from flip-flops (no memory
// macros). Write on the rising edge when `we` is high; the read output
// is registered (one cycle of latency).
//
// NOTE: the address ports are 8 bits wide per the project interface,
// but only the low 6 bits are decoded, giving 64 x 8 bits of storage.
// A full 256 x 8 FF array (2048 flip-flops + 256:1 muxes) does not fit
// in a 1x1 Tiny Tapeout tile, so the storage depth was reduced to 64
// while keeping the module/port names unchanged.
module ram_256x8 (
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] waddr,
    input  wire [7:0] wdata,
    input  wire [7:0] raddr,
    output reg  [7:0] rdata
);

    localparam DEPTH = 64;

    reg [7:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            mem[waddr[5:0]] <= wdata;
        end
        rdata <= mem[raddr[5:0]];
    end

endmodule
