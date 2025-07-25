module pwm (input clk, rst, wen, input [7:0] wdata, input [3:0] addr,output pwm_out);
reg [15:0] period;
reg [15:0] duty;
reg [15:0] counter;
reg enable;
reg pwm_reg;
assign pwm_out=pwm_reg;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        period<=16'd100;
        duty<=16'd50;
        counter<=16'd0;
        enable<=1'b0;
        pwm_reg<=1'b0;
    end else begin
        if (wen) begin
            case (addr)
                4'h0: period<={8'd0, wdata};
                4'h4: duty<={8'd0, wdata};
                4'h8: enable<=wdata[0];
            endcase
        end
        if (enable) begin
            if (counter>=period)
                counter<=16'd0;
            else
                counter<=counter+16'd1;
            pwm_reg<=(counter<duty);
        end else begin
            counter<=16'd0;
            pwm_reg<=1'b0;
        end
    end
end
endmodule
