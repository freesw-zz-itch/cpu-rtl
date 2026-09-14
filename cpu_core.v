// ============================================================
// 核心 CPU 模块 - 支持双口RAM
// - 三级流水线: 取指(IF) → 译码(ID) → 执行(EX)
// - 32 个通用寄存器
// - 16 条指令扩展 (5位 opcode)
// - 完整中断机制 (保存 PC 和 STATUS)
// - 双口数据存储器读写支持
// - 流水线停顿 (stall) 控制
// - 测试接口: 寄存器/内存直接读写
// ============================================================

`include "cpu_defines.v"

module cpu_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq,
    input  wire        pause,        // ← 新增：外部暂停
    // 测试接口: 寄存器读写
    input  wire        test_reg_wr_en,
    input  wire [4:0]  test_reg_addr,
    input  wire [31:0] test_reg_wr_data,
    output wire [31:0] test_reg_rd_data,
    // 测试接口: 内存读写 (双口)
    input  wire        test_mem_wr_en,
    input  wire [31:0] test_mem_addr,
    input  wire [31:0] test_mem_wr_data,
    output wire [31:0] test_mem_rd_data,
    // 调试输出
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instr,
    output wire [31:0] debug_alu_result
);

    // ============================================================
    // ★★★ 重要: 所有 reg 声明必须放在 wire 声明之前 ★★★
    // ============================================================

    // 1. 内部状态: PC 和 STATUS
    reg [31:0] pc;
    reg [31:0] status;

    // 2. 流水线寄存器 (IF/ID, ID/EX)
    reg [31:0] ifidinstr;
    reg [31:0] ifidpc;
    reg        ifidvalid;

    reg [31:0] idexinstr;
    reg [31:0] idexpc;
    reg [31:0] idexrs1val;
    reg [31:0] idexrs2val;
    reg [4:0]  idexrd;
    reg        idexvalid;

    // 3. 中断相关信号
    reg         irq_active;
    reg [31:0]  irq_saved_pc;
    reg [31:0]  irq_saved_status;

    // 4. 测试接口寄存器
    reg [31:0] test_reg_read_data;
    reg [31:0] test_mem_read_data;

    // ============================================================
    // ★★★ 以下为 wire 声明 ★★★
    // ============================================================

    // IF <-> ID 连接
    wire [31:0] if_pc, if_instr;
    wire        if_valid;

    // ID <-> EX 连接
    wire [31:0] id_pc, id_instr, id_rs1, id_rs2, id_imm;
    wire [4:0]  id_rd;
    wire        id_valid;
    wire        id_is_branch, id_is_jump, id_is_load, id_is_alu;

    // EX 输出
    wire [31:0] ex_alu_result, ex_rs2;
    wire [4:0]  ex_rd;
    wire        ex_valid, ex_mem_wr_en, ex_reg_wr_en, ex_is_load, ex_is_alu;
    wire        int_trigger, iret_trigger;

    // // 数据存储器连接 (双口)
    // wire [31:0] dmem_addr, dmem_wr_data;
    // wire        dmem_wr_en;
    // wire [31:0] dmem_data_a;  // 端口A读数据
    // wire [31:0] dmem_data_b;  // 端口B读数据 (测试接口用)

    // 数据存储器连接 (双口)
    wire [31:0] dmem_addr, dmem_wr_data;
    wire        dmem_wr_en;
    wire [31:0] dmem_data_a;  // 端口A读数据 (CPU 读)
    wire [31:0] dmem_data_b;  // 端口B读数据 (测试读)

    // 仲裁器到 data_storage 的信号
    wire [31:0] mem_addr_a;
    wire [31:0] mem_rd_data_a;
    wire        mem_wr_en_b;
    wire [31:0] mem_addr_b;
    wire [31:0] mem_wr_data_b;
    wire [31:0] mem_rd_data_b;


    // 分支连接
    wire        branch_taken;
    wire [31:0] branch_target;

    // 前推连接
    wire [1:0] fwd_a, fwd_b;

    // 执行结果 (用于写回)
    wire [31:0] exe_result;

    // 前推结果
    wire [31:0] fwd_alu_ex, fwd_alu_mem;
    wire [4:0] fwd_rd_ex;

    // 流水线控制
    wire stall, flush;

    // 中断控制信号
    wire irq_pending, irq_ack;
    wire [31:0] irq_vector;
    wire [31:0] saved_pc, saved_status;

    // 寄存器堆输出
    wire [31:0] reg_a, reg_b;

    // 指令存储器输出
    wire [31:0] imem_instr;

    // ============================================================
    // 以下为组合逻辑和模块实例化
    // ============================================================

    // 指令字段解码 (组合逻辑) - 用于 ID/EX 阶段
    wire [4:0]  opcode = idexinstr[31:27];
    wire [4:0]  rd     = idexinstr[26:22];
    wire [4:0]  rs1    = idexinstr[21:17];
    wire [4:0]  rs2    = idexinstr[16:12];
    wire [11:0] imm    = idexinstr[11:0];

    wire [4:0] rd_addr_a = ifidinstr[21:17];
    wire [4:0] rd_addr_b = ifidinstr[16:12];

    // 12位立即数符号扩展
    wire signed [31:0] imm_se = {{20{imm[11]}}, imm};
    
    // 写回使能: JMP/INT/IRET 不写回
    wire no_writeback = (opcode == `OP_JMP) ||
                        (opcode == `OP_INT) ||
                        (opcode == `OP_IRET);

    // 流水线停顿控制
    // 流水线停顿控制
    // stall 和 flush 完全由 pipeline_controller 产生
    wire [4:0] ifid_opcode = ifidinstr[31:27];
    wire       ifid_valid_for_ctrl = ifidvalid;   // IF/ID 有效
    wire       flush_ext;                          // 外部 flush（中断等）

    // ============================================================
    // 模块实例化
    // ============================================================

    // 7.1 寄存器堆
    register_bank rf (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(idexvalid && !no_writeback),
        .wr_addr(rd),
        .wr_data(exe_result),
        .rd_addr_a(rd_addr_a),
        .rd_data_a(reg_a),
        .rd_addr_b(rd_addr_b),
        .rd_data_b(reg_b)
    );

    // 7.2 指令存储器
    program_storage imem_inst (
        .addr(pc),          // PC 是 32 位地址
        .data(imem_instr)   // 取出的 32 位指令
    );

    // ============================================================
    // 7.3 存储器仲裁器
    // ============================================================
    mem_arbiter mem_arb_inst (
        // CPU 侧
        .cpu_addr    (dmem_addr),
        .cpu_wr_en   (dmem_wr_en),
        .cpu_wr_data (dmem_wr_data),
        .cpu_rd_data (dmem_data_a),
        // 测试侧
        .test_addr    (test_mem_addr),
        .test_wr_en   (test_mem_wr_en),
        .test_wr_data (test_mem_wr_data),
        .test_rd_data (dmem_data_b),
        // 到 data_storage 端口A
        .mem_addr_a    (mem_addr_a),
        .mem_rd_data_a (mem_rd_data_a),
        // 到 data_storage 端口B
        .mem_wr_en_b   (mem_wr_en_b),
        .mem_addr_b    (mem_addr_b),
        .mem_wr_data_b (mem_wr_data_b),
        .mem_rd_data_b (mem_rd_data_b)
    );

    // ============================================================
    // 7.4 数据存储器 (纯存储)
    // ============================================================
    data_storage dmem_inst (
        .clk(clk),
        .rst_n(rst_n),
        // 端口A: 只读
        .addr_a    (mem_addr_a),
        .rd_data_a (mem_rd_data_a),
        // 端口B: 读写
        .wr_en_b   (mem_wr_en_b),
        .addr_b    (mem_addr_b),
        .wr_data_b (mem_wr_data_b),
        .rd_data_b (mem_rd_data_b)
    );

    // 7.4 中断控制器
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

    // ============================================================
    // 8. 取指阶段 (IF) 实例化
    // ============================================================
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

    // ============================================================
    // 9. IF/ID 流水线寄存器
    // ============================================================
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

    // ============================================================
    // 10. 译码阶段 (ID) 实例化
    // ============================================================
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
        .fwd_alu_ex(fwd_alu_ex),
        .fwd_alu_mem(fwd_alu_mem),
        .fwd_rd_ex(fwd_rd_ex),
        .fwd_rd_mem(idexrd),
        .fwd_valid_ex(ex_valid),
        .fwd_valid_mem(idexvalid),
        .fwd_wr_en_ex(ex_reg_wr_en),
        .fwd_wr_en_mem(idexvalid && !no_writeback),
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

    // ============================================================
    // 11. 执行阶段 (EX) 实例化
    // ============================================================
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
        .stall(stall),
        .flush(flush),
        .dmem_rd_data(dmem_data_a),  // 使用端口A读数据
        .dmem_addr(dmem_addr),
        .dmem_wr_data(dmem_wr_data),
        .dmem_wr_en(dmem_wr_en),
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
        .fwd_alu_ex(fwd_alu_ex),
        .fwd_alu_mem(fwd_alu_mem),
        .fwd_rd_ex(fwd_rd_ex),
        .debug_alu(debug_alu_result)
    );

    // ============================================================
    // 12. 流水线控制器
    // ============================================================
    pipeline_controller ctrl_inst (
        .clk         (clk),
        .rst_n       (rst_n),
        .ifid_opcode (ifid_opcode),        // ← 用 IF/ID 的 opcode
        .ifid_valid  (ifid_valid_for_ctrl),
        .flush_in    (flush_ext),          // ← 外部 flush（可选）
        .pause       (pause),              // ← 新增：外部暂停请求
        .stall       (stall),
        .flush       (flush)
    );

    // ============================================================
    // 13. 前推单元 - 使用 IF/ID 流水线中的指令
    // ============================================================
    data_forwarder fwd_inst (
        .id_rs1   (rd_addr_a),
        .id_rs2   (rd_addr_b),
        .ex_rd (fwd_rd_ex),
        .mem_rd   (idexrd),
        .ex_valid (ex_valid),
        .mem_valid(idexvalid),
        .ex_wr_en (ex_reg_wr_en),
        // ★★★ MEM 阶段写寄存器使能，排除 R0（R0 不需要前推）★★★
        .mem_wr_en(idexvalid && !no_writeback && (idexrd != 5'b0)),
        .fwd_a    (fwd_a),
        .fwd_b    (fwd_b)
    );

    // ============================================================
    // 14. ID/EX 流水线寄存器
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idexinstr   <= 32'b0;
            idexpc      <= 32'b0;
            idexrs1val  <= 32'b0;
            idexrs2val  <= 32'b0;
            idexrd      <= 5'b0;
            idexvalid   <= 1'b0;
        end else if (!stall && id_valid) begin
            idexinstr   <= id_instr;
            idexpc      <= id_pc;
            idexrs1val  <= id_rs1;
            idexrs2val  <= id_rs2;
            idexrd      <= id_rd;
            idexvalid   <= 1'b1;
        end
    end

    // ============================================================
    // 15. 执行结果写回 (使用端口A数据)
    // ============================================================
    assign exe_result = ex_is_load ? dmem_data_a : ex_alu_result;

    // ============================================================
    // 16. 中断激活状态
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
    // 17. 调试输出
    // ============================================================
    assign debug_pc    = if_pc;
    assign debug_instr = if_instr;

    // ============================================================
    // 18. 测试接口: 寄存器直接读写
    // ============================================================
    always @(*) begin
        test_reg_read_data = 32'b0;
        if (test_reg_addr >= 0 && test_reg_addr < 32) begin
            test_reg_read_data = rf.regs[test_reg_addr];
        end
    end
    assign test_reg_rd_data = test_reg_read_data;

    // 寄存器写入 (同步)
    always @(posedge clk) begin
        if (test_reg_wr_en) begin
            rf.regs[test_reg_addr] <= test_reg_wr_data;
        end
    end

    // ============================================================
    // 19. 测试接口: 内存直接读写 (直接访问内部mem)
    // ============================================================
    // ============================================================
    // 19. 测试接口: 内存读
    // ============================================================
    assign test_mem_rd_data = dmem_data_b;
    // always @(*) begin
    //     test_mem_read_data = 32'b0;
    //     if (test_mem_addr[7:0] >= 0 && test_mem_addr[7:0] < 256) begin
    //         test_mem_read_data = dmem_inst.mem[test_mem_addr[7:0]];
    //     end
    // end
    // assign test_mem_rd_data = test_mem_read_data;

    // 内存写入 (已在 dmem_inst 中通过端口B处理)
    // 不需要额外的 always 块

endmodule
