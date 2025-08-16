// Copyright (c) 2025 Ken Pettit
// SPDX-License-Identifier: Apache-2.0
//
// Description:  
// ------------------------------------------------------------------------------
//
//    This is a Programmable Reconfigurable Indexed State Machine (PRISM)
//    peripheral for the TinyQV RISC-V processor.
//
//                        /\           
//                       /  \           
//                   ..-/----\-..       
//               --''  /      \  ''--   
//                    /________\        
//
//
//        
//   +----------------+                                  
//   |                |    +------------------------+                 +----------+
//   |                |    |  24-bit Register       |                 | 24-bit   |
//   |                |<-->|                        |<----------------+ preload/ |
//   |                |    |  counter/shifter/FIFO  +-------+         | load     |
//   |     PRISM      |    +-------------------+----+       v         +----------+
//   |                |                        |           .-.        
//   |    8-state     |<-----------------------|----------+ = |<------zero
//   |  programmable  |      +--------------+  |           '-'                     
//   |      FSM       |      |    5-bit     |<-+                                   
//   |                |      | Shift Count  |                                      
//   |                |<-----+eq_zero       |<-+                                   
//   |                |      +--------------+  |                                   
//   |                |                        |
//   |                |    +-------------------+----+                              
//   |                |    |   8-bit Comm Register  |                              
//   |                |<-->|                        +-----------------+             
//   |                |    |  load / shfit / read   |                 |             
//   |                |    +------------------------+                 |             
//   |                |                                               |            
//   |                |    +------------------------+             /|  |               
//   |                |    |   8-bit Up/Down counter|      .-.   | +--+ +----------+  
//   |                |<-->|                        |---->| = |<-| |    |  8-bit   |  
//   |                |    |   counter/shifter      |      '+'   | +----+ compare  |  
//   |                |    +------------------------+       |     \|    |          |  
//   |                |                                     |           +----------+  
//   |                |<------------------------------------+                       
//   +----------------+                                                            
//                   
// ------------------------------------------------------------------------------

`default_nettype none

module tqvp_prism (
    input             clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input             rst_n,        // Reset_n - low to reset.
               
    input      [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                    // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.
               
    output     [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                    // Note that uo_out[0] is normally used for UART TX.

    (* keep = "true" *)
    input     [5:0]   address,      // Address within this peripheral's address space
    (* keep = "true" *)
    input     [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    (* keep = "true" *)
    input     [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    (* keep = "true" *)
    input     [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    (* keep = "true" *)
    output reg [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output            data_ready,

    output        user_interrupt    // Dedicated interrupt request for this peripheral
);

    localparam  OUTPUTS = 11;

    localparam  OUT_LATCH2          = 2;
    localparam  OUT_LOAD4           = 4;
    localparam  OUT_COUNT2_DEC      = 5;
    localparam  OUT_SHIFT           = 6;
    localparam  OUT_COUNT1_DEC      = 7;
    localparam  OUT_COUNT1_LOAD     = 8;
    localparam  OUT_COUNT2_INC      = 9;
    localparam  OUT_COUNT2_CLEAR    = 10;

    wire                prism_enable;
    wire                prism_rst_n;
    wire                prism_exec;
    wire                prism_halt;
    reg                 prism_halt_r;
    reg                 prism_interrupt;
    wire                prism_wr;
    wire [15:0]         prism_in_data;
    wire [OUTPUTS-1:0]  prism_out_data;
    wire [31:0]         prism_read_data;
    (* keep = "true" *)
    reg   [1:0]         host_in;
    wire                ctrl_reg_en;
    wire                count1_reg_en;
    wire                count2_reg_en;
    wire                count1_toggle_en;
    (* keep = "true" *)
    reg  [23:0]         count1;
    (* keep = "true" *)
    wire [23:0]         count1_preload;
    (* keep = "true" *)
    reg   [7:0]         count2;
    (* keep = "true" *)
    wire  [7:0]         count2_compare;
    wire                count2_dec;
    wire  [6:0]         uo_out_c;
    (* keep = "true" *)
    reg   [6:0]         latched_out;
    (* keep = "true" *)
    reg   [1:0]         latched_in;
    (* keep = "true" *)
    wire  [1:0]         cond_out_sel;
    wire  [3:1]         cond_out_en;
    (* keep = "true" *)
    reg   [7:0]         comm_data;
    wire  [1:0]         shift_in_sel;
    wire                shift_in;
    wire  [3:0]         shift_data_bits;
    wire  [1:0]         shift_out_sel;
    wire  [3:1]         shift_out;
    (* keep = "true" *)
    reg   [2:0]         shift_count;
    wire                shift_dir;
    wire                shift_24_en;
    wire                shift_en;
    wire  [1:0]         shift_mode;
    wire                shift_data;
    wire                fifo_24;
    wire                shift_24;
    wire                shift_8;
    wire                latch_in;
    wire                latch3;
    wire                load4;
    wire                out0_fifo_full;
    (* keep = "true" *)
    reg   [1:0]         fifo_wr_ptr;
    (* keep = "true" *)
    reg   [1:0]         fifo_rd_ptr;
    (* keep = "true" *)
    reg   [1:0]         fifo_count;
    wire                fifo_write;
    wire                fifo_push;
    wire                fifo_read;
    (* keep = "true" *)
    reg   [7:0]         fifo_rd_data;
    wire                fifo_full;
    wire                fifo_empty;
    wire                latch_in_out;
`ifndef SYNTH_FPGA
    (* keep = "true" *)
    reg   [31:0]        latch_data;
    (* keep = "true" *)
    reg                 latch_wr;
    reg                 latch_wr_p0;
`else
    wire  [31:0]        latch_data;
    assign latch_data = data_in;
`endif
    wire  [0:0]         cond_out;

    // =============================================================
    // Crate a divide by 2 clock using clock gate
    // =============================================================
`ifdef DONT_COMPILE
    wire                clk_div2;
    reg                 clk_gate;

    always @(negedge clk or negedge rst_n)
    begin
        if (~rst_n)
            clk_gate <= 1'b0;
        else// if (prism_enable)
            clk_gate <= ~clk_gate;
    end

`ifdef SIM
    assign clk_div2 = clk_gate & clk;
`else
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__dlclkp_4 CG( .CLK(clk), .GCLK(clk_div2), .GATE(clk_gate) );
    /* verilator lint_on PINMISSING */
`endif
`endif
    
    // =============================================================
    // Instantiate the PRISM controller
    // =============================================================
    prism
    #(
        .OUTPUTS ( OUTPUTS )
     )
    i_prism
    (
        .clk                ( clk               ),
        .rst_n              ( rst_n             ),

        .fsm_enable         ( prism_enable      ),
        .in_data            ( prism_in_data     ),
        .out_data           ( prism_out_data    ),
        .cond_out           ( cond_out          ),
                            
`ifndef SYNTH_FPGA
        // Latch register control
        .latch_data         ( latch_data        ),
        .latch_wr           ( latch_wr          ),
`endif

        .debug_addr         ( address           ),
        .debug_wr           ( prism_wr          ),
        .debug_wdata        ( data_in           ),
        .debug_rdata        ( prism_read_data   ),
        .debug_halt_either  ( prism_halt        )
    );

    assign prism_wr = data_write_n != 2'b11;
    assign prism_exec = prism_enable && !(prism_halt | prism_halt_r);

    genvar i;
    generate
    
    // Create Conditional out enable bits
    for (i = 1; i < 4; i = i + 1)
    begin : GEN_COND_OUT_EN
        assign cond_out_en[i] = cond_out_sel == i;    
    end

    // Create shift out enable bits
    for (i = 1; i < 4; i = i + 1)
    begin : GEN_SHIFTS_OUT_EN
        assign shift_out[i] = i == 0 ? 1'b0 : shift_out_sel == i;    
    end

    endgenerate

    // We don't use uo_out0 so it can be used for comms with RISC-V
    // Assign outputs based on conditional enable or latched enable
    // NOTE:  prism_out_data[6] is actually OUT_SHIFT, not a dedicated pin_out
    assign uo_out_c[0]   = (prism_out_data[0]   & ~out0_fifo_full)   | (out0_fifo_full & fifo_full);
    assign uo_out_c[3:1] = (prism_out_data[3:1] & ~cond_out_en[3:1]) | (cond_out_en[3:1] & {3{cond_out[0]}});
    assign uo_out_c[6:4] = (prism_out_data[6:4] & ~shift_out[3:1])   | (shift_out[3:1]   & {3{shift_data}});

    assign uo_out[7:1]   = latched_out;
    assign uo_out[0]     = 1'b0;
    
    // Assign the PRISM intput data
    assign prism_in_data[6:0]   = ui_in[6:0];
    assign prism_in_data[7]     = shift_data;
    assign prism_in_data[9:8]   = host_in;
    assign prism_in_data[10]    = count1 == 0;
    assign prism_in_data[11]    = count2 >= count2_compare;
    assign prism_in_data[13:12] = latch_in_out ? {latched_out[6], latched_out[1]} : latched_in;
    assign prism_in_data[14]    = shift_24_en ? ({fifo_count, shift_count} == 5'b0) : (shift_count == 3'h0);
    assign prism_in_data[15]    = count2 == comm_data;
    assign user_interrupt = prism_interrupt;

    assign shift_data     = shift_24_en ? (shift_dir ? count1[0] : count1[23]) : (shift_dir ? comm_data[0] : comm_data[7]);
    assign fifo_write     = prism_out_data[OUT_COUNT1_LOAD] & fifo_24;// & clk_gate;
    assign fifo_push      = fifo_write && (fifo_count != 2'h2 || (fifo_count == 2'h2 && fifo_read));
    assign fifo_read      = fifo_24 && data_read_n == 2'b00 && address == 6'h19;
    assign fifo_full      = fifo_24 && fifo_count == 2'h2;
    assign fifo_empty     = fifo_24 && fifo_count == 2'h0;
    assign out0_fifo_full = fifo_24 & latch3;

    // Assign shift mode
    assign shift_mode = {shift_24_en, shift_en};
    assign latch_in   = latch3 && prism_out_data[OUT_LATCH2];
    assign shift_24   = shift_mode == 2'b11 && prism_out_data[OUT_SHIFT];
    assign shift_8    = shift_mode == 2'b01 && prism_out_data[OUT_SHIFT];

    always @*
    begin
        case (fifo_rd_ptr)
        2'h0:    fifo_rd_data = count1[7:0];
        2'h1:    fifo_rd_data = count1[15:8];
        2'h2:    fifo_rd_data = count1[23:16];
        default: fifo_rd_data = 8'h0;
        endcase
    end

    // Address 0 reads the example data register.  
    // Address 4 reads ui_in
    // All other addresses read 0.
    always @*
    begin
        case (address)
            6'h0:    data_out = {prism_interrupt, prism_enable, 6'h0,
                                ui_in[7], latched_out,
                                2'h0, latch3, count2_dec, fifo_24, shift_24_en, shift_dir, shift_en,
                                latch_in_out, load4, cond_out_sel, shift_out_sel, shift_in_sel};
            6'h18:   data_out = {6'h0, host_in, 2'h0, fifo_rd_ptr, fifo_wr_ptr, fifo_full, fifo_empty, fifo_rd_data, comm_data};
            6'h19:   data_out = {24'h0, fifo_rd_data};
            6'h1A:   data_out = {24'h0, fifo_count, fifo_rd_ptr, fifo_wr_ptr, fifo_full, fifo_empty};
            6'h1B:   data_out = {30'h0, host_in};
            6'h20:   data_out = {8'h0, count1_preload};
            6'h24:   data_out = {count2, count1};
            6'h28:   data_out = {24'h0, count2_compare};
            default: data_out = prism_read_data;
        endcase
    end

    // All reads complete in 1 clock
    assign data_ready = 1;

    // Assign COMM data in
    assign shift_data_bits = ui_in[3:0];
    assign shift_in        = shift_data_bits[shift_in_sel];
    
    // User interrupt is generated on rising edge of ui_in[6], and cleared by writing a 1 to the low bit of address 8.

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            prism_interrupt <= 1'b0;
            prism_halt_r    <= 1'b0;
            host_in         <= 2'b0;
            comm_data       <= 8'h0;
            `ifndef SYNTH_FPGA
            latch_wr        <= 1'b0;
            latch_wr_p0     <= 1'b0;
            latch_data      <= 32'h0;
            `endif
            fifo_rd_ptr     <= 2'h0;
            fifo_count      <= 2'h0;
        end
        else
        begin
            `ifndef SYNTH_FPGA
            // Create a delayed data_write signal for latches
            latch_wr_p0 <= prism_wr;
            latch_wr    <= latch_wr_p0;

            // Save data_in for latch and config writes
            if (prism_wr)
                latch_data <= data_in;
            `endif

            // Detect rising edge of HALT
            prism_halt_r <= prism_halt;
            
            if ((prism_halt && !prism_halt_r) | (prism_out_data[OUT_COUNT2_CLEAR] & prism_out_data[OUT_COUNT2_INC])) begin
                prism_interrupt <= 1;
            end else if (((address == 6'h3 || count1_toggle_en) && prism_wr) | !prism_enable)
            begin
                // Test for interrupt clear
                if (data_in[7] | !prism_enable | count1_toggle_en)
                    prism_interrupt <= 0;
            end

            // Test for write to PRISM control bits
            if (address == 6'h18 && data_write_n == 2'b10)
                host_in  <= data_in[25:24];
            else if (address == 6'h1b && data_write_n == 2'b00)
                host_in  <= data_in[1:0];
            else if (count1_toggle_en && data_write_n != 2'b11)
                host_in[0] <= ~host_in[0];

            // Latch comm_data
            if (address == 6'h18 && data_write_n != 2'b11)
                comm_data <= data_in[7:0];
            else if (prism_exec && shift_8)// && clk_gate)
                comm_data <= shift_dir ? {shift_in, comm_data[7:1]}: {comm_data[6:0], shift_in};
            else if (load4 & prism_out_data[OUT_LOAD4])
                case (fifo_wr_ptr)
                    2'h0: comm_data <= count1_preload[7:0];
                    2'h1: comm_data <= count1_preload[15:8];
                    2'h2: comm_data <= count1_preload[23:16];
                endcase

            if (prism_exec)
            begin
                // Manage fifo read pointer
                if (fifo_24 && fifo_read && (fifo_count != 2'h0 || fifo_write))
                begin
                    // Increment FIFO read pointer
                    if (fifo_rd_ptr == 2'h2)
                        fifo_rd_ptr <= 2'h0;
                    else
                        fifo_rd_ptr <= fifo_rd_ptr + 1;
                end

                // Manage fifo count
                if (fifo_24)
                begin
                    // Test for write with no read and not full
                    if (fifo_write && !fifo_read && fifo_count != 2'h2)
                        fifo_count <= fifo_count + 1;
                    // Test for read with no write and not empty
                    else if (fifo_read && !fifo_write && fifo_count != 2'h0)
                        fifo_count <= fifo_count - 1;
                end
                else if (shift_24 && shift_count == 3'h7)// && clk_gate)
                    fifo_count <= fifo_count == 2'h2 ? 2'h0 : fifo_count + 1;
            end
            else if (!prism_enable)
            begin
                fifo_count  <= 2'h0;
                fifo_rd_ptr <= 2'h0;
            end
        end
    end

    assign prism_rst_n = rst_n & prism_enable;
    //always @(posedge clk_div2 or negedge prism_rst_n)
    always @(posedge clk or negedge prism_rst_n)
    begin
        if (!prism_rst_n)
        begin
            count1          <= 24'b0;
            count2          <= 8'b0;
            fifo_wr_ptr     <= 2'h0;
            latched_out     <= 7'h0;
            latched_in      <= 2'h0;
            shift_count     <= 3'h0;
        end
        else
        begin
            if (prism_enable && !prism_halt_r)
                latched_out <= uo_out_c;

            // Countdown to zero counter
            if (prism_exec)
            begin
                // Logic for load / decrement of 24-bit countdown counter
                if (prism_out_data[OUT_COUNT1_LOAD] & !fifo_24)
                    count1 <= count1_preload; 

                // Logic to decrement 24-bit counter
                else if (count1 != 0 && prism_out_data[OUT_COUNT1_DEC])
                    count1 <= count1 - 1;

                // Use 24-bit counter as shift-register
                else if (shift_24)
                    count1 <= shift_dir ? {shift_in, count1[23:1]} :  {count1[22:0], shift_in};

                // Use 24-bit counter as 3-byte FIFO
                else if (fifo_push)
                begin
                    // Push data to the fifo
                    case (fifo_wr_ptr)
                    2'h0: count1[7:0]   <= comm_data;
                    2'h1: count1[15:8]  <= comm_data;
                    2'h2: count1[23:16] <= comm_data;
                    default: 
                        begin
                        end
                    endcase

                    // Increment the write pointer
                    if (fifo_wr_ptr == 2'h2)
                        fifo_wr_ptr <= 0;
                    else
                        fifo_wr_ptr <= fifo_wr_ptr + 1;
                end

                // Count the number of shifts
                if (shift_24 | shift_8)
                begin
                    shift_count <= shift_count + 1;
                end
                
                // 8-bit counter
                if (prism_out_data[OUT_COUNT2_CLEAR] && !prism_out_data[OUT_COUNT2_INC])
                    count2 <= 8'h0; 
                else if (prism_out_data[OUT_COUNT2_INC] && !prism_out_data[OUT_COUNT2_CLEAR])
                    count2 <= count2 + 1;
                else if (count2_dec && prism_out_data[OUT_COUNT2_DEC])
                    count2 <= count2 - 1;
                
                // Latch the lower 2 outputs
                if (latch_in)
                begin
                    latched_in  <= {shift_data, cond_out[0]};
                end
            end
        end
    end

    /*
    ==================================================================================
    Instantiate latch based registers
    ==================================================================================
    */
    assign ctrl_reg_en      = address == 6'h00;
    assign count1_reg_en    = address == 6'h20;
    assign count1_toggle_en = address == 6'h21;
    assign count2_reg_en    = address == 6'h28;

    wire [14:0]   ctrl_bits_out;
    wire [14:0]   ctrl_bits_in;

    assign shift_in_sel        = ctrl_bits_out[1:0];
    assign shift_out_sel       = ctrl_bits_out[3:2];
    assign cond_out_sel        = ctrl_bits_out[5:4];
    assign load4               = ctrl_bits_out[6];
    assign latch_in_out        = ctrl_bits_out[7];
    assign shift_en            = ctrl_bits_out[8];
    assign shift_dir           = ctrl_bits_out[9];
    assign shift_24_en         = ctrl_bits_out[10];
    assign fifo_24             = ctrl_bits_out[11];
    assign count2_dec          = ctrl_bits_out[12];
    assign latch3              = ctrl_bits_out[13];
    assign prism_enable        = ctrl_bits_out[14];

    assign ctrl_bits_in[1:0]   = latch_data[1:0];   // shift_in_sel
    assign ctrl_bits_in[3:2]   = latch_data[3:2];   // shift_out_sel
    assign ctrl_bits_in[5:4]   = latch_data[5:4];   // cond_out_sel
    assign ctrl_bits_in[6]     = latch_data[6];     // load4
    assign ctrl_bits_in[7]     = latch_data[7];     // latch_in_out
    assign ctrl_bits_in[8]     = latch_data[8];     // shift_en
    assign ctrl_bits_in[9]     = latch_data[9];     // shift_dir
    assign ctrl_bits_in[10]    = latch_data[10];    // shift_24_en
    assign ctrl_bits_in[11]    = latch_data[11];    // fifo_24
    assign ctrl_bits_in[12]    = latch_data[12];    // count2_dec
    assign ctrl_bits_in[13]    = latch_data[13];    // latch3
    assign ctrl_bits_in[14]    = latch_data[30];    // PRISM enable

`ifndef SYNTH_FPGA
    prism_latch_reg
    #(
        .WIDTH ( 15 )
     )
    ctrl_regs
    (
        .rst_n      ( rst_n         ),
        .enable     ( ctrl_reg_en   ),
        .wr         ( latch_wr      ),
        .data_in    ( ctrl_bits_in  ),
        .data_out   ( ctrl_bits_out )
    );

    prism_latch_reg
    #(
        .WIDTH ( 24 )
     )
    count_preloads
    (
        .rst_n      ( rst_n                            ),
        .enable     ( count1_reg_en                    ),
        .wr         ( latch_wr                         ),
        .data_in    ( latch_data[23:0]                 ),
        .data_out   ( count1_preload                   )
    );

    prism_latch_reg
    #(
        .WIDTH ( 8 )
     )
    count_compare
    (
        .rst_n      ( rst_n                            ),
        .enable     ( count2_reg_en | count1_toggle_en ),
        .wr         ( latch_wr                         ),
        .data_in    ( latch_data[7:0]                  ),
        .data_out   ( count2_compare    )
    );
`else
    reg [31:0] count_preloads;
    reg [14:0] ctrl_reg;
    always @(posedge clk or negedge rst_n)
    begin
        if (~rst_n)
        begin
            ctrl_reg       <= 'h0;
            count_preloads <= 'h0;
        end
        else
        begin
            // Write to control reg
            if (ctrl_reg_en & prism_wr)
                ctrl_reg <= ctrl_bits_in;

            if (count1_reg_en & prism_wr)
                count_preloads[23:0] <= data_in;
            if ((count2_reg_en | count1_toggle_en) & prism_wr)
                count_preloads[31:24] <= data_in;
        end
    end

    assign ctrl_bits_out = ctrl_reg;
    assign {count2_compare, count1_preload} = count_preloads;

`endif


endmodule

// vim: et sw=4 ts=4

