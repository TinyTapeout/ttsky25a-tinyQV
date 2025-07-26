/*
 * Copyright (c) 2025 Javier MS
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tqvp_impostor_WS2812b (
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

    // Internal reset
    wire reset = ~rst_n;

    // ------------------------------
    // Signal wiring
    // ------------------------------
    wire bit_valid;
    wire bit_value;
    wire byte_valid;
    wire [7:0] byte_data;
    wire idle;
    //latching
    wire rgb_ready_pulse;
    reg  rgb_ready;
    wire clear_rgb = (data_write && address == 4'hE);


    // Registers to store the first 3 bytes (G, R, B)
    reg [7:0] reg_g, reg_r, reg_b;
    reg [1:0] byte_index;

    // ------------------------------
    // Instantiate modules
    // ------------------------------
    ws2812b_pulse_decoder #(
        .CLK_HZ(64000000),
        .THRESHOLD_CYCLES(38)
    ) decoder (
        .clk(clk),
        .reset(reset),
        .din(ui_in[1]),
        .bit_valid(bit_valid),
        .bit_value(bit_value)
    );

    ws2812b_byte_assembler byte_assembler (
        .clk(clk),
        .reset(reset),
        .bit_valid(bit_valid),
        .bit_value(bit_value),
        .byte_valid(byte_valid),
        .byte_data(byte_data)
    );

    ws2812b_idle_detector #(
        .CLK_HZ(64000000),
        .IDLE_US(60)
    ) idle_detector (
        .clk(clk),
        .reset(reset),
        .din(ui_in[1]),
        .idle(idle)
    );

    ws2812b_demux demux (
        .clk(clk),
        .reset(reset),
        .din_raw(ui_in[1]),
        .bit_valid(bit_valid),
        .bit_value(bit_value),
        .byte_valid(byte_valid),
        .idle(idle),
        .dout(uo_out[1]),
        .rgb_ready(rgb_ready_pulse)
    );


    // ------------------------------
    // RGB Register capture
    // ------------------------------
    always @(posedge clk) begin
        if (reset || idle) begin
            byte_index <= 0;
        end else if (byte_valid && byte_index < 3) begin
            case (byte_index)
                2'd0: reg_g <= byte_data;
                2'd1: reg_r <= byte_data;
                2'd2: reg_b <= byte_data;
            endcase
            byte_index <= byte_index + 1;
        end
    end

    // ------------------------------
    // Addressable Output Register Mapping
    // ------------------------------
    reg [7:0] data_out_r;

    always @(*) begin
        case (address)
            4'h0: data_out_r = reg_r;
            4'h1: data_out_r = reg_g;
            4'h2: data_out_r = reg_b;
            4'hF: data_out_r = rgb_ready ? 8'hFF : 8'h00;//0xFF if rgb_ready 0x00 if0
            default: data_out_r = 8'h00;
        endcase
    end

    assign data_out = data_out_r;

    // ------------------------------
    // explicit clear register
    // ------------------------------
    always @(posedge clk) begin
        if (reset || idle) begin
            rgb_ready <= 0;
        end else begin
            if (rgb_ready_pulse)
                rgb_ready <= 1;

            if (clear_rgb)
                rgb_ready <= 0;
        end
    end




    // All unused outputs to 0 
    assign uo_out[0] = 1'b0;
    assign uo_out[7:2] = 6'b0;

endmodule
