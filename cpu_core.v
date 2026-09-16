// ============================================================
// 核心 CPU 模块 - 5 级流水线
// IF → ID → EX → MEM → WB
// 访存 (MEM) 与 写回 (WB) 分离
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
    // 内部状态
    // ============================================================
    reg [31:0] status;
    reg        irq_active;

    // IF/ID 流水线寄存器
    reg [31:0] ifidinstr;
    reg [31:0] ifidpc;
    reg        ifidvalid;

    // ============================================================
    // RAW 冒险检测
    // 当 ID/EX 里的指令写 rd，且 IF/ID 里的指令读 rd 时，停顿 1 周期
    // ============================================================
    wire [4:0] idex_rd_field  = id_instr[26:22];   // ID/EX 的目标寄存器
    wire [4:0] ifid_rs1_field = ifidinstr[21:17];  // IF/ID 的 rs1
    wire [4:0] ifid_rs2_field = ifidinstr[16:12];  // IF/ID 的 rs2

    wire raw_hazard = id_valid &&
                      (idex_rd_field != 5'b0) &&
                      ((idex_rd_field == ifid_rs1_field) ||
                       (idex_rd_field == ifid_rs2_field));

    // IF 阶段和 IF/ID/ID-EX 使用的 stall (含 raw hazard)
    wire stall_final = stall || raw_hazard;

    // 测试接口
    reg [31:0] test_reg_read_data;

    // ============================================================
    // Wire 声明
    // ============================================================
    wire [31:0] if_pc, if_instr;
    wire        if_valid;
    wire [31:0] imem_addr;

    wire [31:0] id_pc, id_instr, id_rs1, id_rs2, id_imm;
    wire [4:0]  id_rd;
    wire        id_valid;
    wire        id_is_branch, id_is_jump, id_is_load, id_is_alu;

    wire [31:0] ex_alu_result, ex_rs2;
    wire [4:0]  ex_rd;
    wire        ex_valid, ex_mem_wr_en, ex_reg_wr_en, ex_is_load, ex_is_alu;
    wire        int_trigger, iret_trigger;

    // MEM 阶段 (组合)
    wire [31:0] mem_result;
    wire [4:0]  mem_rd;
    wire        mem_valid, mem_wr_en;

    // WB 阶段 (寄存器输出)
    wire [31:0] wb_result;
    wire [4:0]  wb_rd;
    wire        wb_valid, wb_wr_en;

    wire [31:0] dmem_addr, dmem_wr_data;
    wire        dmem_wr_en;
    wire [31:0] dmem_data_a, dmem_data_b;

    wire [31:0] mem_addr_a, mem_rd_data_a;
    wire        mem_wr_en_b;
    wire [31:0] mem_addr_b, mem_wr_data_b, mem_rd_data_b;

    wire        branch_taken;
    wire [31:0] branch_target;
    wire [1:0]  fwd_a, fwd_b;
    wire        stall, flush;

    wire        irq_pending, irq_ack;
    wire [31:0] irq_vector;
    wire [31:0] saved_pc, saved_status;

    wire [31:0] reg_a, reg_b;
    wire [31:0] imem_instr;

    // ============================================================
    // 字段解码
    // ============================================================
    wire [4:0]  rd_addr_a = ifidinstr[21:17];
    wire [4:0]  rd_addr_b = ifidinstr[16:12];
    wire [4:0]  ifid_opcode = ifidinstr[31:27];
    wire        ifid_valid_for_ctrl = ifidvalid;

    // ★ 中断响应时 flush
    wire        flush_ext = irq_ack;

    // ============================================================
    // status 复位后使能中断
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            status <= 32'h0000_0001;   // bit[0]=1, 允许中断
    end

    // ============================================================
    // 模块实例化
    // ============================================================

    // 寄存器堆 (写回来自 WB)
    register_bank rf (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wb_valid && wb_wr_en),
        .wr_addr(wb_rd),
        .wr_data(wb_result),
        .rd_addr_a(rd_addr_a),
        .rd_data_a(reg_a),
        .rd_addr_b(rd_addr_b),
        .rd_data_b(reg_b)
    );

    // 指令存储器
    program_storage imem_inst (
        .addr(imem_addr),
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
        .current_pc(if_pc),
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
        .stall(stall_final),
        .flush(flush),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .imem_addr(imem_addr),
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
        end else if (!stall_final) begin
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
        .stall(stall_final),
        .flush(flush),
        .reg_rd_addr_a(rd_addr_a),
        .reg_rd_addr_b(rd_addr_b),
        .reg_rd_data_a(reg_a),
        .reg_rd_data_b(reg_b),
        .fwd_alu_ex(ex_alu_result),    // EX/MEM
        .fwd_alu_mem(wb_result),       // WB
        .fwd_rd_ex(ex_rd),
        .fwd_rd_mem(wb_rd),
        .fwd_valid_ex(ex_valid),
        .fwd_valid_mem(wb_valid),
        .fwd_wr_en_ex(ex_valid && ex_reg_wr_en && !ex_is_load),
        .fwd_wr_en_mem(wb_valid && wb_wr_en),
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
        .mem_rd(wb_rd),                // ★ WB 阶段 rd
        .ex_wr_en(ex_valid && ex_reg_wr_en && !ex_is_load),
        .mem_wr_en(wb_valid && wb_wr_en),
        .fwd_a(fwd_a),
        .fwd_b(fwd_b)
    );

    // ============================================================
    // 访存阶段 (MEM) —— 组合逻辑
    // ============================================================
    memory_access mem_stage (
        .ex_alu_result (ex_alu_result),
        .ex_rs2        (ex_rs2),
        .ex_rd         (ex_rd),
        .ex_valid      (ex_valid),
        .ex_mem_wr_en  (ex_mem_wr_en),
        .ex_is_load    (ex_is_load),
        .ex_is_alu     (ex_is_alu),
        .dmem_addr     (dmem_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_wr_en    (dmem_wr_en),
        .dmem_rd_data  (dmem_data_a),
        .mem_result    (mem_result),
        .mem_rd        (mem_rd),
        .mem_valid     (mem_valid),
        .mem_wr_en     (mem_wr_en)
    );

    // ============================================================
    // 写回阶段 (WB) —— MEM/WB 流水线寄存器
    // ============================================================
    write_back wb_stage (
        .clk       (clk),
        .rst_n     (rst_n),
        .mem_result(mem_result),
        .mem_rd    (mem_rd),
        .mem_valid (mem_valid),
        .mem_wr_en (mem_wr_en),
        .wb_result (wb_result),
        .wb_rd     (wb_rd),
        .wb_valid  (wb_valid),
        .wb_wr_en  (wb_wr_en)
    );

    // ============================================================
    // 中断激活状态
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq_active <= 1'b0;
        else if (irq_ack)
            irq_active <= 1'b1;
        else if (iret_trigger)
            irq_active <= 1'b0;
    end

    // ============================================================
    // 调试输出
    // ============================================================
    assign debug_pc    = if_pc;
    assign debug_instr = if_instr;

    // ============================================================
    // 测试接口: 寄存器
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
