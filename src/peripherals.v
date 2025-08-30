/*
 * Copyright (c) 2025 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Wrapper for all TinyQV peripherals
//
// Address space:
// 0x800_0000 - 03f: Reserved by project wrapper (time, debug, etc)
// 0x800_0040 - 07f: GPIO configuration
// 0x800_0080 - 0bf: UART TX
// 0x800_00c0 - 0ff: UART RX
// 0x800_0100 - 3ff: 12 user peripherals (64 bytes each, word and halfword access supported, each has an interrupt)
// 0x800_0400 - 4ff: 16 simple peripherals (16 bytes each, byte access only)
module tinyQV_peripherals #(parameter CLOCK_MHZ=64) (
    input         clk,
    input         rst_n,

    input  [7:0]  ui_in,        // The input PMOD, always available
    input  [7:0]  ui_in_raw,    // The input PMOD, not synchronized
    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected

    output reg    audio,        // An extra output that can be selected on to uio[7]
    output        audio_select, // Whether audio should be selected on uio[7] (resets to 0).

    input [10:0]  addr_in,
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    input         data_read_complete,  // Set by TinyQV when a read is complete

    output [15:2] user_interrupts  // User peripherals get interrupts 2-15
);

    // Registered data out to TinyQV
    reg  [31:0] data_out_r;
    reg         data_out_hold;
    reg         data_ready_r;

    wire        read_req = data_read_n != 2'b11;

    // Muxed data out direct from selected peripheral
    reg [31:0] data_from_peri;
    reg        data_ready_from_peri;

    // Must mask the data_read_n to avoid extra read while
    // buffering the result
    wire [1:0] data_read_n_peri;
    assign data_read_n_peri = data_read_n | {2{data_ready_r}};

    wire [31:0] data_from_user_peri   [0:23];
    wire [7:0]  data_from_simple_peri [0:15];
    wire        data_ready_from_user_peri   [0:23];

    wire [7:0]  uo_out_from_user_peri   [0:23];
    wire [7:0]  uo_out_from_simple_peri [0:15];
    reg [7:0] uo_out_comb;
    assign uo_out = uo_out_comb;

    // Register the data output from the peripheral.  This improves timing and
    // also simplifies the peripheral interface (no need for the peripheral to care
    // about holding data_out until data_read_complete - it looks like it is read
    // synchronously).
    always @(posedge clk) begin
        if (!rst_n) begin
            data_out_hold <= 0;
        end else begin
            if (data_read_complete) data_out_hold <= 0;

            if (!data_out_hold && data_ready_from_peri && data_read_n != 2'b11) begin
                data_out_hold <= 1;
                data_out_r <= data_from_peri;
            end

            // Data ready must be registered because data_out is.
            data_ready_r <= read_req && data_ready_from_peri;
        end
    end

    assign data_out = data_out_r;
    assign data_ready = data_ready_r || data_write_n != 2'b11;

    // --------------------------------------------------------------------- //
    // Decode the address to select the active peripheral

    localparam PERI_GPIO = 1;
    localparam PERI_UART = 2;

    reg [23:0] peri_user;
    reg [15:0] peri_simple;

    always @(*) begin
        peri_user = 0;
        peri_simple = 0;

        if (addr_in[10:9] == 2'b10) begin
            peri_simple[addr_in[7:4]] = 1;
            data_from_peri = {24'h0, data_from_simple_peri[addr_in[7:4]]};
            data_ready_from_peri = 1;
        end else if (addr_in[10] == 1'b1) begin
            peri_user[{addr_in[10], 1'b0, addr_in[8:6]}] = 1;
            data_from_peri = data_from_user_peri[{addr_in[10], 1'b0, addr_in[8:6]}];
            data_ready_from_peri = data_ready_from_user_peri[{addr_in[10], 1'b0, addr_in[8:6]}];
        end else begin
            peri_user[{1'b0, addr_in[9:6]}] = 1;
            data_from_peri = data_from_user_peri[{1'b0, addr_in[9:6]}];
            data_ready_from_peri = data_ready_from_user_peri[{1'b0, addr_in[9:6]}];
        end
    end

    assign data_from_user_peri[0] = 32'h0;
    assign data_ready_from_user_peri[0] = 0;
    assign uo_out_from_user_peri[0] = 8'h0;

    // --------------------------------------------------------------------- //
    // GPIO

    reg [3:0] audio_func_sel;
    reg [5:0] gpio_out_func_sel [0:7];
    reg [7:0] gpio_out;

    always @(posedge clk) begin
        if (!rst_n) begin
            gpio_out <= 0;
        end else if (peri_user[PERI_GPIO]) begin
            if (addr_in[5:0] == 6'h0) begin
                if (data_write_n != 2'b11) gpio_out <= data_in[7:0];
            end
        end
    end

    assign data_from_user_peri[PERI_GPIO] = (addr_in[5:0] == 6'h0) ? {24'h0, gpio_out} :
                                            (addr_in[5:0] == 6'h4) ? {24'h0, ui_in}    :
                                            (addr_in[5:0] == 6'h10)? {28'h0, audio_func_sel} :
                                            ({addr_in[5], addr_in[1:0]} == 3'b100) ? {26'h0, gpio_out_func_sel[addr_in[4:2]][5:0] } :
                                            32'h0;
    assign data_ready_from_user_peri[PERI_GPIO] = 1;
    assign uo_out_from_user_peri[PERI_GPIO] = gpio_out;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin
            always @(posedge clk) begin
                if (!rst_n) begin
                    gpio_out_func_sel[i] <= (i == 0 || i == 1) ? PERI_UART : PERI_GPIO;
                end else if (peri_user[PERI_GPIO]) begin
                    if ({addr_in[5], addr_in[1:0]} == 3'b100 && addr_in[4:2] == i) begin
                        if (data_write_n != 2'b11) gpio_out_func_sel[i] <= {data_in[5:0]};
                    end
                end
            end

            always @(*) begin
                uo_out_comb[i] = 0;

                if (gpio_out_func_sel[i][4]) begin
                    uo_out_comb[i] = uo_out_from_simple_peri[gpio_out_func_sel[i][3:0]][i];
                end else begin
                    uo_out_comb[i] = uo_out_from_user_peri[{gpio_out_func_sel[i][5],gpio_out_func_sel[i][3:0]}][i];
                end
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (!rst_n) begin
            audio_func_sel <= 0;
        end else if (peri_user[PERI_GPIO]) begin
            if (addr_in[5:0] == 6'h10) begin
                if (data_write_n != 2'b11) audio_func_sel <= data_in[3:0];
            end
        end
    end

    always @(posedge clk) begin
        case (audio_func_sel[2:0])
            3'b000: audio <= uo_out_from_user_peri[17][7];   // PWL synth right
            3'b001: audio <= uo_out_from_user_peri[11][7];   // Pulse TX
            3'b010: audio <= uo_out_from_simple_peri[4][0];  // PWM
            3'b011: audio <= uo_out_from_simple_peri[5][7];  // Matt PWM
            3'b100: audio <= uo_out_from_user_peri[8][7];    // Prism
            3'b101: audio <= uo_out_from_simple_peri[10][7]; // Analog toolkit
            3'b110: audio <= uo_out_from_simple_peri[17][6]; // PWL Synth left
            3'b111: audio <= uo_out_from_simple_peri[5][7];  // Matt PWM
        endcase
    end

    assign audio_select = audio_func_sel[3];

    // --------------------------------------------------------------------- //
    // UART

    tqvp_uart_wrapper #(.CLOCK_MHZ(CLOCK_MHZ)) i_uart (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[PERI_UART]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[PERI_UART]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[PERI_UART]}}),

        .data_out(data_from_user_peri[PERI_UART]),
        .data_ready(data_ready_from_user_peri[PERI_UART]),

        .user_interrupt(user_interrupts[PERI_UART+1:PERI_UART])
    );

    // Peripheral 3 is a full peripheral but with no interrupt
    tqvp_game_pmod i_user_peri03(
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[3]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[3]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[3]}}),

        .data_out(data_from_user_peri[3]),
        .data_ready(data_ready_from_user_peri[3])
    );

    // --------------------------------------------------------------------- //
    // Full interface peripherals

    tqvp_sohaib_npu i_user_peri04(
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[4]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[4]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[4]}}),

        .data_out(data_from_user_peri[4]),
        .data_ready(data_ready_from_user_peri[4]),

        .user_interrupt(user_interrupts[4])
    );

    tqvp_htfab_baby_vga i_user_peri05 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[5]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[5]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[5]}}),

        .data_out(data_from_user_peri[5]),
        .data_ready(data_ready_from_user_peri[5]),

        .user_interrupt(user_interrupts[5])
    );

    tqvp_nkanderson_wdt i_user_peri06 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[6]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[6]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[6]}}),

        .data_out(data_from_user_peri[6]),
        .data_ready(data_ready_from_user_peri[6]),

        .user_interrupt(user_interrupts[6])
    );

    tqvp_full_empty i_user_peri07 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[7]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[7]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[7]}}),

        .data_out(data_from_user_peri[7]),
        .data_ready(data_ready_from_user_peri[7]),

        .user_interrupt(user_interrupts[7])
    );

    tqvp_prism i_prism08 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[8]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[8]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[8]}}),

        .data_out(data_from_user_peri[8]),
        .data_ready(data_ready_from_user_peri[8]),

        .user_interrupt(user_interrupts[8])
    );

    tqvp_full_empty i_user_peri09 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[9]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[9]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[9]}}),

        .data_out(data_from_user_peri[9]),
        .data_ready(data_ready_from_user_peri[9]),

        .user_interrupt(user_interrupts[9])
    );

    tqvp_jnms_pdm i_pdm10 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[10]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[10]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[10]}}),

        .data_out(data_from_user_peri[10]),
        .data_ready(data_ready_from_user_peri[10]),

        .user_interrupt(user_interrupts[10])
    );

    tqvp_hx2003_pulse_transmitter i_user_peri11 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[11]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[11]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[11]}}),

        .data_out(data_from_user_peri[11]),
        .data_ready(data_ready_from_user_peri[11]),

        .user_interrupt(user_interrupts[11])
    );

    tqvp_full_empty i_user_peri12 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[12]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[12]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[12]}}),

        .data_out(data_from_user_peri[12]),
        .data_ready(data_ready_from_user_peri[12]),

        .user_interrupt(user_interrupts[12])
    );

    tqvp_cattuto_vgaconsole i_tqvp_cattuto_vgaconsole (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[13]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[13]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[13]}}),

        .data_out(data_from_user_peri[13]),
        .data_ready(data_ready_from_user_peri[13]),

        .user_interrupt(user_interrupts[13])
    );

    tqvp_full_empty i_user_peri14 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[14]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[14]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[14]}}),

        .data_out(data_from_user_peri[14]),
        .data_ready(data_ready_from_user_peri[14]),

        .user_interrupt(user_interrupts[14])
    );

    tqvp_full_example i_user_peri15 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[15]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[15]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[15]}}),

        .data_out(data_from_user_peri[15]),
        .data_ready(data_ready_from_user_peri[15]),

        .user_interrupt(user_interrupts[15])
    );

    // --------------------------------------------------------------------- //
    // Byte interface peripherals

    tqvp_matt_encoder matt_encoder00 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[0]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[0]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[0])
    );

    tqvp_edge_counter i_edge_counter01 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[1]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[1]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[1])
    );

    tqvp_cattuto_ws2812b_driver i_cattuto_ws2812b_driver02 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[2]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[2]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[2])
    );

    tqvp_impostor_WS2812b javi_WS2812b_slave (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[3]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[3]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[3])
    );

    tqvp_pwm_sujith pwm_sk(
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[4]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[4]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[4])
    );

    tqvp_matt_pwm matt_pwm (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[5]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[5]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[5])
    );

    tqvp_spike spike(
        .clk(clk),
        .rst_n(rst_n),
        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[6]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[6]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[6])
    );

    tqvp_rebeccargb_universal_decoder ubcd (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[7]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[7]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[7])
    );

    tqvp_rebeccargb_hardware_utf8 hardware_utf8 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[8]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[8]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[8])
    );

    tqvp_meiniKi_waveforms i_tqvp_meiniKi_waveforms (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[9]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[9]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[9])
    );

    tqvp_htfab_anatool analog_toolkit (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[10]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[10]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[10])
    );

    tqvp_crc32 crc32(
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[11]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[11]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[11])
    );

    tqvp_htfab_vga_tester vga_tester (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[12]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[12]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[12])
    );

    tqvp_alonso_rsa i_tqvp_alonso_rsa_user_simple013 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[13]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[13]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[13])
    );

    tqvp_spi_peripheral i_user_simple014 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in_raw),
        .uo_out(uo_out_from_simple_peri[14]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[14]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[14])
    );

    tqvp_byte_example i_user_simple015 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[15]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[15]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[15])
    );

    // --------------------------------------------------------------------- //
    // Additional full interface peripherals with no interrupt

    tqvp_dsatizabal_fpu i_user_peri32 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[16]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[16]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[16]}}),

        .data_out(data_from_user_peri[16]),
        .data_ready(data_ready_from_user_peri[16])
    );

    tqvp_toivoh_pwl_synth i_user_peri33 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[17]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[17]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[17]}}),

        .data_out(data_from_user_peri[17]),
        .data_ready(data_ready_from_user_peri[17])
    );

    tqvp_laurie_dwarf_line_table_accelerator i_user_peri34 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[18]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[18]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[18]}}),

        .data_out(data_from_user_peri[18]),
        .data_ready(data_ready_from_user_peri[18])
    );

    tqvp_cattuto_xoshiro128plusplus_prng i_user_peri35 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[19]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[19]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[19]}}),

        .data_out(data_from_user_peri[19]),
        .data_ready(data_ready_from_user_peri[19])
    );

    tqvp_fjpolo_rv2a03 i_user_peri36 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[20]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[20]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[20]}}),

        .data_out(data_from_user_peri[20]),
        .data_ready(data_ready_from_user_peri[20])
    );

    tqvp_rebeccargb_intercal_alu  i_user_peri37 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[21]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[21]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[21]}}),

        .data_out(data_from_user_peri[21]),
        .data_ready(data_ready_from_user_peri[21])
    );

    reg cordic_interrupt;
    tqvp_CORDIC i_user_peri38       (.clk(clk),
                                     .rst_n(rst_n),

                                     .ui_in(ui_in),
                                     .uo_out(uo_out_from_user_peri[22]),

                                     .address(addr_in[5:0]),
                                     .data_in(data_in),

                                     .data_write_n(data_write_n    | {2{~peri_user[22]}}),
                                     .data_read_n(data_read_n_peri | {2{~peri_user[22]}}),

                                     .data_out(data_from_user_peri[22]),
                                     .data_ready(data_ready_from_user_peri[22]),

                                     .user_interrupt(cordic_interrupt));


    tqvp_affinex i_user_peri39 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[23]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n    | {2{~peri_user[23]}}),
        .data_read_n(data_read_n_peri | {2{~peri_user[23]}}),

        .data_out(data_from_user_peri[23]),
        .data_ready(data_ready_from_user_peri[23])
    );

endmodule
