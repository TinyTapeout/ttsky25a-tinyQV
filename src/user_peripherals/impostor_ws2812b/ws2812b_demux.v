

module ws2812b_demux (
    input  wire clk,
    input  wire reset,

    input  wire din_raw,     // NEW: actual DIN waveform (synchronized)
    input  wire bit_valid,
    input  wire bit_value,
    input  wire byte_valid,
    input  wire idle,

    output reg  dout,
    output reg  rgb_ready    // high for 1 cycle after RGB is captured
);

    // Classic Verilog FSM (Icarus-compatible)
    localparam WAIT_RGB   = 2'b00;
    localparam FORWARDING = 2'b01;

    reg [1:0] state, next_state;
    reg [1:0] byte_count;

    // State + control
    always @(posedge clk) begin
        if (reset) begin
            state <= WAIT_RGB;
            byte_count <= 2'd0;
            dout <= 1'b0;
            rgb_ready <= 1'b0;
        end else begin
            state <= next_state;
            rgb_ready <= 1'b0;

            case (state)
                WAIT_RGB: begin
                    if (byte_valid) begin
                        byte_count <= byte_count + 1;
                        if (byte_count == 2'd2)
                            rgb_ready <= 1'b1;  // signal RGB is fully captured
                    end
                    dout <= 1'b0;  // mute during RGB capture
                end

                FORWARDING: begin
                    dout <= din_raw;  // forward waveform directly
                end

                default: begin
                    // Safe default handling: mute dout and clear rgb_ready
                    dout <= 1'b0;
                    rgb_ready <= 1'b0;
                end
                
            endcase

            if (idle) begin
                byte_count <= 2'd0;
            end
        end
    end

    // Next state logic
    always @(*) begin
        case (state)
            WAIT_RGB:
                next_state = (byte_count == 2'd2 && byte_valid) ? FORWARDING : WAIT_RGB;

            FORWARDING:
                next_state = idle ? WAIT_RGB : FORWARDING;

            default:
                next_state = WAIT_RGB;
        endcase
    end

endmodule
