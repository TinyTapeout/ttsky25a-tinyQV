/*
 * Copyright (c) 2025 Rebecca G. Bettencourt
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

(* keep_hierarchy *)
module tqvp_rebeccargb_hardware_utf8 (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.
    input  [7:0]  ui_in,        // The input PMOD.  Note that ui_in[7] is normally used for UART RX.
    output [7:0]  uo_out,       // The output PMOD.  Note that uo_out[0] is normally used for UART TX.
    input  [3:0]  address,      // Address within this peripheral's address space
    input         data_write,   // Data write request from the TinyQV core.
    input  [7:0]  data_in,      // Data in to the peripheral, valid when data_write is high.
    output [7:0]  data_out      // Data out from the peripheral, set this in accordance with the supplied address
);

    // ******** BEGIN UTF8.V ******** //

    wire [7:0] din = data_in;

    reg [7:0] dout; // latched data output
    reg chk_range;  // restrict valid characters to 0-0x10FFFF
    reg cbe;        // I/O is big endian
    reg retry;      // consume output, reset, and try same input again

    reg empty;      // no data has been received since last reset
    reg [31:0] rc;  // character register
    reg [2:0] rcip; // UTF-32 input length
    reg [2:0] rcop; // UTF-32 output pointer
    reg [2:0] rbop; // UTF-8 output pointer
    reg [2:0] ruop; // UTF-16 output pointer

    // UTF-8 input length
    wire [2:0] rbip = (
        empty ? 0 :
        (rc < 32'h00000080 || rc >= 32'hFFFFFF80) ? 1 :
        (rc < 32'h00000800 || rc >= 32'hFFFFF000) ? 2 :
        (rc < 32'h00010000 || rc >= 32'hFFFE0000) ? 3 :
        (rc < 32'h00200000 || rc >= 32'hFFC00000) ? 4 :
        (rc < 32'h04000000 || rc >= 32'hF8000000) ? 5 :
        (rc < 32'h80000000 || rc >= 32'hF0000000) ? 6 :
        0
    );

    // UTF-16 input length
    wire [2:0] ruip = (
        empty ? 0 :
        (rc < 32'h00010000) ? 2 :
        (rc < 32'h00110000) ? 4 :
        (rc < 32'hDDD80000) ? 0 :
        (rc < 32'hDDDC0000) ? 3 :
        (rc < 32'hDDDDDD00) ? 0 :
        (rc < 32'hDDDDDE00) ? 1 :
        0
    );

    wire bout_eof = (rbop >= rbip);
    wire uout_eof = (ruop >= ruip);

    wire [3:0] status = (
        empty ? 0 :
        (rc < 32'h00110000) ? 4'b1000 : // READY
        (rc < 32'h80000000) ? 4'b1001 : // READY, NONUNI
        (rc < 32'hDDD80000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hDDDC0000) ? 4'b0000 : // UNDERFLOW (UTF-16, 3 bytes)
        (rc < 32'hDDDDDD00) ? 4'b1100 : // READY, INVALID
        (rc < 32'hDDDDDE00) ? 4'b0000 : // UNDERFLOW (UTF-16, 1 byte)
        (rc < 32'hF0000000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hF4000000) ? 4'b1010 : // READY, OVERLONG (6 bytes)
        (rc < 32'hF8000000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hF8200000) ? 4'b1010 : // READY, OVERLONG (5 bytes)
        (rc < 32'hFC000000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hFE000000) ? 4'b0000 : // UNDERFLOW (UTF-8, 5 bytes)
        (rc < 32'hFFC00000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hFFC10000) ? 4'b1010 : // READY, OVERLONG (4 bytes)
        (rc < 32'hFFE00000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hFFF80000) ? 4'b0000 : // UNDERFLOW (UTF-8, 4 bytes)
        (rc < 32'hFFFE0000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hFFFE0800) ? 4'b1010 : // READY, OVERLONG (3 bytes)
        (rc < 32'hFFFF0000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hFFFFE000) ? 4'b0000 : // UNDERFLOW (UTF-8, 3 bytes)
        (rc < 32'hFFFFF000) ? 4'b1100 : // READY, INVALID
        (rc < 32'hFFFFF080) ? 4'b1010 : // READY, OVERLONG (2 bytes)
        (rc < 32'hFFFFF800) ? 4'b1100 : // READY, INVALID
        (rc < 32'hFFFFFF80) ? 4'b0000 : // UNDERFLOW (UTF-8, 2 bytes)
        (rc < 32'hFFFFFFC0) ? 4'b1100 : // READY, INVALID
        (rc < 32'hFFFFFFFE) ? 4'b0000 : // UNDERFLOW (UTF-8, 1 byte)
        4'b1100 // READY, INVALID
    );

    wire ready = status[3];
    wire invalid = status[2];
    wire overlong = status[1];
    wire nonuni = status[0];
    wire error = (retry | invalid | overlong | (nonuni & chk_range));

    wire [5:0] props = (
        (empty || rc[31]) ? 0 :
        (rc < 32'h00000020) ? 6'b010000 : // CONTROL
        (rc < 32'h0000007F) ? 6'b100000 : // NORMAL
        (rc < 32'h000000A0) ? 6'b010000 : // CONTROL
        (rc < 32'h0000D800) ? 6'b100000 : // NORMAL
        (rc < 32'h0000DB80) ? 6'b001100 : // SURROGATE, HIGHCHAR
        (rc < 32'h0000DC00) ? 6'b001110 : // SURROGATE, HIGHCHAR, PRIVATE
        (rc < 32'h0000E000) ? 6'b001000 : // SURROGATE
        (rc < 32'h0000F900) ? 6'b000010 : // PRIVATE
        (rc < 32'h0000FDD0) ? 6'b100000 : // NORMAL
        (rc < 32'h0000FDF0) ? 6'b000001 : // NONCHAR
        (rc < 32'h0000FFFE) ? 6'b100000 : // NORMAL
        (rc < 32'h00010000) ? 6'b000001 : // NONCHAR
        (chk_range && rc >= 32'h00110000) ? 0 :
        (rc[15:0] >= 16'hFFFE) ? 6'b000101 : // HIGHCHAR, NONCHAR
        (rc < 32'h000F0000) ? 6'b100100 : // NORMAL, HIGHCHAR
        6'b000110 // HIGHCHAR, PRIVATE
    );

    wire normal = props[5];
    wire control = props[4];
    wire surrogate = props[3];
    wire highchar = props[2];
    wire private = props[1];
    wire nonchar = props[0];

    task reset_all; begin
        // reset all registers
        empty <= 1;
        rc <= 0;
        rcip <= 0;
        rcop <= 0;
        rbop <= 0;
        ruop <= 0;
        dout <= 0;
        retry <= 0;
    end endtask

    task reset_read; begin
        // reset only read pointers
        rcop <= 0;
        rbop <= 0;
        ruop <= 0;
        dout <= 0;
    end endtask

    task write_utf32; begin
        // write 8 bits to character register
        if (rcip == 0) begin
            empty <= 0;
            rc <= {24'b0, din};
            rcip <= 1;
        end else if (rcip >= 4) begin
            retry <= 1;
        end else begin
            case (rcip)
                1: rc <= {16'b0, (cbe ? {rc[7:0], din} : {din, rc[7:0]})};
                2: rc <= {8'b0, (cbe ? {rc[15:0], din} : {din, rc[15:0]})};
                3: rc <= (cbe ? {rc[23:0], din} : {din, rc[23:0]});
            endcase
            rcip <= rcip + 1;
        end
    end endtask

    task read_utf32; begin
        // read 8 bits from character register
        if (rcop >= 4) begin
            dout <= 0;
        end else begin
            case (rcop)
                0: dout <= cbe ? rc[31:24] : rc[7:0];
                1: dout <= cbe ? rc[23:16] : rc[15:8];
                2: dout <= cbe ? rc[15:8] : rc[23:16];
                3: dout <= cbe ? rc[7:0] : rc[31:24];
            endcase
            rcop <= rcop + 1;
        end
    end endtask

    task write_utf8; begin
        // write UTF-8 byte to character register
        if (rbip == 0) begin
            empty <= 0;
            rc <= {{24{din[7]}}, din};
        end else if (ready || (din[7:6] != 2'b10)) begin
            retry <= 1;
        end else begin
            case (rbip)
                1: rc <= &{rc[31:6], ~rc[5], |rc[4:1]} ? {21'b0, rc[4:0], din[5:0]} : {rc[25:0], din[5:0]};
                2: rc <= &{rc[31:11], ~rc[10], |rc[9:5]} ? {16'b0, rc[9:0], din[5:0]} : {rc[25:0], din[5:0]};
                3: rc <= &{rc[31:16], ~rc[15], |rc[14:10]} ? {11'b0, rc[14:0], din[5:0]} : {rc[25:0], din[5:0]};
                4: rc <= &{rc[31:21], ~rc[20], |rc[19:15]} ? {6'b0, rc[19:0], din[5:0]} : {rc[25:0], din[5:0]};
                5: rc <= &{rc[31:26], ~rc[25], |rc[24:20]} ? {1'b0, rc[24:0], din[5:0]} : {4'hF, rc[21:0], din[5:0]};
            endcase
        end
    end endtask

    task read_utf8; begin
        // read UTF-8 byte from character register
        if (rbop >= rbip) begin
            dout <= 0;
        end else if (rbop == 0) begin
            case (rbip)
                1: dout <= rc[7:0];
                2: dout <= {2'b11, rc[11:6]};
                3: dout <= {3'b111, rc[16:12]};
                4: dout <= {4'b1111, rc[21:18]};
                5: dout <= {5'b11111, rc[26:24]};
                6: dout <= {7'b1111110, (rc[31] ? 1'b0 : rc[30])};
            endcase
            rbop <= 1;
        end else begin
            case (rbip - rbop)
                1: dout <= {2'b10, rc[5:0]};
                2: dout <= {2'b10, rc[11:6]};
                3: dout <= {2'b10, rc[17:12]};
                4: dout <= {2'b10, rc[23:18]};
                5: dout <= {2'b10, (rc[31] ? 2'b0 : rc[29:28]), rc[27:24]};
            endcase
            rbop <= rbop + 1;
        end
    end endtask

    // value for low surrogate after consuming the next 8 bits from din
    wire [15:0] lsin = (cbe ? {rc[7:0], din} : {din, rc[7:0]});

    task write_utf16; begin
        // write UTF-16 byte to character register
        if (ruip == 0) begin
            empty <= 0;
            rc <= {24'hDDDDDD, din};
        end else if (ruip >= 4) begin
            retry <= 1;
        end else begin
            case (ruip)
                // 1-byte truncated UTF-16 input
                1: rc <= {16'b0, lsin};
                // 2-byte UTF-16 input; rc must be a high surrogate
                2: if (rc >= 32'hD800 && rc < 32'hDC00) begin
                    rc <= {8'hDD, rc[15:0], din};
                end else begin
                    retry <= 1;
                end
                // 3-byte truncated UTF-16 input; lsin must be a low surrogate
                3: if (lsin[15:10] == 6'b110111) begin
                    // decode surrogate pair
                    rc <= {11'b0, {1'b0, rc[17:14]} + 5'b1, rc[13:8], lsin[9:0]};
                end else begin
                    // revert to unpaired high surrogate
                    // signal for retry
                    rc <= {16'b0, rc[23:8]};
                    retry <= 1;
                end
            endcase
        end
    end endtask

    wire [15:0] hs = {6'b110110, (rc[19:16]-4'b1), rc[15:10]}; // high surrogate
    wire [15:0] ls = {6'b110111, rc[9:0]}; // low surrogate

    task read_utf16; begin
        // read UTF-16 byte from character register
        if (ruop >= ruip) begin
            dout <= 0;
        end else begin
            case (ruip)
                // 1-byte incomplete UTF-16 input
                1: dout <= rc[7:0];
                // BMP character
                2: case (ruop)
                    0: dout <= cbe ? rc[15:8] : rc[7:0];
                    1: dout <= cbe ? rc[7:0] : rc[15:8];
                endcase
                // 3-byte incomplete UTF-16 input
                3: case (ruop)
                    0: dout <= cbe ? rc[23:16] : rc[15:8];
                    1: dout <= cbe ? rc[15:8] : rc[23:16];
                    2: dout <= rc[7:0];
                endcase
                // non-BMP character - encode as surrogate pair
                4: case (ruop)
                    0: dout <= cbe ? hs[15:8] : hs[7:0];
                    1: dout <= cbe ? hs[7:0] : hs[15:8];
                    2: dout <= cbe ? ls[15:8] : ls[7:0];
                    3: dout <= cbe ? ls[7:0] : ls[15:8];
                endcase
            endcase
            ruop <= ruop + 1;
        end
    end endtask

    // ******** END UTF8.V ******** //

    always @(posedge clk) begin
        if (!rst_n) begin
            cbe <= 1; chk_range <= 1; reset_all;
        end else if (data_write) begin
            if (address[3]) begin
                // direct write to character register
                retry <= 0; empty <= 0; rcip <= 4;
                case (address[1:0])
                    0: if (cbe) rc[31:24] <= din; else rc[7:0] <= din;
                    1: if (cbe) rc[23:16] <= din; else rc[15:8] <= din;
                    2: if (cbe) rc[15:8] <= din; else rc[23:16] <= din;
                    3: if (cbe) rc[7:0] <= din; else rc[31:24] <= din;
                endcase
            end else begin
                // write to virtual register
                case (address[2:0])
                    0: begin cbe <= din[3]; chk_range <= din[2]; reset_all; end
                    1: write_utf32;
                    2: write_utf16;
                    3: write_utf8;
                    4: begin cbe <= din[3]; chk_range <= din[2]; reset_read; end
                    5: read_utf32;
                    6: read_utf16;
                    7: read_utf8;
                endcase
            end
        end
    end

    // All output pins must be assigned. If not used, assign to 0.
    assign uo_out = 0;

    wire [7:0] rcread = (
        // direct read from character register
        address[1] ? (address[0] ? (cbe ? rc[ 7:0 ] : rc[31:24])
                                 : (cbe ? rc[15:8 ] : rc[23:16]))
                   : (address[0] ? (cbe ? rc[23:16] : rc[15:8 ])
                                 : (cbe ? rc[31:24] : rc[ 7:0 ]))
    );

    wire [7:0] rvread = (
        // read from virtual register
        address[1] ? (address[0] ? ({(bout_eof &~ empty), 4'h0, rbip})
                                 : ({(uout_eof &~ empty), 4'h0, ruip}))
                   : (address[0] ? ({2'b00, nonchar, private, highchar, surrogate, control, normal})
                                 : ({2'b00, error, nonuni, overlong, invalid, retry, ready}))
    );

    assign data_out = (address[3] ? rcread : address[2] ? dout : rvread);

    // List all unused inputs to prevent warnings
    wire _unused = &{ui_in, 1'b0};

endmodule
