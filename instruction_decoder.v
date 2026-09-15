// ============================================================
// 指令译码器 - 5 级流水线
// 输出 ID/EX 流水线寄存器
// 停顿/flush 时插入气泡
// ============================================================

`include "cpu_defines.v"

module instruction_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_instr,
    input  wire        if_valid,
    input  wire        stall,
    input  wire        flush,
    // 寄存器读端口
    output wire [4:0]  reg_rd_addr_a,
    output wire [4:0]  reg_rd_addr_b,
    input  wire [31:0] reg_rd_data_a,
    input  wire [31:0] reg_rd_data_b,
    // 前推数据 (EX/MEM 和 MEM/WB)
    input  wire [31:0] fwd_alu_ex,      // EX/MEM 结果
    input  wire [31:0] fwd_alu_mem,     // MEM/WB 结果
    input  wire [4:0]  fwd_rd_ex,       // EX/MEM rd
    input  wire [4:0]  fwd_rd_mem,      // MEM/WB rd
    input  wire        fwd_valid_ex,
    input  wire        fwd_valid_mem,
    input  wire        fwd_wr_en_ex,
    input  wire        fwd_wr_en_mem,
    input  wire [1:0]  fwd_a,
    input  wire [1:0]  fwd_b,
    // 输出到 EX
    output reg  [31:0] id_pc,
    output reg  [31:0] id_instr,
    output reg  [31:0] id_rs1,
    output reg  [31:0] id_rs2,
    output reg  [4:0]  id_rd,
    output reg  [31:0] id_imm,
    output reg         id_valid,
    output reg         id_is_branch,
    output reg         id_is_jump,
    output reg         id_is_load,
    output reg         id_is_alu
);

    wire [4:0]  opcode = if_instr[31:27];
    wire [4:0]  rd     = if_instr[26:22];
    wire [4:0]  rs1    = if_instr[21:17];
    wire [4:0]  rs2    = if_instr[16:12];
    wire [11:0] imm    = if_instr[11:0];

    wire signed [31:0] imm_se = {{20{imm[11]}}, imm};

    wire is_branch = (opcode == `OP_BEQ);
    wire is_jump   = (opcode == `OP_JMP);
    wire is_load   = (opcode == `OP_LW);
    wire is_alu    = `IS_ALU_OP(opcode);

    // 分支/跳转不进入 ID/EX
    wire id_valid_next = if_valid && !is_branch && !is_jump;

    assign reg_rd_addr_a = rs1;
    assign reg_rd_addr_b = rs2;

    reg [31:0] rs1_val, rs2_val;

    // 前推 MUX
    always @* begin
        case (fwd_a)
            `FWD_NONE: rs1_val = reg_rd_data_a;
            `FWD_EX:   rs1_val = fwd_alu_ex;
            `FWD_MEM:  rs1_val = fwd_alu_mem;
            default:   rs1_val = reg_rd_data_a;
        endcase
    end

    always @* begin
        case (fwd_b)
            `FWD_NONE: rs2_val = reg_rd_data_b;
            `FWD_EX:   rs2_val = fwd_alu_ex;
            `FWD_MEM:  rs2_val = fwd_alu_mem;
            default:   rs2_val = reg_rd_data_b;
        endcase
    end

    // ============================================================
    // ID/EX 流水线寄存器
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc        <= 32'b0;
            id_instr     <= 32'b0;
            id_rs1       <= 32'b0;
            id_rs2       <= 32'b0;
            id_rd        <= 5'b0;
            id_imm       <= 32'b0;
            id_valid     <= 1'b0;
            id_is_branch <= 1'b0;
            id_is_jump   <= 1'b0;
            id_is_load   <= 1'b0;
            id_is_alu    <= 1'b0;
        end else if (flush || stall) begin
            // 插入气泡
            id_pc        <= 32'b0;
            id_instr     <= 32'b0;
            id_rs1       <= 32'b0;
            id_rs2       <= 32'b0;
            id_rd        <= 5'b0;
            id_imm       <= 32'b0;
            id_valid     <= 1'b0;
            id_is_branch <= 1'b0;
            id_is_jump   <= 1'b0;
            id_is_load   <= 1'b0;
            id_is_alu    <= 1'b0;
        end else if (if_valid) begin
            id_pc        <= if_pc;
            id_instr     <= if_instr;
            id_rs1       <= rs1_val;
            id_rs2       <= rs2_val;
            id_rd        <= rd;
            id_imm       <= imm_se;
            id_valid     <= id_valid_next;
            id_is_branch <= is_branch;
            id_is_jump   <= is_jump;
            id_is_load   <= is_load;
            id_is_alu    <= is_alu;
        end
    end

endmodule
