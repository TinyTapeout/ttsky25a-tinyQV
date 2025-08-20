/*
 * Copyright (c) 2025 Javier MS
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

(* keep_hierarchy *)
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
    wire clear_rgb = (data_write && address == 4'h3);


    // Registers to store the first 3 bytes (G, R, B)
    reg [7:0] reg_g, reg_r, reg_b;
    reg [1:0] byte_index;

    // ------------------------------
    // Instantiate modules
    // ------------------------------
    ws2812b_pulse_decoder decoder (
        .clk(clk),
        .reset(reset),
        .din(din),
        .threshold_cycles(reg_threshold_cycles),
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

    ws2812b_idle_detector idle_detector (
        .clk(clk),
        .reset(reset),
        .din(din),
        .idle_threshold_ticks(reg_idle_ticks),
        .idle(idle)
    );


    ws2812b_demux demux (
        .clk(clk),
        .reset(reset),
        .din_raw(din),
        .bit_valid(bit_valid),
        .bit_value(bit_value),
        .byte_valid(byte_valid),
        .idle(idle),
        .dout(dout_signal),
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
            4'h4: data_out_r = rgb_ready ? 8'hFF : 8'h00;//0xFF if rgb_ready 0x00 if0
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

    // ------------------------------------
    // Clock Configuration registers (prescalers)
    // ------------------------------------
    reg [15:0] reg_threshold_cycles;
    reg [15:0] reg_idle_ticks;
    reg [15:0] shadow_threshold_cycles;
    reg [15:0] shadow_idle_ticks;

    reg prescaler_commit;

    // Default values set on reset
    always @(posedge clk) begin
        if (reset) begin
            reg_threshold_cycles     <= 16'd38;
            reg_idle_ticks           <= 16'd3840;
            shadow_threshold_cycles  <= 16'd38;
            shadow_idle_ticks        <= 16'd3840;
            prescaler_commit         <= 1'b0;
        end else begin
            // Self-clear one-shot flag
            prescaler_commit <= 1'b0;

            if (data_write) begin
                case (address)
                    // shadow_idle_ticks
                    4'h6: shadow_idle_ticks[7:0]    <= data_in;
                    4'h7: shadow_idle_ticks[15:8]   <= data_in;

                    // shadow_threshold_cycles
                    4'hA: shadow_threshold_cycles[7:0]    <= data_in;
                    4'hB: shadow_threshold_cycles[15:8]   <= data_in;

                    // Prescaler commit request
                    4'h5: prescaler_commit <= 1'b1;
                endcase
            end

            // Apply commit if triggered
            if (prescaler_commit) begin
                reg_threshold_cycles <= shadow_threshold_cycles;
                reg_idle_ticks       <= shadow_idle_ticks;
            end
        end
    end

// ------------------------------------
// Din pin configuration registers
// ------------------------------------
reg [2:0] reg_din_select;
wire din = ui_in[reg_din_select];

always @(posedge clk) begin
    if (reset) begin
        reg_din_select <= 3'd1;  // Default DIN = ui_in[1]
    end else if (data_write && address == 4'hE) begin
        reg_din_select <= data_in[2:0]; // Only use lower 3 bits
    end
end


//replicateDOUT on all outputs, this way the tiniQV is able to choose
wire dout_signal;
assign uo_out = {8{dout_signal}};


endmodule
