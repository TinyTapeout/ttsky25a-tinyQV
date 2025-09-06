/*
 * Copyright (c) 2025 Pedro Correia
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tqvp_TRNG_20RO7FF_PC #(
    parameter SIZE_RO = 6, //size of the RO will be SIZE_RO + 1 inverter gates (7 in this case)
              N_RO = 20 //number of ROs in parallel
  )(
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

    reg [N_RO:0][SIZE_RO:0] oscillator_ring = 0;
    reg [N_RO:0] oscillator_ring_Q = 0;

    reg [7:0] ro_data = 0;
    reg [7:0] shift_reg = 0;
    reg xorA;
    reg counter = 4'b0;
    integer i;
    integer j;

    always @(*) begin //Ring oscilators Construction logic

        for (j = 0; j < N_RO; j = j + 1) begin
            for (i = 1; i <= SIZE_RO; i = i + 1) begin
                oscillator_ring[j][i] = ~oscillator_ring[j][i-1];
            end
            oscillator_ring[j][0] = ~oscillator_ring[j][SIZE_RO];
        end
    end

    always_ff @(posedge clk) begin //sampling FF logic
        for (i = 0; i < N_RO; i = i + 1) begin
            oscillator_ring_Q[i] = oscillator_ring[i][SIZE_RO];
        end
    end

    always @(*) begin // xor logic
        xorA = oscillator_ring_Q[0] ^ oscillator_ring_Q[1];
        for (i = 2; i < N_RO; i = i + 1) begin
            xorA = xorA ^ oscillator_ring_Q[i];
        end
    end

    always_ff @(posedge clk or posedge !rst_n) begin //shift register / 8bit data packager
        if (!rst_n) begin
            counter <= 4'b0;
            ro_data <= 8'b0;
            shift_reg <= 8'b0;
            tx_start <= 1'b0;
        end
        else begin
            if (rst_n) begin
                shift_reg[7] <= xorA;
                shift_reg[6] <= shift_reg[7];
                shift_reg[5] <= shift_reg[6];
                shift_reg[4] <= shift_reg[5];
                shift_reg[3] <= shift_reg[4];
                shift_reg[2] <= shift_reg[3];
                shift_reg[1] <= shift_reg[2];
                shift_reg[0] <= shift_reg[1];

                // Counting logic
                if (counter >= 7) begin
                    ro_data <= shift_reg;
                    tx_start <= 1'b1;
                    shift_reg <= 8'b0;
                    data_out <= ro_data;
                end
                else begin
                    tx_start <= 1'b0;
                end
            end
        end
    end

endmodule
