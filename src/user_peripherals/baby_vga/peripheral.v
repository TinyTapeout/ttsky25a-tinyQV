/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
(* keep_hierarchy *)
module tqvp_htfab_baby_vga (
    input  wire        clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input  wire        rst_n,        // Reset_n - low to reset.

    input  wire  [7:0] ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                     // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output wire  [7:0] uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                     // Note that uo_out[0] is normally used for UART TX.

    input  wire  [5:0] address,      // Address within this peripheral's address space
    input  wire [31:0] data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input  wire  [1:0] data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input  wire  [1:0] data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

    output wire [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output wire        data_ready,

    output wire        user_interrupt  // Dedicated interrupt request for this peripheral
);

wire vga_cli;
wire [5:0] vga_x_hi;
wire [4:0] vga_x_lo;
wire [4:0] vga_y_hi;
wire [5:0] vga_y_lo;
wire vga_hsync;
wire vga_vsync;
wire vga_blank;

vga_timing vga (
    .clk,
    .rst_n,
    .cli(vga_cli),
    .x_hi(vga_x_hi),
    .x_lo(vga_x_lo),
    .y_hi(vga_y_hi),
    .y_lo(vga_y_lo),
    .hsync(vga_hsync),
    .vsync(vga_vsync),
    .blank(vga_blank),
    .interrupt(user_interrupt)
);

wire [2:0] counter = vga_x_lo[2:0];

reg [3:0] r1_addr;
wire [31:0] pixel_line;

framebuffer fb (
    .clk,
    .rst_n,
    .counter,
    .r1_addr,
    .r2_addr(vga_y_hi[3:0]),
    .w_addr(address[5:2]),
    .data_in,
    .set_data(data_write_n == 2'b10),
    .data_out1(data_out),
    .data_out2(pixel_line)
);

assign vga_cli = (data_write_n == 2'b10);

reg [3:0] read_index;
reg read_ready;

always @(posedge clk) begin
    if (!rst_n) begin
        r1_addr <= 4'b0;
        read_index <= 4'b0;
        read_ready <= 1'b0;
    end else if (read_index != 0) begin
        r1_addr <= address[5:2];
        read_index <= read_index + 1;
        if (read_index >= 4'd11) begin
            read_ready <= 1'b1;
        end else begin
            read_ready <= 1'b0;
        end
    end else if (data_read_n == 2'b10) begin
        r1_addr <= address[5:2];
        read_index <= 4'b1;
        read_ready <= 1'b0;
    end else begin
        read_index <= 4'b0;
        read_ready <= 1'b0;
    end
end

assign data_ready = read_ready;

reg pixel;
reg hsync_buf;
reg vsync_buf;

always @(posedge clk) begin
    if (!rst_n) begin
        pixel <= 1'b0;
    end else if (vga_blank) begin
        pixel <= 1'b0;
    end else begin
        pixel <= pixel_line[vga_x_hi[4:0]];
    end
    hsync_buf <= vga_hsync;
    vsync_buf <= vga_vsync;
end

assign uo_out = {hsync_buf, pixel, pixel, pixel, vsync_buf, pixel, pixel, pixel};

wire _unused = &{ui_in, address[1:0], vga_x_hi[5], vga_x_lo[4:3], vga_y_hi[4], vga_y_lo, 1'b0};

endmodule
