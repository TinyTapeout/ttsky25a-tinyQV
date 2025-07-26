

module ws2812b_byte_assembler  (
    input  wire clk,
    input  wire reset,

    input  wire bit_valid,
    input  wire bit_value,

    output reg  byte_valid,
    output reg [7:0] byte_data
);

    reg [2:0] bit_count;
    reg [7:0] shift_reg;

    always @(posedge clk) begin
        if (reset) begin
            bit_count  <= 3'd0;
            shift_reg  <= 8'd0;
            byte_valid <= 1'b0;
        end else begin
            byte_valid <= 1'b0;  // default

            if (bit_valid) begin
                shift_reg <= {shift_reg[6:0], bit_value};
                bit_count <= bit_count + 1;

                if (bit_count == 3'd7) begin
                    byte_data  <= {shift_reg[6:0], bit_value}; // full byte
                    byte_valid <= 1'b1;
                    bit_count  <= 3'd0;
                end
            end
        end
    end

endmodule
