`default_nettype none

// Top-level Tiny Tapeout wrapper for the programmable waveform / PWM
// generator.
//
//   ui_in[0] = UART RX
//   ui_in[1] = MODE (0 = DAC playback, 1 = PWM)
//
//   MODE = 0: uo_out = RAM playback byte (for TLC7524 DAC),
//             uio_out[0] = DAC write strobe (pulses with pattern_player
//             advance), uio_oe[0] = 1.
//   MODE = 1: uo_out = 8 independent PWM channels, duty cycles taken
//             from RAM[0..7]. uio pins are all inputs (high-Z).
//
// NOTE: this wrapper uses the standard Tiny Tapeout split I/O ports
// (uio_in / uio_out / uio_oe) rather than a top-level `inout` port,
// matching the interface required by the TT test harness and PDK
// I/O cells.
module tt_um_pattern_gen (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire       uart_valid;
    wire [7:0] uart_data;

    uart_rx uart_rx_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (ui_in[0]),
        .data  (uart_data),
        .valid (uart_valid)
    );

    // Write-address pointer: advances by one for every received byte.
    reg [7:0] write_addr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_addr <= 8'd0;
        end else if (uart_valid) begin
            write_addr <= write_addr + 1'b1;
        end
    end

    wire [7:0] play_addr;
    wire       advance;

    pattern_player pattern_player_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .raddr   (play_addr),
        .advance (advance)
    );

    wire [7:0] ram_rdata;

    ram_256x8 ram_inst (
        .clk   (clk),
        .we    (uart_valid),
        .waddr (write_addr),
        .wdata (uart_data),
        .raddr (play_addr),
        .rdata (ram_rdata)
    );

    // Capture duty-cycle bytes for PWM channels 0-7 from RAM[0..7] as
    // the pattern player passes over those addresses. `play_addr`/
    // `advance` lead `ram_rdata` by one cycle, so the address is
    // registered alongside the advance pulse and matched up with the
    // RAM data on the following cycle.
    reg [7:0] cap_addr;
    reg       cap_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_addr  <= 8'd0;
            cap_valid <= 1'b0;
        end else begin
            cap_valid <= advance;
            if (advance) begin
                cap_addr <= play_addr;
            end
        end
    end

    reg [7:0] duty0, duty1, duty2, duty3, duty4, duty5, duty6, duty7;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            duty0 <= 8'd0;
            duty1 <= 8'd0;
            duty2 <= 8'd0;
            duty3 <= 8'd0;
            duty4 <= 8'd0;
            duty5 <= 8'd0;
            duty6 <= 8'd0;
            duty7 <= 8'd0;
        end else if (cap_valid) begin
            case (cap_addr)
                8'd0: duty0 <= ram_rdata;
                8'd1: duty1 <= ram_rdata;
                8'd2: duty2 <= ram_rdata;
                8'd3: duty3 <= ram_rdata;
                8'd4: duty4 <= ram_rdata;
                8'd5: duty5 <= ram_rdata;
                8'd6: duty6 <= ram_rdata;
                8'd7: duty7 <= ram_rdata;
                default: ;
            endcase
        end
    end

    wire [7:0] pwm_out;

    pwm_gen pwm_gen_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .duty0   (duty0),
        .duty1   (duty1),
        .duty2   (duty2),
        .duty3   (duty3),
        .duty4   (duty4),
        .duty5   (duty5),
        .duty6   (duty6),
        .duty7   (duty7),
        .pwm_out (pwm_out)
    );

    wire mode = ui_in[1];

    assign uo_out  = mode ? pwm_out : ram_rdata;
    assign uio_out = mode ? 8'h00 : {7'b0, advance};
    assign uio_oe  = mode ? 8'h00 : 8'b0000_0001;

    // uio_in and ena are not used by this design.

endmodule
