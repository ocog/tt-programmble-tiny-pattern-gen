`default_nettype none

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

    // -------------------------------------------------------------------------
    // Port mapping
    // -------------------------------------------------------------------------
    wire uart_rx = ui_in[0];
    wire mode    = ui_in[1];
    wire load    = ui_in[2];

    // -------------------------------------------------------------------------
    // FSM
    // state[2] = play_en
    // state[1] = accept_uart
    // state[0] = init_we
    // -------------------------------------------------------------------------
    localparam INIT = 3'b001;
    localparam LOAD = 3'b010;
    localparam PLAY = 3'b110;

    reg [2:0] state, next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= INIT;
        else        state <= next;
    end

    always @(state or init_done or load) begin
        next = 3'bx;
        case (state)
            INIT:    next = (init_done) ? LOAD : INIT;
            LOAD:    next = (load)      ? PLAY : LOAD;
            PLAY:    next = PLAY;
            default: next = INIT;
        endcase
    end

    assign {play_en, accept_uart, init_we} = state;

    // -------------------------------------------------------------------------
    // Init counter
    // -------------------------------------------------------------------------
    reg [5:0] init_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       init_addr <= 6'd0;
        else if (init_we) init_addr <= init_addr + 1'b1;
    end

    wire init_done = (init_addr == 6'd63);

    // -------------------------------------------------------------------------
    // UART RX
    // -------------------------------------------------------------------------
    wire [7:0] uart_data;
    wire       uart_valid;

    uart_rx #(
        .CLK_FREQ  (10_000_000),
        .BAUD_RATE (9600)
    ) uart_rx_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (uart_rx),
        .data  (uart_data),
        .valid (uart_valid)
    );

    // -------------------------------------------------------------------------
    // Write address counter
    // -------------------------------------------------------------------------
    reg [7:0] write_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                        write_addr <= 8'd0;
        else if (accept_uart & uart_valid) write_addr <= write_addr + 1'b1;
    end

    // -------------------------------------------------------------------------
    // RAM write datapath mux
    // -------------------------------------------------------------------------
    wire       we    = init_we | (accept_uart & uart_valid);
    wire [7:0] waddr = init_we ? {2'b00, init_addr} : write_addr;
    wire [7:0] wdata = init_we ? 8'h00               : uart_data;

    // -------------------------------------------------------------------------
    // Pattern player
    // -------------------------------------------------------------------------
    wire [7:0] play_addr;
    wire       advance;

    pattern_player #(
        .CLK_FREQ     (10_000_000),
        .PLAY_RATE_HZ (1000),
        .RAM_DEPTH    (64)
    ) pattern_player_inst (
        .clk    (clk),
        .rst_n  (rst_n),
        .raddr  (play_addr),
        .advance(advance)
    );

    // -------------------------------------------------------------------------
    // RAM
    // -------------------------------------------------------------------------
    wire [7:0] ram_rdata;

    ram_256x8 ram_inst (
        .clk   (clk),
        .we    (we),
        .waddr (waddr),
        .wdata (wdata),
        .raddr (play_addr),
        .rdata (ram_rdata)
    );

    // -------------------------------------------------------------------------
    // PWM duty cycle capture
    // -------------------------------------------------------------------------
    reg [7:0] duty [0:7];
    reg [7:0] cap_addr;
    reg       cap_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_addr  <= 8'd0;
            cap_valid <= 1'b0;
        end else begin
            cap_addr  <= play_addr;
            cap_valid <= advance;
        end
    end

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1)
                duty[i] <= 8'd0;
        end else if (cap_valid & (cap_addr[7:3] == 5'd0)) begin
            duty[cap_addr[2:0]] <= ram_rdata;
        end
    end

    // -------------------------------------------------------------------------
    // PWM generator
    // -------------------------------------------------------------------------
    wire [7:0] pwm_out;

    pwm_gen pwm_gen_inst (
        .clk    (clk),
        .rst_n  (rst_n),
        .duty0  (duty[0]), .duty1 (duty[1]),
        .duty2  (duty[2]), .duty3 (duty[3]),
        .duty4  (duty[4]), .duty5 (duty[5]),
        .duty6  (duty[6]), .duty7 (duty[7]),
        .pwm_out(pwm_out)
    );

    // -------------------------------------------------------------------------
    // Output mux — gated by play_en
    // -------------------------------------------------------------------------
    assign uo_out = play_en ? (mode ? pwm_out : ram_rdata) : 8'h00;

    // -------------------------------------------------------------------------
    // Bidirectional IO
    // -------------------------------------------------------------------------
    assign uio_out = {7'b0, advance};
    assign uio_oe  = {7'b0, play_en & ~mode};

    // -------------------------------------------------------------------------
    // Unused inputs
    // -------------------------------------------------------------------------
    wire _unused = &{ena, uio_in, ui_in[7:3]};

endmodule