// ============================================================
// 核心 CPU 模块 - 5 级流水线
// IF → ID → EX → MEM → WB
// 使用 memory_access 作为主 MEM/WB 寄存器
// 使用 result_writer 作为备用 MEM/WB 寄存器（对照）
// ============================================================

`include "cpu_defines.v"

module cpu_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq,
    input  wire        pause,
    // 测试接口: 寄存器
    input  wire        test_reg_wr_en,
    input  wire [4:0]  test_reg_addr,
    input  wire [31:0] test_reg_wr_data,
    output wire [31:0] test_reg_rd_data,
    // 测试接口: 内存
    input  wire        test_mem_wr_en,
    input  wire [31:0] test_mem_addr,
    input  wire [31:0] test_mem_wr_data,
    output wire [31:0] test_mem_rd_data,
    // 调试
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instr,
    output wire [31:0] debug_alu_result
);

    // ============================================================
    // 内部寄存器
    // ============================================================
    reg [31:0] pc;
    reg [31:0] status;

    // IF/ID
    reg [31:0] ifidinstr;
    reg [31:0] ifidpc;
    reg        ifidvalid;

    // 中断状态
    reg         irq_active;

    // 测试接口
    reg [31:0] test_reg_read_data;

    // ============================================================
    // Wire 声明
    // ============================================================

    // IF <-> ID
    wire [31:0] if_pc, if_instr;
    wire        if_valid;

    // ID <-> EX (来自 instruction_decoder 的 ID/EX 寄存器)
    wire [31:0] id_pc, id_instr, id_rs1, id_rs2, id_imm;
    wire [4:0]  id_rd;
    wire        id_valid;
    wire        id_is_branch, id_is_jump, id_is_load, id_is_alu;

    // EX/MEM 输出 (来自 arithmetic_unit)
    wire [31:0] ex_alu_result, ex_rs2;
    wire [4:0]  ex_rd;
    wire        ex_valid, ex_mem_wr_en, ex_reg_wr_en, ex_is_load, ex_is_alu;
    wire        int_trigger, iret_trigger;

    // MEM/WB 输出 (来自 memory_access)
    wire [31:0] mem_result;
    wire [4:0]  mem_rd;
    wire        mem_valid, mem_wr_en;

    // MEM/WB 备用输出 (来自 result_writer)
    wire [31:0] wb_result_alt;
    wire [4:0]  wb_rd_alt;
    wire        wb_valid_alt, wb_wr_en_alt;

    // 数据存储器接口
    wire [31:0] dmem_addr, dmem_wr_data;
    wire        dmem_wr_en;
    wire [31:0] dmem_data_a;
    wire [31:0] dmem_data_b;

    // mem_arbiter 到 data_storage
    wire [31:0] mem_addr_a;
    wire [31:0] mem_rd_data_a;
    wire        mem_wr_en_b;
    wire [31:0] mem_addr_b;
    wire [31:0] mem_wr_data_b;
    wire [31:0] mem_rd_data_b;

    // 分支
    wire        branch_taken;
    wire [31:0] branch_target;

    // 前推
    wire [1:0]  fwd_a, fwd_b;

    // 流水线控制
    wire        stall, flush;

    // 中断
    wire        irq_pending, irq_ack;
    wire [31:0] irq_vector;
    wire [31:0] saved_pc, saved_status;

    // 寄存器堆
    wire [31:0] reg_a, reg_b;

    // 指令存储器
    wire [31:0] imem_instr;

    // ============================================================
    // 字段解码
    // ============================================================
    wire [4:0]  rd_addr_a = ifidinstr[21:17];
    wire [4:0]  rd_addr_b = ifidinstr[16:12];

    wire [4:0]  ifid_opcode = ifidinstr[31:27];
    wire        ifid_valid_for_ctrl = ifidvalid;
    wire        flush_ext = 1'b0;

    // ============================================================
    // dmem 接口 - 来自 EX/MEM (MEM 阶段)
    // ============================================================
    assign dmem_addr    = ex_alu_result;
    assign dmem_wr_data = ex_rs2;
    assign dmem_wr_en   = ex_mem_wr_en;

    // ============================================================
    // 模块实例化
    // ============================================================

    // 寄存器堆 (写回来自 MEM/WB)
    register_bank rf (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(mem_valid && mem_wr_en),
        .wr_addr(mem_rd),
        .wr_data(mem_result),
        .rd_addr_a(rd_addr_a),
        .rd_data_a(reg_a),
        .rd_addr_b(rd_addr_b),
        .rd_data_b(reg_b)
    );

    // 指令存储器
    program_storage imem_inst (
        .addr(pc),
        .data(imem_instr)
    );

    // 存储器仲裁器
    mem_arbiter mem_arb_inst (
        .cpu_addr    (dmem_addr),
        .cpu_wr_en   (dmem_wr_en),
        .cpu_wr_data (dmem_wr_data),
        .cpu_rd_data (dmem_data_a),
        .test_addr    (test_mem_addr),
        .test_wr_en   (test_mem_wr_en),
        .test_wr_data (test_mem_wr_data),
        .test_rd_data (dmem_data_b),
        .mem_addr_a    (mem_addr_a),
        .mem_rd_data_a (mem_rd_data_a),
        .mem_wr_en_b   (mem_wr_en_b),
        .mem_addr_b    (mem_addr_b),
        .mem_wr_data_b (mem_wr_data_b),
        .mem_rd_data_b (mem_rd_data_b)
    );

    // 数据存储器
    data_storage dmem_inst (
        .clk(clk),
        .rst_n(rst_n),
        .addr_a    (mem_addr_a),
        .rd_data_a (mem_rd_data_a),
        .wr_en_b   (mem_wr_en_b),
        .addr_b    (mem_addr_b),
        .wr_data_b (mem_wr_data_b),
        .rd_data_b (mem_rd_data_b)
    );

    // 中断控制器
    interrupt_handler irq_inst (
        .clk(clk),
        .rst_n(rst_n),
        .irq(irq),
        .cpu_ready(!stall && !irq_active && status[0]),
        .irq_ret(iret_trigger),
        .current_pc(pc),
        .current_status(status),
        .irq_pending(irq_pending),
        .irq_ack(irq_ack),
        .saved_pc(saved_pc),
        .saved_status(saved_status),
        .irq_vector(irq_vector)
    );

    // 取指
    instruction_fetcher if_inst (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .imem_addr(pc),
        .imem_data(imem_instr),
        .irq_ack(irq_ack),
        .irq_vector(irq_vector),
        .irq_ret(iret_trigger),
        .saved_pc(saved_pc),
        .if_pc(if_pc),
        .if_instr(if_instr),
        .if_valid(if_valid)
    );

    // IF/ID 流水线寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifidinstr <= 32'b0;
            ifidpc    <= 32'b0;
            ifidvalid <= 1'b0;
        end else if (flush) begin
            ifidinstr <= 32'b0;
            ifidpc    <= 32'b0;
            ifidvalid <= 1'b0;
        end else if (!stall) begin
            ifidinstr <= if_instr;
            ifidpc    <= if_pc;
            ifidvalid <= if_valid;
        end
    end

    // 译码 (内含 ID/EX 寄存器)
    instruction_decoder id_inst (
        .clk(clk),
        .rst_n(rst_n),
        .if_pc(ifidpc),
        .if_instr(ifidinstr),
        .if_valid(ifidvalid),
        .stall(stall),
        .flush(flush),
        .reg_rd_addr_a(rd_addr_a),
        .reg_rd_addr_b(rd_addr_b),
        .reg_rd_data_a(reg_a),
        .reg_rd_data_b(reg_b),
        .fwd_alu_ex(ex_alu_result),    // EX/MEM 结果
        .fwd_alu_mem(mem_result),      // MEM/WB 结果
        .fwd_rd_ex(ex_rd),             // EX/MEM rd
        .fwd_rd_mem(mem_rd),           // MEM/WB rd
        .fwd_valid_ex(ex_valid),
        .fwd_valid_mem(mem_valid),
        .fwd_wr_en_ex(ex_valid && ex_reg_wr_en && !ex_is_load),  // 排除 LW
        .fwd_wr_en_mem(mem_valid && mem_wr_en),
        .fwd_a(fwd_a),
        .fwd_b(fwd_b),
        .id_pc(id_pc),
        .id_instr(id_instr),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_rd(id_rd),
        .id_imm(id_imm),
        .id_valid(id_valid),
        .id_is_branch(id_is_branch),
        .id_is_jump(id_is_jump),
        .id_is_load(id_is_load),
        .id_is_alu(id_is_alu)
    );

    // 执行 (内含 EX/MEM 寄存器)
    arithmetic_unit ex_inst (
        .clk(clk),
        .rst_n(rst_n),
        .id_pc(id_pc),
        .id_instr(id_instr),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_rd(id_rd),
        .id_imm(id_imm),
        .id_valid(id_valid),
        .id_is_branch(id_is_branch),
        .id_is_jump(id_is_jump),
        .id_is_load(id_is_load),
        .id_is_alu(id_is_alu),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .int_trigger(int_trigger),
        .iret_trigger(iret_trigger),
        .alu_result(ex_alu_result),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd),
        .ex_valid(ex_valid),
        .ex_mem_wr_en(ex_mem_wr_en),
        .ex_reg_wr_en(ex_reg_wr_en),
        .ex_is_load(ex_is_load),
        .ex_is_alu(ex_is_alu),
        .debug_alu(debug_alu_result)
    );

    // 流水线控制器
    pipeline_controller ctrl_inst (
        .clk(clk),
        .rst_n(rst_n),
        .ifid_opcode(ifid_opcode),
        .ifid_valid(ifid_valid_for_ctrl),
        .flush_in(flush_ext),
        .pause(pause),
        .stall(stall),
        .flush(flush)
    );

    // 数据前推
    data_forwarder fwd_inst (
        .id_rs1(rd_addr_a),
        .id_rs2(rd_addr_b),
        .ex_rd(ex_rd),
        .mem_rd(mem_rd),
        .ex_valid(ex_valid),
        .mem_valid(mem_valid),
        .ex_wr_en(ex_valid && ex_reg_wr_en && !ex_is_load),  // 排除 LW
        .mem_wr_en(mem_valid && mem_wr_en),
        .fwd_a(fwd_a),
        .fwd_b(fwd_b)
    );

    // ============================================================
    // MEM/WB 流水线寄存器 - 主路径 (memory_access)
    // ============================================================
    memory_access mem_access_inst (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush),
        .ex_alu_result(ex_alu_result),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd),
        .ex_valid(ex_valid),
        .ex_mem_wr_en(ex_mem_wr_en),
        .ex_is_load(ex_is_load),
        .ex_is_alu(ex_is_alu),
        .dmem_rd_data(dmem_data_a),
        .mem_result(mem_result),
        .mem_rd(mem_rd),
        .mem_valid(mem_valid),
        .mem_wr_en(mem_wr_en)
    );

    // ============================================================
    // MEM/WB 流水线寄存器 - 备用路径 (result_writer)
    // 与 memory_access 同源，用于验证与对照
    // 输出未连接到寄存器堆，避免冲突
    // ============================================================
    result_writer result_writer_inst (
        .clk(clk),
        .rst_n(rst_n),
        .ex_result(ex_alu_result),
        .ex_rd(ex_rd),
        .ex_valid(ex_valid),
        .ex_is_load(ex_is_load),
        .ex_is_alu(ex_is_alu),
        .dmem_data(dmem_data_a),
        .mem_result(wb_result_alt),
        .mem_rd(wb_rd_alt),
        .mem_valid(wb_valid_alt),
        .mem_wr_en(wb_wr_en_alt)
    );

    // ============================================================
    // 中断激活状态
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_active <= 1'b0;
        end else if (irq_ack) begin
            irq_active <= 1'b1;
        end else if (iret_trigger) begin
            irq_active <= 1'b0;
        end
    end

    // ============================================================
    // 调试输出
    // ============================================================
    assign debug_pc    = if_pc;
    assign debug_instr = if_instr;

    // ============================================================
    // 测试接口: 寄存器读写
    // ============================================================
    always @(*) begin
        test_reg_read_data = 32'b0;
        if (test_reg_addr < 32)
            test_reg_read_data = rf.regs[test_reg_addr];
    end
    assign test_reg_rd_data = test_reg_read_data;

    always @(posedge clk) begin
        if (test_reg_wr_en)
            rf.regs[test_reg_addr] <= test_reg_wr_data;
    end

    // ============================================================
    // 测试接口: 内存读
    // ============================================================
    assign test_mem_rd_data = dmem_data_b;

endmodule
