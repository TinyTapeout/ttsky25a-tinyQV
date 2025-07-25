`timescale 1ns/1ps
module pwm_tb;
reg clk, rst, wen;
reg [7:0] wdata;
reg [3:0] addr;
wire pwm_out;
pwm dut (.clk(clk),.rst(rst),.wen(wen),.wdata(wdata),.addr(addr),.pwm_out(pwm_out));
initial begin
    $dumpfile("pwm.vcd");
    $dumpvars(0, pwm_tb);
    clk=0;
    rst=1;
    wen=0;
    #20 rst=0;
    // Set period
    #10 addr=4'h0; wdata=8'd100; wen=1; #10 wen=0;
    // Set duty
    #10 addr=4'h4; wdata=8'd40; wen=1; #10 wen=0;
    // Enable
    #10 addr=4'h8; wdata=8'd1; wen=1; #10 wen=0;
    #1000 $finish;
end
always #5 clk=~clk;
endmodule
