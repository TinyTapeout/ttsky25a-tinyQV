`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 38 and change tqvp_example to your chosen module name.
module tqvp_htfab_vga_tester (
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

reg [7:0] params [15:0];
reg redraw;

always @(posedge clk) begin
    if (!rst_n) begin
        params[0] <= 8'b0;
        params[1] <= 8'b0;
        params[2] <= 8'b0;
        params[3] <= 8'b0;
        params[4] <= 8'b0;
        params[5] <= 8'b0;
        params[6] <= 8'b0;
        params[7] <= 8'b0;
        params[8] <= 8'b0;
        params[9] <= 8'b0;
        params[10] <= 8'b0;
        params[11] <= 8'b0;
        params[12] <= 8'b0;
        params[13] <= 8'b0;
        params[14] <= 8'b0;
        params[15] <= 8'b0;
        redraw <= 1'b1;
    end else if (data_write) begin
        params[address] <= data_in;
        redraw <= 1'b1;
    end else begin
        redraw <= 1'b0;
    end
end

assign data_out = params[address];

reg [1:0] h_phase;
reg [12:0] h_pos;
reg [12:0] h_rem;
reg h_sync_bit;
reg h_active;
reg h_advance;

reg [1:0] v_phase;
reg [12:0] v_pos;
reg [12:0] v_rem;
reg v_sync_bit;
reg v_active;
reg v_advance;

reg [12:0] frame;

// v_advance & frame are unused and will be optimized out,
// but were kept for symmetry between horizontal & vertical logic

always @(posedge clk) begin
    if (!rst_n || redraw) begin
        h_phase <= 2'd0;
        h_pos <= 13'd0;
        {h_sync_bit, h_active, h_advance, h_rem} <= {params[0], params[1]};
        v_phase <= 2'd0;
        v_pos <= 13'd0;
        {v_sync_bit, v_active, v_advance, v_rem} <= {params[8], params[9]};
        frame <= 13'd0;
    end else begin
        if (h_rem == 1) begin
            h_pos <= 13'd0;
            case (h_phase)
                2'd0: {h_sync_bit, h_active, h_advance, h_rem} <= {params[2], params[3]};
                2'd1: {h_sync_bit, h_active, h_advance, h_rem} <= {params[4], params[5]};
                2'd2: {h_sync_bit, h_active, h_advance, h_rem} <= {params[6], params[7]};
                2'd3: {h_sync_bit, h_active, h_advance, h_rem} <= {params[0], params[1]};
            endcase
            h_phase <= h_phase+1;
            if (h_advance) begin
                if (v_rem == 1) begin
                    v_pos <= 13'd0;
                    case (v_phase)
                        2'd0: {v_sync_bit, v_active, v_advance, v_rem} <= {params[10], params[11]};
                        2'd1: {v_sync_bit, v_active, v_advance, v_rem} <= {params[12], params[13]};
                        2'd2: {v_sync_bit, v_active, v_advance, v_rem} <= {params[14], params[15]};
                        2'd3: {v_sync_bit, v_active, v_advance, v_rem} <= {params[8], params[9]};
                    endcase
                    v_phase <= v_phase+1;
                    if (v_advance) begin
                        frame <= frame+1;
                    end                    
                end else begin
                    v_pos <= v_pos+1;
                    v_rem <= v_rem-1;
                end
            end            
        end else begin
            h_pos <= h_pos+1;
            h_rem <= h_rem-1;
        end
    end
end

wire active = h_active && v_active;
wire edge_1 = (h_pos < 1) || (v_pos < 1) || (h_rem <= 1) || (v_rem <= 1);
wire edge_2 = (h_pos < 2) || (v_pos < 2) || (h_rem <= 2) || (v_rem <= 2);
wire edge_override = edge_2;
wire [1:0] edge_value = edge_1 ? 2'b11 : 2'b00;

wire [1:0] vga_red = active ? (edge_override ? edge_value : {h_pos[7], v_pos[7]}) : 2'b00;
wire [1:0] vga_green = active ? (edge_override ? edge_value : {h_pos[6], v_pos[8]}) : 2'b00;
wire [1:0] vga_blue = active ? (edge_override ? edge_value : {v_pos[6], h_pos[8]}) : 2'b00;
wire vga_hsync = h_sync_bit;
wire vga_vsync = v_sync_bit;

assign uo_out = {vga_hsync, vga_blue[0], vga_green[0], vga_red[0],
                 vga_vsync, vga_blue[1], vga_green[1], vga_red[1]};

wire _unused = &{ui_in, 1'b0};

endmodule
