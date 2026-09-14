// ============================================================
// 算术逻辑单元 (ALU)
// 运算 + 分支目标计算 + 访存地址计算
// 支持立即数模式: 当 rs2 == 0 时，使用立即数
// ============================================================

`include "cpu_defines.v"

module arithmetic_unit (
    input  wire        clk,
    input  wire        rst_n,
    // 来自译码阶段的输入
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
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] dmem_rd_data,
    // 数据存储器接口
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wr_data,
    output wire        dmem_wr_en,
    // 分支控制 (输出到IF)
    output reg         branch_taken,
    output reg  [31:0] branch_target,
    // 中断控制
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
    output reg [31:0]  fwd_alu_ex,
    output reg [31:0]  fwd_alu_mem,
    output reg [4:0]   fwd_rd_ex,
    // 调试
    output wire [31:0] debug_alu
);

    wire [4:0]  opcode = id_instr[31:27];
    wire [4:0]  rs1_field = id_instr[21:17];
    wire [4:0]  rs2_field = id_instr[16:12];
    reg  [31:0] alu_out;
    
    // 辅助信号
    wire imm_mode = (rs2_field == `REG_R0);
    wire is_sw    = (opcode == `OP_SW);

    // ============================================================
    // ALU 运算
    // ============================================================
    always @* begin
        case (opcode)
            // ============================================================
            // ADD: 加法
            // ============================================================
            `OP_ADD: begin
                if (imm_mode)
                    alu_out = $signed(id_rs1) + $signed(id_imm);
                else
                    alu_out = $signed(id_rs1) + $signed(id_rs2);
            end

            // ============================================================
            // SUB: 减法
            // ============================================================
            `OP_SUB: begin
                if (imm_mode)
                    alu_out = $signed(id_rs1) - $signed(id_imm);
                else
                    alu_out = $signed(id_rs1) - $signed(id_rs2);
            end

            // ============================================================
            // MUL: 乘法
            // ============================================================
            `OP_MUL: begin
                if (imm_mode)
                    alu_out = $signed(id_rs1) * $signed(id_imm);
                else
                    alu_out = $signed(id_rs1) * $signed(id_rs2);
            end

            // ============================================================
            // DIV: 除法
            // ============================================================
            `OP_DIV: begin
                if (imm_mode)
                    alu_out = (id_imm == 0) ? 32'b0 : $signed(id_rs1) / $signed(id_imm);
                else
                    alu_out = (id_rs2 == 0) ? 32'b0 : $signed(id_rs1) / $signed(id_rs2);
            end

            // ============================================================
            // ADDI: 立即数加法
            // ============================================================
            `OP_ADDI: begin
                alu_out = $signed(id_rs1) + $signed(id_imm);
            end

            // ============================================================
            // SUBI: 立即数减法
            // ============================================================
            `OP_SUBI: begin
                alu_out = $signed(id_rs1) - $signed(id_imm);
            end

            // ============================================================
            // SHL: 逻辑左移
            // ============================================================
            `OP_SHL: alu_out = id_rs1 << id_imm[4:0];

            // ============================================================
            // SHR: 逻辑右移
            // ============================================================
            `OP_SHR: alu_out = id_rs1 >> id_imm[4:0];

            // ============================================================
            // AND: 按位与
            // ============================================================
            `OP_AND: begin
                if (imm_mode)
                    alu_out = id_rs1 & id_imm;
                else
                    alu_out = id_rs1 & id_rs2;
            end

            // ============================================================
            // OR: 按位或
            // ============================================================
            `OP_OR: begin
                if (imm_mode)
                    alu_out = id_rs1 | id_imm;
                else
                    alu_out = id_rs1 | id_rs2;
            end

            // ============================================================
            // XOR: 按位异或
            // ============================================================
            `OP_XOR: begin
                if (imm_mode)
                    alu_out = id_rs1 ^ id_imm;
                else
                    alu_out = id_rs1 ^ id_rs2;
            end

            // ============================================================
            // LW: 加载字 (地址计算)
            // ============================================================
            `OP_LW: alu_out = id_rs1 + id_imm;

            // ============================================================
            // SW: 存储字 (地址计算)
            // ============================================================
            `OP_SW: alu_out = id_rs1 + id_imm;

            // ============================================================
            // MOVE: 数据移动
            // ============================================================
            `OP_MOVE: begin
                if (rs1_field == `REG_R0)
                    alu_out = id_imm;   // MOVE Rd, #imm
                else
                    alu_out = id_rs1;   // MOVE Rd, Rs1
            end

            // ============================================================
            // 默认: 输出 0
            // ============================================================
            default: alu_out = 32'b0;
        endcase
    end

    // ============================================================
    // 分支/跳转逻辑
    // ============================================================
    always @* begin
        branch_taken = 1'b0;
        branch_target = 32'b0;
        if (id_is_branch && id_valid && id_rs1 == id_rs2) begin
            branch_taken = 1'b1;
            branch_target = id_pc + id_imm;
        end else if (id_is_jump && id_valid) begin
            branch_taken = 1'b1;
            branch_target = id_imm;
        end
    end

    // ============================================================
    // 中断控制
    // ============================================================
    always @* begin
        int_trigger  = (opcode == `OP_INT)  && id_valid;
        iret_trigger = (opcode == `OP_IRET) && id_valid;
    end

    // ============================================================
    // 数据存储器接口
    // ============================================================
    assign dmem_addr    = alu_out;
    assign dmem_wr_data = id_rs2;
    assign dmem_wr_en   = (opcode == `OP_SW) && id_valid;
    assign debug_alu    = alu_out;

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
        end
    end

    // ============================================================
    // 前推数据到 EX/MEM 阶段
    // ============================================================
    always @(*) begin
        if (!rst_n) begin
            fwd_alu_ex  <= 32'b0;
            fwd_alu_mem <= 32'b0;
            fwd_rd_ex   <= 5'b0;
        end else if (id_valid) begin
            fwd_alu_ex  <= alu_out;
            fwd_alu_mem <= alu_result;
            fwd_rd_ex   <= id_rd;
        end
    end

endmodule
