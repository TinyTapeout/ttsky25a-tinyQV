/* Copyright 2023-2024 (c) Michael Bell
   SPDX-License-Identifier: Apache-2.0
 */

module sim_qspi_pmod (
    // External SPI interface
    input      [3:0] qspi_data_in,
    output reg [3:0] qspi_data_out,
    input            qspi_clk,

    input qspi_flash_select,
    input qspi_ram_a_select,
    input qspi_ram_b_select
);

    // ROM and RAM size in bytes is 1 << XXX_BITS.
    parameter   ROM_BITS       = 13;
    parameter   RAM_A_BITS     = 12;
    parameter   RAM_B_BITS     = 11;

    reg [31:0] cmd;
    reg [24:0] addr;
    reg [5:0] start_count;
    reg reading_dummy;
    reg reading;
    reg writing;
    reg error;
    reg [3:0] data_buff_in;
    wire [7:0] rom_buff_out;
    wire [7:0] ram_a_buff_out;
    wire [7:0] ram_b_buff_out;

    wire any_select = qspi_flash_select && qspi_ram_a_select && qspi_ram_b_select;

    BRAM #(.ADDR_WIDTH(ROM_BITS), .INIT_FILE(`PROG_FILE)) rom (
        .clk(qspi_clk),
        .data_in({data_buff_in, qspi_data_in}),
        .data_out(rom_buff_out),
        .addr(addr[ROM_BITS:1]),
        .wen(1'b0),
        .ren(!addr[0] & !qspi_flash_select)
    );
    BRAM #(.ADDR_WIDTH(RAM_A_BITS)) ram_a (
        .clk(qspi_clk),
        .data_in({data_buff_in, qspi_data_in}),
        .data_out(ram_a_buff_out),
        .addr(addr[RAM_A_BITS:1]),
        .wen(writing & addr[0] & !qspi_ram_a_select),
        .ren(!addr[0] & !qspi_ram_a_select)
    );
    BRAM #(.ADDR_WIDTH(RAM_B_BITS)) ram_b (
        .clk(qspi_clk),
        .data_in({data_buff_in, qspi_data_in}),
        .data_out(ram_b_buff_out),
        .addr(addr[RAM_B_BITS:1]),
        .wen(writing & addr[0] & !qspi_ram_b_select),
        .ren(!addr[0] & !qspi_ram_b_select)
    );

    wire [5:0] next_start_count = start_count + 1;

    always @(posedge qspi_clk or posedge any_select) begin
        if (any_select) begin
            cmd <= 0;
            start_count <= 0;
        end else begin
            start_count <= next_start_count;

            if (!addr[0]) data_buff_in <= qspi_data_in;

            if (!reading && !writing && !error) begin
                cmd <= {cmd[27:0], qspi_data_in};
            end
        end
    end

    always @(negedge qspi_clk or posedge any_select) begin
        if (any_select) begin
            reading <= 0;
            reading_dummy <= 0;
            writing <= 0;
            error <= 0;
            addr <= 0;
        end else begin
            if (reading || writing) begin
                addr <= addr + 1;
            end else if (reading_dummy) begin
                if (start_count < 8 && cmd[3:0] != 4'b1010) begin
                    error <= 1;
                    reading_dummy <= 0;
                end
                if (start_count == 12) begin
                    reading <= 1;
                    reading_dummy <= 0;
                end
            end else if (!error && start_count == (qspi_flash_select ? 8 : 6)) begin
                addr[ROM_BITS:1] <= cmd[ROM_BITS-1:0];
                addr[0] <= 0;
                if (!qspi_flash_select || cmd[31:24] == 8'h0B)
                    reading_dummy <= 1;
                else if (cmd[31:24] == 8'h02)
                    writing <= 1;
                else
                    error <= 1;
            end
        end
    end

    always @(negedge qspi_clk) begin
        qspi_data_out <= !qspi_ram_a_select ? (addr[0] ? ram_a_buff_out[3:0] : ram_a_buff_out[7:4]) :
                         !qspi_ram_b_select ? (addr[0] ? ram_b_buff_out[3:0] : ram_b_buff_out[7:4]) :
                                              (addr[0] ? rom_buff_out[3:0] : rom_buff_out[7:4]);
    end

endmodule
