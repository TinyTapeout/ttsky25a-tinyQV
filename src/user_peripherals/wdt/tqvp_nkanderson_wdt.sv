/*
 * Copyright (c) 2025 Niklas Anderson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

(* keep_hierarchy *)
module tqvp_nkanderson_wdt (
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

    output        user_interrupt  // Dedicated interrupt request for this peripheral
);

    // ------------------------------------------------------------------------
    // Internal Registers and Parameters
    // ------------------------------------------------------------------------
    localparam TAP_MAGIC = 32'h0000ABCD;  // reduce likelihood of corrupt data inadvertently signalling tap
    // Register address map
    localparam ADDR_ENABLE = 6'h00;  // 0
    localparam ADDR_START = 6'h04;  // 4
    localparam ADDR_COUNTDOWN = 6'h08;  // 8
    localparam ADDR_TAP = 6'h0C;  // 12
    localparam ADDR_STATUS = 6'h10;  // 16

    logic [31:0] countdown_value;  // configured reload value
    logic [31:0] counter;  // countdown timer

    logic        enabled;  // written at address 0 or implied by start
    logic        started;  // set by write to address 1
    logic        timeout_pending;  // true if timer expired and interrupt is active

    logic [31:0] data_reg;  // output data
    logic        data_ready_reg;

    // ------------------------------------------------------------------------
    // Write Handling
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled         <= 1'b0;
            started         <= 1'b0;
            countdown_value <= 32'd0;
            counter         <= 32'd0;
            timeout_pending <= 1'b0;
        end else begin
            // Countdown logic
            if (enabled && started && !timeout_pending) begin
                if (counter > 0) counter <= counter - 1;
                if (counter == 1) timeout_pending <= 1'b1;  // triggers interrupt on next clk
            end

            // Handle writes
            if (data_write_n != 2'b11) begin
                unique case (address)
                    ADDR_ENABLE: begin  // Enable
                        // Note: Does not clear timeout, but countdown and started state are preserved
                        enabled <= data_in[0];
                    end

                    ADDR_START: begin  // Start
                        // Start implicitly enables
                        if (countdown_value != 0) begin
                            enabled <= 1'b1;
                            started <= 1'b1;
                            counter <= countdown_value;
                        end
                    end

                    ADDR_COUNTDOWN: begin  // Set countdown value
                        unique case (data_write_n)
                            2'b00: countdown_value <= {24'd0, data_in[7:0]};
                            2'b01: countdown_value <= {16'd0, data_in[15:0]};
                            2'b10: countdown_value <= data_in;
                            default:  /* do nothing */;
                        endcase
                    end

                    ADDR_TAP: begin  // Tap
                        if (enabled && started && data_in == TAP_MAGIC) begin
                            counter <= countdown_value;
                            timeout_pending <= 1'b0;
                        end
                    end

                    default:  /* do nothing */;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // Read Handling
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        data_ready_reg <= (data_read_n != 2'b11);
        unique case (address)
            ADDR_COUNTDOWN: data_reg <= countdown_value;
            ADDR_STATUS:    data_reg <= {28'd0, (counter != 0), timeout_pending, started, enabled};
            default:        data_reg <= 32'hFFFFFFFF;
        endcase
    end

    // ------------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------------
    assign uo_out = 8'd0;  // Not used
    assign data_out = data_reg;
    assign data_ready = data_ready_reg;
    assign user_interrupt = timeout_pending;

    // List all unused inputs to prevent warnings
    // ui_in is unused as none of our behaviour depends on
    // PMOD input.
    wire _unused = &{ui_in, 1'b0};

endmodule
