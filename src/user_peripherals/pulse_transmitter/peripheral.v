/*
 * Copyright (c) 2025 HX2003
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
(* keep_hierarchy *)
module tqvp_hx2003_pulse_transmitter # (
    parameter CARRIER_TIMER_WIDTH = 12, // Do not change these parameters, as the register mapping will not be updated
    parameter LOOP_COUNTER_WIDTH = 8    // Do not change these parameters, as the register mapping will not be updated
) ( 
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

    // Local Fixed parameters (do not change)
    localparam NUM_DATA_REG = 8; // NUM_DATA_REG must be power of 2 as we depend on the program to rollover, see rollover / wrapping test

    // Calculated parameters
    localparam DATA_REG_ADDR_NUM_BITS = $clog2(NUM_DATA_REG);
    
    // The various configuration registers
    reg [31:0] reg_0;
    `define interrupt_status_register reg_0[3:0]
    wire [3:0] _debug_interrupt_status_register = reg_0[3:0];
    `define program_status_register reg_0[4]
    wire _debug_program_status_register = reg_0[4];
    wire _unused_reg_0_a = &{reg_0[7:5], 1'b0};
    wire [3:0] config_interrupt_enable_mask = reg_0[11:8];
    wire config_loop_forever = reg_0[12];
    wire config_idle_level = reg_0[13];
    wire config_invert_output = reg_0[14];
    wire config_carrier_en = reg_0[15];
    wire config_downcount = reg_0[16];
    wire config_use_2bpe = reg_0[17];
    wire [1:0] config_low_symbol_0 = reg_0[19:18];
    wire [1:0] config_low_symbol_1 = reg_0[21:20];
    wire [1:0] config_high_symbol_0 = reg_0[23:22];
    wire [1:0] config_high_symbol_1 = reg_0[25:24];
    wire _unused_reg_0_b = &{reg_0[31:26], 1'b0};


    reg [31:0] reg_1;
    wire [7:0] config_program_start_index = reg_1[7:0];
    wire [7:0] config_program_end_index = reg_1[15:8];
    wire [7:0] config_program_loopback_index = reg_1[23:16];
    wire [7:0] config_program_loop_count = reg_1[31:24];
 

    reg [31:0] reg_2;
    wire [7:0] config_main_low_duration_a = reg_2[7:0];
    wire [7:0] config_main_low_duration_b = reg_2[15:8];
    wire [7:0] config_main_high_duration_a = reg_2[23:16];
    wire [7:0] config_main_high_duration_b = reg_2[31:24];


    reg [31:0] reg_3;
    wire [7:0] config_auxillary_mask = reg_3[7:0];
    wire [7:0] config_auxillary_duration_a = reg_3[15:8];
    wire [7:0] config_auxillary_duration_b = reg_3[23:16];
    wire [3:0] config_auxillary_prescaler = reg_3[27:24];
    wire [3:0] config_main_prescaler = reg_3[31:28];

    reg [11:0] reg_4;
    wire [11:0] config_carrier_duration = reg_4[11:0];

    // Interrupt
    assign user_interrupt = `interrupt_status_register > 0;
    
    wire [3:0] interrupt_event_flag = {
        program_counter_mid_interrupt, // bit 3 (program_counter_mid_interrupt)
        terminate_program, // bit 2 (program_end_interrupt)
        loop_interrupt, // bit 1 (loop_interrupt)
        timer_pulse_out // bit 0 (timer_interrupt)
    } & config_interrupt_enable_mask;

    // The rest of our code
    wire start_pulse;

    simple_rising_edge_detector config_start_rising_edge_detector(
        .clk(clk),
        .rst_n(rst_n),
        .sig_in(`program_status_register),
        .pulse_out(start_pulse)
    );
    
    reg [31:0] PROGRAM_DATA_MEM[(NUM_DATA_REG - 1):0];

    // Writing of registers / program data symbol
    // Note: Unaligned accesses may NOT be checked
    // Note: Unsupported access sizes may be not checked
    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset the registers to its defaults
            // If user modifies the value, the values are kept even if the program terminated
            reg_0 <= 0;
            reg_1 <= 0;
            reg_2 <= 0;
            reg_3 <= 0;
            reg_4 <= 0;
        end else begin
            // Defaults (they can be overriden below)
            `interrupt_status_register <= `interrupt_status_register | interrupt_event_flag;
            `program_status_register <= `program_status_register & ~terminate_program;

            if (address[5] == 1'b0) begin
                // Support 32 bit aligned write at address 0, 4, 8, 12, 16 for reg_0, reg_1, reg_2, reg_3, reg_4
                // Support 8 bit write for lower 8 bits of reg_0 (status information)
                if (data_write_n == 2'b00 || data_write_n == 2'b10) begin
                    case (address[4:2])
                        3'd0: begin
                            // reg_0[3:0] stores the interrupt values,
                            // bit 0 (timer_interrupt)
                            // bit 1 (loop_interrupt) 
                            // bit 2 (program_end_interrupt) 
                            // bit 3 (program_counter_mid_interrupt)
                            // write 1 to the desired interrupt bit to clear it
                            `interrupt_status_register <= (`interrupt_status_register & ~data_in[3:0]) | interrupt_event_flag;
                            // reg_0[4] stores whether the program is running,
                            // write 1 to bit 4 of reg_0 to start the program, (does not restart if already started)
                            // write 1 to bit 5 of reg_0 to stop the program
                            `program_status_register <= data_in[5] ? 1'b0 : ((data_in[4] ? 1'b1 : `program_status_register));

                            // reg_0[7:5] <= data_in[7:5]; not using, so lets save space

                            if (data_write_n == 2'b10) begin
                                // 32 bit write (write the remaining 24 bits)
                                reg_0[31:8] <= data_in[31:8];
                            end
                        end
                        3'd1: reg_1 <= data_in[31:0];
                        3'd2: reg_2 <= data_in[31:0];
                        3'd3: reg_3 <= data_in[31:0];
                        3'd4: reg_4 <= data_in[11:0];
                        default: begin
                            // Do nothing
                        end
                    endcase
                end
            end else begin
                if (data_write_n == 2'b10) begin
                    // Program data symbol 32 bit write
                    // map the address to our PROGRAM_DATA_MEM
                    // 0b100000 -> PROGRAM_DATA_MEM index 0
                    // 0b100100 -> PROGRAM_DATA_MEM index 1
                    // 0b101000 -> PROGRAM_DATA_MEM index 2
                    PROGRAM_DATA_MEM[address[(DATA_REG_ADDR_NUM_BITS - 1 + 2):2]] <= data_in[31:0];
                end
            end
        end
    end

    // Apply optional carrier
    wire modulated_output = config_carrier_en ? (saved_transmit_level && carrier_out): saved_transmit_level;

    // Insert idle level when not transmitting
    wire active_or_idle_output = (valid_output) ? modulated_output : config_idle_level;
    
    // Apply optional inversion
    wire final_output = active_or_idle_output ^ config_invert_output;
    
    wire carrier_out;
    
    carrier #(.TIMER_WIDTH(CARRIER_TIMER_WIDTH)) carrier_timer(
        .clk(clk),
        .sys_rst_n(rst_n),           
        .en(`program_status_register && !start_pulse && !start_pulse_delayed_1),
        .duration(config_carrier_duration),
        .out(carrier_out)
    );

    wire start_pulse_delayed_1;
    wire start_pulse_delayed_2;
    delay_2 start_pulse_delayer(
        .clk(clk),
        .sys_rst_n(rst_n),
        .sig_in(start_pulse),
        .sig_delayed_1_out(start_pulse_delayed_1),
        .sig_delayed_2_out(start_pulse_delayed_2)
    );


    wire timer_request_data;
    wire timer_pulse_out;
    wire timer_pulse_out_with_initial = start_pulse_delayed_1 || timer_pulse_out;
    reg [7:0] duration;
    reg [3:0] prescaler;
    countdown_timer countdown_timer(
        .clk(clk),
        .sys_rst_n(rst_n),
        .en(`program_status_register && !start_pulse && !start_pulse_delayed_1),
        .prescaler(prescaler),
        .duration(duration),
        .request_data(timer_request_data),
        .pulse_out(timer_pulse_out)
    );

    // When program counter is
    // 0, it should take from address 0
    // 32, it should take from address 1
    // 64, it should take from address 2
    // ...
    // 224, it should take from address 7

    // The auxillary mask only applies for the first 8 symbols in both 1bpe and 2bpe mode
    reg use_auxillary;
    always @(*) begin
        if(program_counter < 16) begin
            if (config_use_2bpe) begin
                // get the nth 
                use_auxillary = config_auxillary_mask[program_counter[3:1] +: 1];
            end else begin
                //use_auxillary = (program_counter < 8) && config_auxillary_mask[program_counter[2:0]];
                //0b0111 = 7
                use_auxillary = (program_counter[3] == 1'b0) && config_auxillary_mask[program_counter[2:0] +: 1];
            end
        end else begin 
            use_auxillary = 1'b0;
        end
    end

    wire [31:0] data_32 = PROGRAM_DATA_MEM[program_counter[7:5]];
    reg [1:0] symbol_data_raw;

    reg [1:0] symbol_data_decoded;
    reg transmit_level;

    // Combinatorics to obtain duration and transmit level based on program_counter
    always @(*) begin
        // Extract 2-bit raw chunk based on sel
        // When program counter is
        // 0, it should take from 1:0
        // 2, it should take from 3:1
        // 4, it should take from 5:4
        // ...
        symbol_data_raw = data_32[{program_counter[4:1], 1'b0} +: 2];

        if (config_use_2bpe) begin
            symbol_data_decoded = symbol_data_raw;
        end else begin
            // Select 1 bit from the symbol data
            if (symbol_data_raw[program_counter[0] +: 1]) begin
                // High
                symbol_data_decoded = sequence_done_in_1bpe ? config_high_symbol_1: config_high_symbol_0;
            end else begin
                // Low
                symbol_data_decoded = sequence_done_in_1bpe ? config_low_symbol_1: config_low_symbol_0;
            end
        end

        transmit_level = symbol_data_decoded[1];
        
        if (use_auxillary) begin
            prescaler = config_auxillary_prescaler;
            if(symbol_data_decoded[0] == 1'b0) begin
                duration = config_auxillary_duration_a;
            end else begin
                duration = config_auxillary_duration_b;
            end
        end else begin
            prescaler = config_main_prescaler;
            case (symbol_data_decoded)
                2'd0: duration = config_main_low_duration_a;
                2'd1: duration = config_main_low_duration_b;
                2'd2: duration = config_main_high_duration_a;
                2'd3: duration = config_main_high_duration_b;
            endcase
        end
    end
    
    reg saved_transmit_level;
    always @(posedge clk) begin
        if (!rst_n) begin
            saved_transmit_level <= 0;
        end else begin
            if(timer_pulse_out_with_initial) begin
                // save the transmit_level
                saved_transmit_level <= transmit_level;
            end
        end
    end

    // The output is only valid when `program_status_register is high,
    // except for the first few cycles after starting the program.
    // This is because it takes some cycles to fetch and prefetch the symbols.
    wire valid_output = `program_status_register && !start_pulse && !start_pulse_delayed_1 && !start_pulse_delayed_2;

    // The program counter should increment:
    // once for start_pulse (we fetch the current symbol and increment program_counter)
    // every time we trigger the timer (note: program counter is incremented before timer has elapsed, because we want to prefetch)
    wire program_counter_increment_trigger = timer_request_data;
    
    // The program counter is 8 bits, so between 0 to 255
    //
    // In 2bpe (2 bit per element) mode, program_counter is incremented by 2 each time
    // can be any even value between 0 to 255 inclusive
    //
    // In 1bpe (1 bit per element) mode, program_counter is incremented by 1 each time,
    // As each element is expanded to 2 symbols, the program_counter is incremented half as often
    //
    // config_program_start_index, config_program_end_index and config_program_loopback_index
    // can be any value between 0 to 255 inclusive

    // In 1bpe mode, each element is expanded to 2 symbols we need to keep track of which symbol we are currently at
    reg sequence_done_in_1bpe;

    reg [7:0] program_counter;
    reg [(LOOP_COUNTER_WIDTH - 1):0] program_loop_counter;
    reg program_end_of_file;
    reg loop_interrupt; // should only be activated for 1 pulse
    reg program_counter_mid_interrupt; // should only be activated for 1 pulse

    always @(posedge clk) begin
        if (!rst_n || !`program_status_register) begin
            program_loop_counter <= config_program_loop_count;
            program_end_of_file <= 0;
            program_counter <= config_program_start_index;
            loop_interrupt <= 0;
            program_counter_mid_interrupt <= 0;
            sequence_done_in_1bpe <= 0;
        end else begin
            loop_interrupt <= 0; // default value, can be overridden later
            program_counter_mid_interrupt <= 0; // default value, can be overridden later

            if (program_counter_increment_trigger) begin
                // Toggle this every time,
                // In 1bpe mode: it starts from 0 -> 1 -> 0 -> 1 -> 0 -> ...
                // only when sequence_done_in_1bpe is 1 when something is done, so program_counter is incremented half as often 
                //
                // In 2bpe mode: sequence_done_in_1bpe will be ignored
                sequence_done_in_1bpe <= !sequence_done_in_1bpe;
                
                if(config_use_2bpe || sequence_done_in_1bpe) begin
                    // We only want the interrupt to trigger once every time the program counter is at 128
                    // Note, this does not mean it triggers at this interval
                    if (program_counter == 128) begin
                        program_counter_mid_interrupt <= 1'b1;
                    end

                    if (program_counter == config_program_end_index) begin
                        if (!config_loop_forever && (program_loop_counter == 0)) begin
                            // Set program_end_of_file
                            // But do not disable output yet, as the preloaded values are not yet flushed out
                            program_end_of_file <= 1;
                        end else begin
                            // We want to loop, set the program counter
                            program_counter <= config_program_loopback_index;
                            program_loop_counter <= program_loop_counter - 1;
                            loop_interrupt <= 1'b1;
                        end
                    end else begin
                        // Less utilization
                        if (config_downcount) begin
                            if (config_use_2bpe) begin
                                program_counter <= program_counter - 2;
                            end else begin
                                program_counter <= program_counter - 1;
                            end
                        end else begin
                            if (config_use_2bpe) begin
                                program_counter <= program_counter + 2;
                            end else begin
                                program_counter <= program_counter + 1;
                            end
                        end
                    end
                end
            end
        end
    end

    wire terminate_program = timer_pulse_out_with_initial && program_end_of_file;

    // Pin outputs
    assign uo_out[1:0] = 0;
    assign uo_out[2] = carrier_out;
    assign uo_out[3] = valid_output;
    assign uo_out[7:4] = {final_output, final_output, final_output, final_output};
  
    // Read address doesn't matter
    assign data_out[4:0] = reg_0[4:0];
    assign data_out[7:5] = 3'b0;
    assign data_out[15:8] = program_loop_counter;
    assign data_out[23:16] = program_counter;
    assign data_out[31:24] = 8'b0;

    // All reads complete in 1 clock
    assign data_ready = 1;
 
    // List all unused inputs to prevent warnings
    wire _unused1 = &{data_read_n, 1'b0};
    wire _unused2 = &{ui_in, 1'b0};
    wire _unused3 = &{address[1:0], 1'b0};

endmodule
