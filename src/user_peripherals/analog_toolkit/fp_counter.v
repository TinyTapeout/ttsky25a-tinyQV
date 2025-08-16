`default_nettype none

module fp_counter (
    input wire clk,
    input wire rst_n,
    input wire [7:0] step,
    input wire step_en,
    output wire [7:0] value
);

reg [29:0] counter;
wire [19:0] inc = {16'b0000000000000001, step[3:0]} << step[7:4];

always @(posedge clk) begin
    if (!rst_n) begin
        counter <= 0;
    end else if(step_en) begin
        counter <= counter + {10'b0, inc};
    end
end

reg [3:0] shift;

always @(*) begin
    casez (counter[29:14])
        16'b0000000000000000: shift = 4'b0000;
        16'b0000000000000001: shift = 4'b0001;
        16'b000000000000001?: shift = 4'b0010;
        16'b00000000000001??: shift = 4'b0011;
        16'b0000000000001???: shift = 4'b0100;
        16'b000000000001????: shift = 4'b0101;
        16'b00000000001?????: shift = 4'b0110;
        16'b0000000001??????: shift = 4'b0111;
        16'b000000001???????: shift = 4'b1000;
        16'b00000001????????: shift = 4'b1001;
        16'b0000001?????????: shift = 4'b1010;
        16'b000001??????????: shift = 4'b1011;
        16'b00001???????????: shift = 4'b1100;
        16'b0001????????????: shift = 4'b1101;
        16'b001?????????????: shift = 4'b1110;
        16'b01??????????????: shift = 4'b1111;
        16'b10??????????????: shift = 4'b1111;
        16'b110?????????????: shift = 4'b1110;
        16'b1110????????????: shift = 4'b1101;
        16'b11110???????????: shift = 4'b1100;
        16'b111110??????????: shift = 4'b1011;
        16'b1111110?????????: shift = 4'b1010;
        16'b11111110????????: shift = 4'b1001;
        16'b111111110???????: shift = 4'b1000;
        16'b1111111110??????: shift = 4'b0111;
        16'b11111111110?????: shift = 4'b0110;
        16'b111111111110????: shift = 4'b0101;
        16'b1111111111110???: shift = 4'b0100;
        16'b11111111111110??: shift = 4'b0011;
        16'b111111111111110?: shift = 4'b0010;
        16'b1111111111111110: shift = 4'b0001;
        16'b1111111111111111: shift = 4'b0000;
    endcase
end

reg sign;
reg [3:0] exponent;
reg [2:0] mantissa;

always @(posedge clk) begin
    sign <= counter[29];
    exponent <= counter[29] ? ~shift : shift;
    mantissa <= counter[(shift == 0 ? 11 : shift+10) +: 3];
end

assign value = {sign, exponent, mantissa};

endmodule
