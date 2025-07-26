

module ws2812b_pulse_decoder #(
    parameter CLK_HZ = 64000000,
    parameter THRESHOLD_CYCLES = 38
)(
    input  wire clk,
    input  wire reset,
    input  wire din,
    output reg  bit_valid,
    output reg  bit_value
);

    // FSM states (use classic Verilog style)
    localparam IDLE       = 2'b00;
    localparam COUNT_HIGH = 2'b01;
    localparam WAIT_LOW   = 2'b10;

    reg [1:0] state, next_state;
    reg [7:0] high_counter;

    reg din_sync_0, din_sync_1;
    wire din_stable;

    assign din_stable = din_sync_1;

    // Input synchronizer
    always @(posedge clk) begin
        din_sync_0 <= din;
        din_sync_1 <= din_sync_0;
    end

    // FSM state register
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            high_counter <= 0;
            bit_valid <= 0;
            bit_value <= 0;
        end else begin
            state <= next_state;
            bit_valid <= 0; // default

            case (state)
                IDLE: begin
                    if (din_stable)
                        high_counter <= 1;
                end
                COUNT_HIGH: begin
                    if (din_stable)
                        high_counter <= high_counter + 1;
                end
                WAIT_LOW: begin
                    if (!din_stable) begin
                        bit_valid <= 1;
                        bit_value <= (high_counter > THRESHOLD_CYCLES) ? 1'b1 : 1'b0;
                    end
                end
            endcase
        end
    end

    // FSM next-state logic
    always @(*) begin
        case (state)
            IDLE:
                next_state = din_stable ? COUNT_HIGH : IDLE;

            COUNT_HIGH:
                next_state = din_stable ? COUNT_HIGH : WAIT_LOW;

            WAIT_LOW:
                next_state = din_stable ? WAIT_LOW : IDLE;

            default:
                next_state = IDLE;
        endcase
    end

endmodule
