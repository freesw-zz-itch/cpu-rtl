// ============================================================
// CPU 测试平台 - 真正执行指令测试
// 打印所有寄存器和 PC 值
// 包含双口RAM功能测试
// ============================================================

`timescale 1ns / 1ps

`include "cpu_defines.v"

module cpu_tb();

    reg         clk;
    reg         rst_n;
    reg         irq;
    reg         pause;        // ← 新增：外部暂停请求
    reg         test_reg_wr_en;
    reg  [4:0]  test_reg_addr;
    reg  [31:0] test_reg_wr_data;
    wire [31:0] test_reg_rd_data;
    reg         test_mem_wr_en;
    reg  [31:0] test_mem_addr;
    reg  [31:0] test_mem_wr_data;
    wire [31:0] test_mem_rd_data;
    wire [31:0] debug_pc, debug_instr, debug_alu;

    // ============================================================
    // 指令构建函数 (使用宏定义)
    // ============================================================
    
    function [31:0] build_instr;
        input [4:0]  opcode;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [4:0]  rs2;
        input [11:0] imm;
        begin
            build_instr = {opcode, rd, rs1, rs2, imm};
        end
    endfunction

    // ============================================================
    // 预定义指令编码 (使用宏)
    // ============================================================
    
    // ADD 指令
    `define INSTR_ADD(rd, rs1, rs2) \
        build_instr(`OP_ADD, rd, rs1, rs2, 12'h000)
    
    // SUB 指令
    `define INSTR_SUB(rd, rs1, rs2) \
        build_instr(`OP_SUB, rd, rs1, rs2, 12'h000)
    
    // MUL 指令
    `define INSTR_MUL(rd, rs1, rs2) \
        build_instr(`OP_MUL, rd, rs1, rs2, 12'h000)
    
    // DIV 指令
    `define INSTR_DIV(rd, rs1, rs2) \
        build_instr(`OP_DIV, rd, rs1, rs2, 12'h000)
    
    // ADDI 指令
    `define INSTR_ADDI(rd, rs1, imm) \
        build_instr(`OP_ADDI, rd, rs1, `REG_R0, imm)
    
    // SUBI 指令
    `define INSTR_SUBI(rd, rs1, imm) \
        build_instr(`OP_SUBI, rd, rs1, `REG_R0, imm)
    
    // MOVE 指令 (寄存器模式)
    `define INSTR_MOVE_REG(rd, rs1) \
        build_instr(`OP_MOVE, rd, rs1, `REG_R0, 12'h000)
    
    // MOVE 指令 (立即数模式)
    `define INSTR_MOVE_IMM(rd, imm) \
        build_instr(`OP_MOVE, rd, `REG_R0, `REG_R0, imm)
    
    // LW 指令
    `define INSTR_LW(rd, rs1, imm) \
        build_instr(`OP_LW, rd, rs1, `REG_R0, imm)
    
    // SW 指令
    `define INSTR_SW(rs2, rs1, imm) \
        build_instr(`OP_SW, `REG_R0, rs1, rs2, imm)
    
    // BEQ 指令
    `define INSTR_BEQ(rs1, rs2, imm) \
        build_instr(`OP_BEQ, `REG_R0, rs1, rs2, imm)
    
    // JMP 指令
    `define INSTR_JMP(imm) \
        build_instr(`OP_JMP, `REG_R0, `REG_R0, `REG_R0, imm)
    
    // NOP 指令
    `define INSTR_NOP 32'h00000000


    cpu_core uut (
        .clk              (clk),
        .rst_n            (rst_n),
        .irq              (irq),
        .pause            (pause),
        .test_reg_wr_en   (test_reg_wr_en),
        .test_reg_addr    (test_reg_addr),
        .test_reg_wr_data (test_reg_wr_data),
        .test_reg_rd_data (test_reg_rd_data),
        .test_mem_wr_en   (test_mem_wr_en),
        .test_mem_addr    (test_mem_addr),
        .test_mem_wr_data (test_mem_wr_data),
        .test_mem_rd_data (test_mem_rd_data),
        .debug_pc         (debug_pc),
        .debug_instr      (debug_instr),
        .debug_alu_result (debug_alu)
    );

    always #5 clk = ~clk;

    // ============================================================
    // 初始状态: 复位信号为低
    // ============================================================
    initial begin
        rst_n = 0;
    end

    // ============================================================
    // 测试任务
    // ============================================================

    // 写寄存器任务
    task write_reg;
        input [4:0] addr;
        input [31:0] data;
        begin
            @(negedge clk) begin
                test_reg_wr_en = 1'b1;
                test_reg_addr = addr;
                test_reg_wr_data = data;
            end
            @(posedge clk)
            @(posedge clk) begin
                test_reg_wr_en = 1'b0;
            end
            #1;
        end
    endtask

    // 读寄存器任务
    task read_reg;
        input [4:0] addr;
        output reg [31:0] data;
        begin
            test_reg_addr = addr;
            @(posedge clk);
            #1;
            data = test_reg_rd_data;
            $display("  [READ] R%0d = 0x%08X (%0d)", addr, data, data);
        end
    endtask

    // 写内存任务
    task write_mem;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk) begin
                test_mem_wr_en = 1'b1;
                test_mem_addr = addr;
                test_mem_wr_data = data;
            end
            @(posedge clk) begin
                test_mem_wr_en = 1'b0;
            end
            #1;
        end
    endtask

    // 读内存任务
    task read_mem;
        input [31:0] addr;
        output reg [31:0] data;
        begin
            test_mem_addr = addr;
            @(posedge clk);
            data = test_mem_rd_data;
            #1;
        end
    endtask

    // ============================================================
    // 写入指令任务 (使用字地址)
    // ============================================================
    task write_instruction;
        input [31:0] addr;
        input [31:0] instr;
        begin
            uut.imem_inst.mem[addr[7:2]] = instr;
            #1;
        end
    endtask

    // ============================================================
    // 重置 CPU (释放复位，PC 回到 0)
    // ============================================================
    task reset_cpu;
        begin
            rst_n = 0;
            #20;
            rst_n = 1;
            #20;
        end
    endtask

    // ============================================================
    // 重置 PC 但不清除寄存器
    // ============================================================
    task reset_pc_only;
        begin
            force uut.if_inst.pc = 32'h00000000;
            #10;
            release uut.if_inst.pc;
            #10;
        end
    endtask

    // ============================================================
    // 等待 PC 到达目标地址 (带超时)
    // ============================================================
    task wait_for_pc;
        input [31:0] target_pc;
        integer timeout;
        begin
            timeout = 0;
            while (debug_pc !== target_pc && timeout < 1000) begin
                #10;
                timeout = timeout + 1;
                if (timeout % 100 == 0) begin
                    $display("  [WAIT] PC = 0x%08X, waiting for 0x%08X...", debug_pc, target_pc);
                end
            end
            if (timeout >= 1000) begin
                $display("  ?? WARNING: Timeout waiting for PC = 0x%08X (current PC = 0x%08X)", 
                         target_pc, debug_pc);
            end
        end
    endtask

    // ============================================================
    // 运行程序
    // ============================================================
    task run_program;
        input [31:0] instr0, instr1, instr2, instr3, instr4;
        input [4:0]  result_reg;
        input [31:0] expected;
        input [127:0] test_name;
        reg [31:0] result;
        begin
            $display("\n========================================");
            $display("  Test: %s", test_name);
            $display("========================================");

            $display("  [1] Writing program to instruction memory...");
            write_instruction(32'h00000000, instr0);
            write_instruction(32'h00000004, instr1);
            write_instruction(32'h00000008, instr2);
            write_instruction(32'h0000000C, instr3);
            write_instruction(32'h00000010, instr4);
            $display("  [1] Program written.");

            $display("  [2] Resetting CPU...");
            reset_cpu();
            $display("  [2] CPU reset complete. PC = 0x%08X", debug_pc);

            $display("  [3] Waiting for execution to complete...");
            wait_for_pc(32'h0000001C);

            $display("  [4] Reading result...");
            read_reg(result_reg, result);
            $display("  Result: R%0d = %0d (0x%08X)", result_reg, result, result);
            $display("  Expected: %0d (0x%08X)", expected, expected);

            if (result === expected) begin
                $display("  Status: PASS");
            end else begin
                $display("  Status: FAIL");
            end

            print_all_regs();
            print_memory();
        end
    endtask

    // ============================================================
    // 打印所有 32 个寄存器的值
    // ============================================================
    task print_all_regs;
        reg [31:0] reg_val;
        integer i;
        begin
            $display("");
            $display("  ========== Register File (32 Registers) ==========");
            $display("  R00: 0x%08X  R01: 0x%08X  R02: 0x%08X  R03: 0x%08X",
                     uut.rf.regs[0], uut.rf.regs[1], uut.rf.regs[2], uut.rf.regs[3]);
            $display("  R04: 0x%08X  R05: 0x%08X  R06: 0x%08X  R07: 0x%08X",
                     uut.rf.regs[4], uut.rf.regs[5], uut.rf.regs[6], uut.rf.regs[7]);
            $display("  R08: 0x%08X  R09: 0x%08X  R10: 0x%08X  R11: 0x%08X",
                     uut.rf.regs[8], uut.rf.regs[9], uut.rf.regs[10], uut.rf.regs[11]);
            $display("  R12: 0x%08X  R13: 0x%08X  R14: 0x%08X  R15: 0x%08X",
                     uut.rf.regs[12], uut.rf.regs[13], uut.rf.regs[14], uut.rf.regs[15]);
            $display("  R16: 0x%08X  R17: 0x%08X  R18: 0x%08X  R19: 0x%08X",
                     uut.rf.regs[16], uut.rf.regs[17], uut.rf.regs[18], uut.rf.regs[19]);
            $display("  R20: 0x%08X  R21: 0x%08X  R22: 0x%08X  R23: 0x%08X",
                     uut.rf.regs[20], uut.rf.regs[21], uut.rf.regs[22], uut.rf.regs[23]);
            $display("  R24: 0x%08X  R25: 0x%08X  R26: 0x%08X  R27: 0x%08X",
                     uut.rf.regs[24], uut.rf.regs[25], uut.rf.regs[26], uut.rf.regs[27]);
            $display("  R28: 0x%08X  R29: 0x%08X  R30: 0x%08X  R31: 0x%08X",
                     uut.rf.regs[28], uut.rf.regs[29], uut.rf.regs[30], uut.rf.regs[31]);
            $display("  ====================================================");
            $display("  PC = 0x%08X", debug_pc);
            $display("  ====================================================");
            $display("");
        end
    endtask

    // ============================================================
    // 打印内存数据
    // ============================================================
    task print_memory;
        integer i;
        reg [31:0] mem_data;
        begin
            $display("");
            $display("  ========== Program Memory (Address 0x00 - 0x08) ==========");
            for (i = 0; i <= 8; i = i + 1) begin
                mem_data = uut.imem_inst.mem[i];
                $display("  addr[0x%02X]: 0x%08X", i, mem_data);
            end
            $display("  ==========================================================");
            $display("");

            $display("");
            $display("  ========== Data Memory (Address 0x00 - 0x08) ==========");
            for (i = 0; i <= 8; i = i + 1) begin
                mem_data = uut.dmem_inst.mem[i];
                $display("  addr[0x%02X]: 0x%08X", i, mem_data);
            end
            $display("  ==========================================================");
            $display("");
        end
    endtask

    // ============================================================
    // 打印指定范围的内存数据
    // ============================================================
    task print_memory_range;
        input [31:0] start_addr;
        input [31:0] end_addr;
        integer i;
        reg [31:0] mem_data;
        begin
            $display("");
            $display("  ========== Data Memory (0x%02X - 0x%02X) ==========", start_addr, end_addr);
            for (i = start_addr; i <= end_addr; i = i + 1) begin
                mem_data = uut.dmem_inst.mem[i];
                $display("  addr[0x%02X]: 0x%08X", i, mem_data);
            end
            $display("  ==================================================");
            $display("");
        end
    endtask

    // ============================================================
    // 执行单条指令的测试
    // ============================================================
    task run_single_test;
        input [127:0] test_name;
        input [31:0] instr;
        input [4:0]  result_reg;
        input [31:0] expected;
        input [4:0]  reg1, reg2;
        input [31:0] val1, val2;
        reg [31:0] result;
        begin
            $display("\n========================================");
            $display("  Test: %s", test_name);
            $display("  Instruction: 0x%08X", instr);
            $display("  R%0d = %0d, R%0d = %0d", reg1, val1, reg2, val2);
            $display("========================================");

            $display("  [0] Initializing CPU...");
            rst_n = 0;
            #30;
            rst_n = 1;
            pause = 1;  // 暂停 CPU 执行，确保寄存器写入完成
            #20;
            $display("  [0] CPU initialized. PC = 0x%08X", debug_pc);

            $display("  [1] Writing instruction...");
            write_instruction(32'h00000000, instr);
            write_instruction(32'h00000004, 32'h00000000);

            $display("  [2] Writing register values...");
            write_reg(reg1, val1);
            write_reg(reg2, val2);
            pause = 0;  // 解除暂停，开始执行指令
            #10;

            $display("  [3] Resetting PC to 0...");
            reset_pc_only();
            $display("  [3] PC = 0x%08X", debug_pc);

            $display("  [4] Waiting for execution...");
            wait_for_pc(32'h00000008);

            $display("  [5] Reading result...");
            read_reg(result_reg, result);
            $display("  Result: R%0d = %0d (0x%08X)", result_reg, result, result);
            $display("  Expected: %0d (0x%08X)", expected, expected);

            if (result === expected) begin
                $display("  Status: PASS");
            end else begin
                $display("  Status: FAIL");
            end

            print_all_regs();
            print_memory();
        end
    endtask

    // ============================================================
    // 双口RAM测试任务
    // ============================================================
    task test_dual_port_ram;
        reg [31:0] data;
        begin
            $display("\n========================================");
            $display("  Dual-Port RAM Test");
            $display("========================================");

            // 确保CPU处于复位状态
            rst_n = 0;
            #30;
            rst_n = 1;
            #20;

            // 测试1: 端口B写入，端口A读取
            $display("\n[Test 1] Port B write, Port A read");
            @(posedge clk);
            test_mem_wr_en = 1;
            test_mem_addr = 32'h00000010;
            test_mem_wr_data = 32'hDEADBEEF;

            @(posedge clk);
            test_mem_wr_en = 0;
            #10;
            
            test_mem_addr = 32'h00000010;
          
            #10;
            $display("  Write addr[0x10]=0x%08X via Port B", 32'hDEADBEEF);
            $display("  Read  addr[0x10]=0x%08X via Port A", test_mem_rd_data);
            
            if (test_mem_rd_data === 32'hDEADBEEF) begin
                $display("  Test 1: PASS");
            end else begin
                $display("  Test 1: FAIL");
            end

            // 测试2: 端口B写入多个地址
            $display("\n[Test 2] Write multiple addresses via Port B");
            write_mem(32'h00000020, 32'h12345678);
            write_mem(32'h00000024, 32'h9ABCDEF0);
            write_mem(32'h00000028, 32'h5555AAAA);
            #10;

            test_mem_addr = 32'h00000020;
            #10;
            $display("  Read addr[0x20]=0x%08X", test_mem_rd_data);
            test_mem_addr = 32'h00000024;
            #10;
            $display("  Read addr[0x24]=0x%08X", test_mem_rd_data);
            test_mem_addr = 32'h00000028;
            #10;
            $display("  Read addr[0x28]=0x%08X", test_mem_rd_data);

            // 测试3: 通过端口B读操作
            $display("\n[Test 3] Port B read operation");
            data = uut.dmem_inst.mem[32'h20];
            $display("  Port B read addr[0x20]=0x%08X (via internal access)", data);
            
            // 测试4: 并发读写不同地址
            $display("\n[Test 4] Concurrent read/write");
            write_mem(32'h00000030, 32'h00000000);
            #10;
            
            test_mem_wr_en = 1;
            test_mem_addr = 32'h00000034;
            test_mem_wr_data = 32'hCAFEBABE;
            test_mem_addr = 32'h00000030;
            #10;
            $display("  During write to 0x34, read addr[0x30]=0x%08X", test_mem_rd_data);
            test_mem_wr_en = 0;
            #10;
            
            test_mem_addr = 32'h00000034;
            #10;
            $display("  Verify write addr[0x34]=0x%08X", test_mem_rd_data);

            $display("\n=== Dual-Port RAM Test Complete ===");
            print_memory_range(32'h00000010, 32'h0000003F);
        end
    endtask

    // ============================================================
    // 测试流程
    // ============================================================
    initial begin
        reg [31:0] result;

        $display("========================================");
        $display("    5-Stage Pipeline CPU Test");
        $display("    (Dual-Port RAM Version)");
        $display("========================================");
        $display("");

        clk = 0;
        irq = 0;
        pause = 0;
        test_reg_wr_en = 0;
        test_mem_wr_en = 0;

        #10;
        rst_n = 0;
        #30;
        rst_n = 1;
        #20;
        wait_for_pc(32'h00000040);
        print_memory_range(32'h00000000, 32'h0000003F);
        #10;

        // ============================================================
        // 测试 1: ADD 10 + 5 = 15
        // ============================================================
        run_single_test(
            "ADD: 10 + 5 = 15",
            `INSTR_ADD(`REG_R0, `REG_R1, `REG_R2),
            5'd0, 32'd15,
            5'd1, 5'd2,
            32'd10, 32'd5
        );

        // ============================================================
        // 测试 2: SUB 100 - 30 = 70
        // ============================================================
        run_single_test(
            "SUB: 100 - 30 = 70",
            32'h10022000,
            5'd0, 32'd70,
            5'd1, 5'd2,
            32'd100, 32'd30
        );

        // ============================================================
        // 测试 3: MUL 7 * 8 = 56
        // ============================================================
        run_single_test(
            "MUL: 7 * 8 = 56",
            32'h18022000,
            5'd0, 32'd56,
            5'd1, 5'd2,
            32'd7, 32'd8
        );

        // ============================================================
        // 测试 4: DIV 144 / 12 = 12
        // ============================================================
        run_single_test(
            "DIV: 144 / 12 = 12",
            32'h20022000,
            5'd0, 32'd12,
            5'd1, 5'd2,
            32'd144, 32'd12
        );

        // ============================================================
        // 测试 5: MOVE 20 -> R0
        // ============================================================
        run_single_test(
            "MOVE: R1(20) -> R0",
            32'h80020000,
            5'd0, 32'd20,
            5'd1, 5'd0,
            32'd20, 32'd0
        );

        // ============================================================
        // 测试 6: ADDI 立即数加法
        // ============================================================
        run_single_test(
            "ADDI: 10 + 5 = 15",
            32'h88020005,
            5'd0, 32'd15,
            5'd1, 5'd0,
            32'd10, 32'd0
        );

        // ============================================================
        // 测试 7: ADDI 负数测试
        // ============================================================
        run_single_test(
            "ADDI: 10 + (-3) = 7",
            32'h88020FFD,
            5'd0, 32'd7,
            5'd1, 5'd0,
            32'd10, 32'd0
        );

        // ============================================================
        // 测试 8: SUBI 立即数减法
        // ============================================================
        run_single_test(
            "SUBI: 10 - 5 = 5",
            32'h90020005,
            5'd0, 32'd5,
            5'd1, 5'd0,
            32'd10, 32'd0
        );

        // ============================================================
        // 测试 9: SUBI 负数立即数
        // ============================================================
        run_single_test(
            "SUBI: 10 - (-3) = 13",
            32'h90020FFD,
            5'd0, 32'd13,
            5'd1, 5'd0,
            32'd10, 32'd0
        );

        // ============================================================
        // 测试 10: 完整程序 (10+5)*2=30
        // ============================================================
        run_program(
            32'h0840000A,   // ADD R1, R0, #10
            32'h08800005,   // ADD R2, R0, #5
            32'h08C22000,   // ADD R3, R1, R2
            32'h18060002,   // MUL R0, R3, #2
            32'h00000000,   // NOP
            5'd0, 32'd30,
            "Program: (10 + 5) * 2 = 30"
        );

        // ============================================================
        // 测试 11: 双口RAM功能测试
        // ============================================================
        test_dual_port_ram();

        // ============================================================
        // 测试报告
        // ============================================================
        $display("\n========================================");
        $display("    All Tests Complete!");
        $display("========================================");

        #50 $finish;
    end

    initial begin
        $dumpfile("cpu_waveform.vcd");
        $dumpvars(0, cpu_tb);
    end

endmodule
