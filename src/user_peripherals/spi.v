/* Copyright 2023-2025 (c) Michael Bell
   SPDX-License-Identifier: Apache-2.0

   A general SPI controller, with optional DC line for
   simple control of SPI LCDs.
   */

`default_nettype none

module tqvp_spi_ctrl (
    input clk,
    input rstn,

    // External SPI interface
    input      spi_miso,
    output reg spi_select,
    output reg spi_clk_out,
    output     spi_mosi,
    output reg spi_dc,  // Data/command indication

    // Internal interface for reading/writing data
    input        dc_in,    // Written back to spi_dc when byte transmission begins
    input        end_txn,  // Whether to release CS at the end of this byte
    input  [7:0] data_in,  // Data to transmit
    input        start,    // Signal to start a transfer, set high for 1 clock when busy is low
    output [7:0] data_out, // Data read, valid when busy is low
    output reg   busy,     // Whether a transfer is in progress

    // Configuration
    input        set_config,  // Set high to change the clock divider
    input  [6:0] divider_in,  // SPI clock is input clock divided by 2 * (divider_in + 1)
    input        read_latency_in // If low reads are sampled half an SPI clock cycle after the rising edge, 
                                 // if high the sample is one SPI clock cycle later.
);

    reg [7:0] data;
    reg [3:0] bits_remaining;
    reg       end_txn_reg;
    reg [6:0] clock_count;
    reg [6:0] clock_divider;
    reg       read_latency;

    always @(posedge clk) begin
        if (!rstn) begin
            read_latency <= 0;
            clock_divider <= 7'd3;
        end else begin
            if (set_config) begin
                clock_divider <= divider_in;
                read_latency <= read_latency_in;
            end
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            busy <= 0;
            spi_select <= 1;
            spi_clk_out <= 0;
            spi_dc <= 0;
            clock_count <= 0;
            bits_remaining <= 0;
        end else begin
            if (!busy) begin
                if (start) begin
                    busy <= 1;
                    data <= data_in;
                    spi_dc <= dc_in;
                    end_txn_reg <= end_txn;
                    bits_remaining <= 4'd8;
                    spi_select <= 0;
                    spi_clk_out <= 0;
                end
            end else begin
                clock_count <= clock_count + 7'h1;
                if (clock_count == clock_divider) begin
                    clock_count <= 0;
                    spi_clk_out <= !spi_clk_out;
                    if (spi_clk_out) begin
                        data <= {data[6:0], spi_miso};
                        if (bits_remaining != 0) begin
                            bits_remaining <= bits_remaining - 3'b001;
                        end
                    end else begin
                        if (bits_remaining[3] == 0 && read_latency) data[0] <= spi_miso;
                        if (bits_remaining == 0) begin
                            busy <= 0;
                            spi_select <= end_txn_reg;
                            spi_clk_out <= 0;
                        end
                    end
                end
            end
        end
    end

    assign spi_mosi = data[7];
    assign data_out = data;

endmodule

module tqvp_spi_peripheral (
    input         clk,
    input         rst_n,

    input  [7:0]  ui_in,        // The input PMOD, always available
    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected

    input [3:0]   address,      // Address within this peripheral's address space

    input         data_write,   // Data write request from the TinyQV core.
    input [7:0]   data_in,      // Data in to the peripheral, valid when data_write is high.
    
    output [7:0]  data_out      // Data out from the peripheral, set this in accordance with the supplied address
);

    // State for next byte.  If tx_pending then this will
    // be sent immediately as soon as previous byte finishes.
    reg tx_pending;
    reg dc_ctrl;
    reg end_txn;
    reg [7:0] tx_data;

    wire spi_busy;
    wire [7:0] rx_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_pending <= 0;
            dc_ctrl <= 0;
            end_txn <= 1;
        end else begin
            if (data_write) begin
                if (address == 4'h0) begin
                    end_txn <= data_in[2];
                    dc_ctrl <= data_in[3];
                end else if (address == 4'h1) begin
                    tx_pending <= 1;
                    tx_data <= data_in;
                end
            end else begin
                if (!spi_busy && tx_pending) begin
                    tx_pending <= 0;
                end
            end
        end
    end

    wire start = !data_write && !spi_busy && tx_pending;
    wire spi_select;

    tqvp_spi_ctrl i_spi_ctrl (
        .clk(clk),
        .rstn(rst_n),

        .spi_miso(ui_in[2]),
        .spi_select(spi_select),
        .spi_clk_out(uo_out[5]),
        .spi_mosi(uo_out[3]),
        .spi_dc(uo_out[2]),

        .dc_in(dc_ctrl),
        .end_txn(end_txn),
        .data_in(tx_data),
        .start(start),
        .data_out(rx_data),
        .busy(spi_busy),

        .set_config(data_write && address == 4'h4),
        .divider_in(data_in[6:0]),
        .read_latency_in(data_in[7])
    );

    assign uo_out[1:0] = {2{spi_select}};
    assign uo_out[4] = spi_select;
    assign uo_out[7:6] = {2{spi_select}};

    // Address 0 reads the control/status register.  
    // Address 1 reads back tx_data
    // Address 2 reads rx_data
    // All other addresses read 0 (config is write only)
    assign data_out = (address == 4'h0) ? {4'b0000, dc_ctrl, end_txn, tx_pending, spi_busy} :
                      (address == 4'h1) ? tx_data :
                      (address == 4'h2) ? rx_data :
                      8'h0;    

    // List all unused inputs to prevent warnings
    wire _unused = &{ui_in[7:3], ui_in[1:0], 1'b0};

endmodule