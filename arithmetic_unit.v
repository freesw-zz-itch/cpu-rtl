// ============================================================
// 算术逻辑单元 (ALU) - 5 级流水线版本
// 负责 EX 阶段：ALU 运算 + 产生 EX/MEM 流水线寄存器
// ============================================================

`include "cpu_defines.v"

module arithmetic_unit (
    input  wire        clk,
    input  wire        rst_n,
    // 来自 ID/EX 寄存器
    input  wire [31:0] id_pc,
    input  wire [31:0] id_instr,
    input  wire [31:0] id_rs1,
    input  wire [31:0] id_rs2,
    input  wire [4:0]  id_rd,
    input  wire [31:0] id_imm,
    input  wire        id_valid,
    input  wire        id_is_branch,
    input  wire        id_is_jump,
    input  wire        id_is_load,
    input  wire        id_is_alu,
    // 分支 / 中断输出
    output reg         branch_taken,
    output reg  [31:0] branch_target,
    output reg         int_trigger,
    output reg         iret_trigger,
    // EX/MEM 流水线输出
    output reg  [31:0] alu_result,
    output reg  [31:0] ex_rs2,
    output reg  [4:0]  ex_rd,
    output reg         ex_valid,
    output reg         ex_mem_wr_en,
    output reg         ex_reg_wr_en,
    output reg         ex_is_load,
    output reg         ex_is_alu,
    // 调试
    output wire [31:0] debug_alu
);

    wire [4:0]  opcode    = id_instr[31:27];
    wire [4:0]  rs1_field = id_instr[21:17];
    wire [4:0]  rs2_field = id_instr[16:12];
    reg  [31:0] alu_out;

    wire imm_mode = (rs2_field == `REG_R0);

    // ============================================================
    // ALU 组合运算
    // ============================================================
    always @* begin
        case (opcode)
            `OP_ADD:  alu_out = imm_mode ? (id_rs1 + id_imm) : (id_rs1 + id_rs2);
            `OP_SUB:  alu_out = imm_mode ? (id_rs1 - id_imm) : (id_rs1 - id_rs2);
            `OP_MUL:  alu_out = imm_mode ? (id_rs1 * id_imm) : (id_rs1 * id_rs2);
            `OP_DIV:  alu_out = imm_mode ? ((id_imm==0) ? 32'b0 : id_rs1/id_imm)
                                         : ((id_rs2==0) ? 32'b0 : id_rs1/id_rs2);
            `OP_ADDI: alu_out = id_rs1 + id_imm;
            `OP_SUBI: alu_out = id_rs1 - id_imm;
            `OP_SHL:  alu_out = id_rs1 << id_imm[4:0];
            `OP_SHR:  alu_out = id_rs1 >> id_imm[4:0];
            `OP_AND:  alu_out = imm_mode ? (id_rs1 & id_imm) : (id_rs1 & id_rs2);
            `OP_OR:   alu_out = imm_mode ? (id_rs1 | id_imm) : (id_rs1 | id_rs2);
            `OP_XOR:  alu_out = imm_mode ? (id_rs1 ^ id_imm) : (id_rs1 ^ id_rs2);
            `OP_LW:   alu_out = id_rs1 + id_imm;
            `OP_SW:   alu_out = id_rs1 + id_imm;
            `OP_MOVE: alu_out = (rs1_field == `REG_R0) ? id_imm : id_rs1;
            default:  alu_out = 32'b0;
        endcase
    end

    // ============================================================
    // 分支 / 跳转判断
    // ============================================================
    always @* begin
        branch_taken  = 1'b0;
        branch_target = 32'b0;
        if (id_is_branch && id_valid && (id_rs1 == id_rs2)) begin
            branch_taken  = 1'b1;
            branch_target = id_pc + id_imm;
        end else if (id_is_jump && id_valid) begin
            branch_taken  = 1'b1;
            branch_target = id_imm;
        end
    end

    // ============================================================
    // 中断
    // ============================================================
    always @* begin
        int_trigger  = (opcode == `OP_INT)  && id_valid;
        iret_trigger = (opcode == `OP_IRET) && id_valid;
    end

    assign debug_alu = alu_out;

    // ============================================================
    // EX/MEM 流水线寄存器
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result   <= 32'b0;
            ex_rs2       <= 32'b0;
            ex_rd        <= 5'b0;
            ex_valid     <= 1'b0;
            ex_mem_wr_en <= 1'b0;
            ex_reg_wr_en <= 1'b0;
            ex_is_load   <= 1'b0;
            ex_is_alu    <= 1'b0;
        end else if (id_valid) begin
            alu_result   <= alu_out;
            ex_rs2       <= id_rs2;
            ex_rd        <= id_rd;
            ex_valid     <= 1'b1;
            ex_mem_wr_en <= (opcode == `OP_SW);
            ex_reg_wr_en <= (id_is_alu || id_is_load);
            ex_is_load   <= id_is_load;
            ex_is_alu    <= id_is_alu;
        end else begin
            // 气泡
            alu_result   <= 32'b0;
            ex_rs2       <= 32'b0;
            ex_rd        <= 5'b0;
            ex_valid     <= 1'b0;
            ex_mem_wr_en <= 1'b0;
            ex_reg_wr_en <= 1'b0;
            ex_is_load   <= 1'b0;
            ex_is_alu    <= 1'b0;
        end
    end

endmodule
