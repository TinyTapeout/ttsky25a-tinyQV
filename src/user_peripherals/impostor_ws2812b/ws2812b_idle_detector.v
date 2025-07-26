

module ws2812b_idle_detector #(
    parameter CLK_HZ = 64000000,   // system clock
    parameter IDLE_US = 60         // idle threshold in microseconds
)(
    input  wire clk,
    input  wire reset,
    input  wire din,
    output reg  idle
);
    localparam integer IDLE_CYCLES = (CLK_HZ / 1000000) * IDLE_US;

    reg [$clog2(IDLE_CYCLES):0] idle_counter;

    always @(posedge clk) begin
        if (reset) begin
            idle_counter <= 0;
            idle <= 0;
        end else if (din == 1'b1) begin
            idle_counter <= 0;
            idle <= 0;
        end else begin
            if (idle_counter < IDLE_CYCLES)
                idle_counter <= idle_counter + 1;
            else
                idle <= 1;
        end
    end
endmodule
