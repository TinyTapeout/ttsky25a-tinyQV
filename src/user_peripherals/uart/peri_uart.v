/*
 * Copyright (c) 2025 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// UART peripheral - this wraps both TX and RX UART
module tqvp_uart_wrapper #(
    parameter DIVIDER_REG_LEN = 13,        // Enough to allow baud rates down to 9600 at 64MHz clock
    parameter CLOCK_MHZ = 64
    )(
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    output [1:0]  user_interrupt  // Dedicated interrupt request for this peripheral
);

    // A read/write register to control the divider
    reg [DIVIDER_REG_LEN-1:0] baud_divider;
    always @(posedge clk) begin
        if (!rst_n) begin
            baud_divider <= (CLOCK_MHZ * 1000000) / 115200;  // Reset to correct divider for 115200 baud.
        end else begin
            if (address == 6'h8) begin
                if (data_write_n != 2'b11)              baud_divider[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) baud_divider[DIVIDER_REG_LEN-1:8]  <= data_in[DIVIDER_REG_LEN-1:8];
            end
        end
    end

    // A read/write 1-bit register to choose alternative ui_in for rxd
    reg rxd_select;
    always @(posedge clk) begin
        if (!rst_n) begin
            rxd_select <= 0;
        end else begin
            if (address == 6'hc) begin
                if (data_write_n != 2'b11) rxd_select <= data_in[0];
            end
        end
    end

    //////  TX functionality //////

    wire uart_tx_busy;
    wire uart_txd;

    tqvp_uart_tx i_uart_tx(
        .clk(clk),
        .resetn(rst_n),
        .uart_txd(uart_txd),
        .uart_tx_en((address == 6'h0 && data_write_n != 2'b11)),
        .uart_tx_data(data_in[7:0]),
        .uart_tx_busy(uart_tx_busy),
        .baud_divider(baud_divider)
    );

    // Interrupt on ability to send
    assign user_interrupt[1] = !uart_tx_busy;

    ////// RX functionality //////

    wire uart_rx_valid;
    wire [7:0] uart_rx_data;
    wire uart_rxd = rxd_select ? ui_in[3] : ui_in[7];
    wire uart_rts;

    tqvp_uart_rx i_uart_rx(
        .clk(clk),
        .resetn(rst_n),
        .uart_rxd(uart_rxd),
        .uart_rts(uart_rts),
        .uart_rx_read(!uart_rx_buffered),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_data(uart_rx_data),
        .baud_divider(baud_divider) 
    );

    // Buffer one byte of received data
    reg uart_rx_buffered;
    reg [7:0] uart_rx_buf_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            uart_rx_buffered <= 0;
        end else begin
            if (uart_rx_buffered == 0) begin
                uart_rx_buffered <= uart_rx_valid;
                uart_rx_buf_data <= uart_rx_data;
            end else begin
                if (address == 6'h0 && data_read_n != 2'b11) begin
                    uart_rx_buffered <= 0;
                end
            end
        end
    end

    // Interrupt on byte available
    assign user_interrupt[0] = uart_rx_buffered;
    assign data_out = address == 6'h0 ? {24'd0, uart_rx_buf_data} :
                      address == 6'h4 ? {30'd0, uart_rx_buffered, uart_tx_busy} :
                      address == 6'h8 ? {19'd0, baud_divider} : 
                      address == 6'hc ? {31'd0, rxd_select} : 32'd0;
    assign data_ready = 1;

    assign uo_out = {4{uart_rts, uart_txd}};

    wire _unused = &{data_in[31:8], ui_in[6:0], 1'b0};

endmodule
