`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 38 and change tqvp_example to your chosen module name.
module tqvp_htfab_anatool (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [3:0]   address,      // Address within this peripheral's address space

    input         data_write,   // Data write request from the TinyQV core.
    input [7:0]   data_in,      // Data in to the peripheral, valid when data_write is high.
    
    output [7:0]  data_out      // Data out from the peripheral, set this in accordance with the supplied address
);

    reg [7:0] step;
    reg [2:0] channel;
    reg duty_rst_n;

    wire [7:0] fp_time;
    wire [7:0] fp_duty;

    fp_counter fp_time_i (
        .clk,
        .rst_n,
        .step,
        .step_en(1'b1),
        .value(fp_time)
    );

    fp_counter fp_duty_i (
        .clk,
        .rst_n(rst_n & duty_rst_n),
        .step,
        .step_en(ui_in[channel]),
        .value(fp_duty)
    );

    reg [7:0] in_duty;
    reg [7:0] out_duty [2:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            step <= 0;
            out_duty[0] <= 8'h80;
            out_duty[1] <= 8'h80;
            out_duty[2] <= 8'h80;
            channel <= 0;
        end else if (data_write) begin
            if (address == 4) begin
                step <= data_in;
            end else if (address == 5) begin
                channel <= data_in[2:0];
            end else begin
                out_duty[2'(address)] <= data_in;
            end
        end
    end

    wire roll = fp_time[7];
    reg last_roll;

    always @(posedge clk) begin
        if (!rst_n) begin
            last_roll <= 0;
            duty_rst_n <= 0;
        end else begin
            last_roll <= roll;
            if (last_roll && !roll) begin
                in_duty <= fp_duty;
                duty_rst_n <= 0;
            end else begin
                duty_rst_n <= 1;
            end
        end
    end

    wire [2:0] out_bank;
    assign out_bank[0] = fp_time < out_duty[0];
    assign out_bank[1] = fp_time < out_duty[1];
    assign out_bank[2] = fp_time < out_duty[2];

    assign uo_out = {out_bank, !ui_in[4], out_bank, ui_in[0]};

    assign data_out = in_duty;

endmodule
