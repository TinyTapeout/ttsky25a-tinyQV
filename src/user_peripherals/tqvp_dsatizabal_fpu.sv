`default_nettype none

module tqvp_dsatizabal_fpu (
    input         clk,
    input         rst_n,

    input  [7:0]  ui_in,
    output [7:0]  uo_out,

    input  [5:0]  address,
    input  [31:0] data_in,
    input  [1:0]  data_write_n,
    input  [1:0]  data_read_n,
    output [31:0] data_out,
    output        data_ready
);

    // === Memory-mapped Registers ===
    reg [15:0] operand_a;
    reg [15:0] operand_b;
    reg [2:0]  operation;

    reg        busy;
    reg        valid_in;

    reg [15:0] result;
    reg        ready;

    // === FSM States ===
    typedef enum logic [2:0] {
        IDLE            = 3'b000,
        READING         = 3'b001,
        OPERANDS_READY  = 3'b010,
        CALCULATING     = 3'b011,
        WRITING         = 3'b100
    } fpu_state_t;

    reg[1:0] state;

    // === FPU Operations ===
    typedef enum logic [2:0] {
        ADD     = 3'b000,
        SUB     = 3'b001,
        MULT    = 3'b010
    } fpu_operations_t;

    // === Muxed B for subtract
    wire [15:0] b_muxed = (operation == SUB) ? {~operand_b[15], operand_b[14:0]} : operand_b;

    // === Pipelined Adder ===
    wire [15:0] add_result;
    wire        add_valid_out;

    fpu_adder add_inst (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in && (operation == ADD || operation == SUB) && (state == OPERANDS_READY)),
        .a(operand_a),
        .b(b_muxed),
        .valid_out(add_valid_out),
        .result(add_result)
    );

    // === Pipelined Multiplier ===
    wire [15:0] mul_result;
    wire        mul_valid_out;

    fpu_mult mul_inst (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in && (operation == MULT) && (state == OPERANDS_READY)),
        .a(operand_a[15:0]),
        .b(operand_b[15:0]),
        .valid_out(mul_valid_out),
        .result(mul_result)
    );

    // === Write Logic & FSM ===
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a     <= 0;
            operand_b     <= 0;
            operation     <= 0;
            valid_in      <= 0;
            busy          <= 0;
            state         <= IDLE;
            result        <= 0;
            ready         <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (data_write_n != 2'b11) begin
                        if (address[1:0] == 2'b00) begin
                            operation    <= address[4:2];
                            operand_a    <= data_in;
                            ready        <= 0;
                            busy         <= 1;
                            state        <= READING;
                        end
                    end
                end

                READING: begin
                    if (data_write_n != 2'b11) begin
                        if (address[1:0] == 2'b01) begin
                            operand_b    <= data_in;
                            state        <= OPERANDS_READY;
                            valid_in     <= 1;
                        end
                    end
                end

                OPERANDS_READY: begin
                    state        <= CALCULATING;
                end

                CALCULATING: begin
                    if (add_valid_out) begin
                        result <= add_result;
                        state  <= IDLE;
                        ready  <= 1;
                        busy   <= 0;
                    end else if (mul_valid_out) begin
                        result <= mul_result;
                        state  <= IDLE;
                        ready  <= 1;
                        busy   <= 0;
                    end
                end
            endcase
        end
    end

    // === Read Logic ===
    // === Read Logic ===
    assign data_out = (address == 6'h00) ? { 16'b0, operand_a } :
                      (address == 6'h04) ? { 16'b0, operand_b } :
                      (address == 6'h08) ? {29'b0, operation} : // TODO: do I need to add control signals?
                      (address == 6'h0C) ? result :
                      (address == 6'h10) ? {31'b0, busy} :
                      32'h0;

    assign data_ready       = ready;

    assign uo_out           = 0;

endmodule
