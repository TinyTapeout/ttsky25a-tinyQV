module char_rom_cc #(
    parameter DATA_WIDTH = 35,     // Width of ROM data (35 bits for each character)
    parameter ADDR_WIDTH = 7,      // Address width
    parameter ADDR_MIN = 32,
    parameter ADDR_MAX = 127
)(
    input wire [ADDR_WIDTH-1:0] address,
    output wire [DATA_WIDTH-1:0] data
);

// The ROM has been optimized for gate count. The 96 printable ASCII characters
// have been remapped to minimize logic complexity. The mapping is inverted
// by the LUT below. The space taken by the remapped ROM and the LUT is smaller
// than the space taken by the original ROM.

reg [DATA_WIDTH-1:0] mem [0:ADDR_MAX-ADDR_MIN];
initial begin
    $readmemb("font_vgaconsole.bin", mem);  // load char bitmaps from file
end

reg [6:0] row_lut_inv [0:95];
initial begin
    $readmemh("vgaconsole_lut.mem", row_lut_inv); // row remapping
end

wire [ADDR_WIDTH-1:0] phys;
assign phys = (|address[ADDR_WIDTH-1:5]) ? row_lut_inv[address-ADDR_MIN] : 7'd95;

assign data = mem[phys];

endmodule
