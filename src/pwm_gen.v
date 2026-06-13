`default_nettype none

// 8-channel PWM generator. A single free-running 8-bit counter
// (0..255) is shared by all channels; channel i is high while the
// counter is less than duty_i (duty=0 -> always low,
// duty=255 -> high for 255/256 of the period). PWM frequency is
// CLK_FREQ / 256.
module pwm_gen (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] duty0,
    input  wire [7:0] duty1,
    input  wire [7:0] duty2,
    input  wire [7:0] duty3,
    input  wire [7:0] duty4,
    input  wire [7:0] duty5,
    input  wire [7:0] duty6,
    input  wire [7:0] duty7,
    output wire [7:0] pwm_out
);

    reg [7:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 8'd0;
        end else begin
            counter <= counter + 1'b1;
        end
    end

    assign pwm_out[0] = (counter < duty0);
    assign pwm_out[1] = (counter < duty1);
    assign pwm_out[2] = (counter < duty2);
    assign pwm_out[3] = (counter < duty3);
    assign pwm_out[4] = (counter < duty4);
    assign pwm_out[5] = (counter < duty5);
    assign pwm_out[6] = (counter < duty6);
    assign pwm_out[7] = (counter < duty7);

endmodule
