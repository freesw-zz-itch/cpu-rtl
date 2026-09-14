// ============================================================
// 双口RAM独立测试
// ============================================================

`timescale 1ns / 1ps

module test_dual_port();

    reg         clk;
    reg         rst_n;
    reg  [31:0] addr_a;
    wire [31:0] rd_data_a;
    reg         wr_en_b;
    reg  [31:0] addr_b;
    reg  [31:0] wr_data_b;
    wire [31:0] rd_data_b;

    data_storage dmem (
        .clk(clk),
        .rst_n(rst_n),
        // 端口A: 只读
        .addr_a(addr_a),
        .rd_data_a(rd_data_a),
        // 端口B: 读写
        .wr_en_b(wr_en_b),
        .addr_b(addr_b),
        .wr_data_b(wr_data_b),
        .rd_data_b(rd_data_b)
    );

    always #5 clk = ~clk;

    initial begin
        integer i;
        
        clk = 0;
        rst_n = 0;
        addr_a = 0;
        wr_en_b = 0;
        addr_b = 0;
        wr_data_b = 0;

        #20;
        rst_n = 1;
        #10;

        $display("========================================");
        $display("  Dual-Port RAM Independent Test");
        $display("========================================");

        // ============================================================
        // 测试1: 端口B写入，端口A读取
        // ============================================================
        $display("\n[Test 1] Port B write, Port A read");
        addr_b = 32'h00000005;
        wr_data_b = 32'h12345678;
        wr_en_b = 1;
        #10;
        wr_en_b = 0;
        #10;
        addr_a = 32'h00000005;
        #10;
        $display("  Write 0x%08X to addr[0x05] via Port B", wr_data_b);
        $display("  Read  0x%08X from addr[0x05] via Port A", rd_data_a);
        
        if (rd_data_a === 32'h12345678) begin
            $display("  Test 1: PASS");
        end else begin
            $display("  Test 1: FAIL (expected 0x12345678, got 0x%08X)", rd_data_a);
        end

        // ============================================================
        // 测试2: 端口B写入多个地址
        // ============================================================
        $display("\n[Test 2] Write multiple addresses");
        addr_b = 32'h00000010;
        wr_data_b = 32'hA5A5A5A5;
        wr_en_b = 1;
        #10;
        addr_b = 32'h00000014;
        wr_data_b = 32'h5A5A5A5A;
        #10;
        addr_b = 32'h00000018;
        wr_data_b = 32'hFFFFFFFF;
        #10;
        wr_en_b = 0;
        #10;

        addr_a = 32'h00000010;
        #10;
        $display("  Read addr[0x10]=0x%08X", rd_data_a);
        addr_a = 32'h00000014;
        #10;
        $display("  Read addr[0x14]=0x%08X", rd_data_a);
        addr_a = 32'h00000018;
        #10;
        $display("  Read addr[0x18]=0x%08X", rd_data_a);

        // ============================================================
        // 测试3: 端口B读操作
        // ============================================================
        $display("\n[Test 3] Port B read operation");
        addr_b = 32'h00000010;
        #10;
        $display("  Port B read addr[0x10]=0x%08X", rd_data_b);
        addr_b = 32'h00000014;
        #10;
        $display("  Port B read addr[0x14]=0x%08X", rd_data_b);

        // ============================================================
        // 测试4: 同时读写不同地址
        // ============================================================
        $display("\n[Test 4] Concurrent read/write different addresses");
        // 先写入数据
        addr_b = 32'h00000020;
        wr_data_b = 32'hDEADBEEF;
        wr_en_b = 1;
        #10;
        wr_en_b = 0;
        #10;
        
        // 同时：端口A读0x20，端口B写0x24
        addr_a = 32'h00000020;
        addr_b = 32'h00000024;
        wr_data_b = 32'hCAFEBABE;
        wr_en_b = 1;
        #10;
        $display("  Port A read addr[0x20]=0x%08X", rd_data_a);
        $display("  Port B write addr[0x24]=0x%08X", wr_data_b);
        wr_en_b = 0;
        #10;
        
        // 验证端口B写入
        addr_a = 32'h00000024;
        #10;
        $display("  Verify Port B write: addr[0x24]=0x%08X", rd_data_a);

        // ============================================================
        // 测试5: 复位测试
        // ============================================================
        $display("\n[Test 5] Reset test");
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;
        addr_a = 32'h00000005;
        #10;
        $display("  After reset, addr[0x05]=0x%08X (should be 0)", rd_data_a);
        
        if (rd_data_a === 32'b0) begin
            $display("  Test 5: PASS");
        end else begin
            $display("  Test 5: FAIL");
        end

        // ============================================================
        // 打印所有内存
        // ============================================================
        $display("\n========================================");
        $display("  Memory Dump (0x00 - 0x2F)");
        $display("========================================");
        for (i = 0; i < 48; i = i + 1) begin
            if (i % 8 == 0) $display("");
            $write("  [0x%02X]=0x%08X", i, dmem.mem[i]);
        end
        $display("");
        $display("========================================");

        $display("\n=== All Tests Complete ===");
        #50 $finish;
    end

    initial begin
        $dumpfile("dual_port_wave.vcd");
        $dumpvars(0, test_dual_port);
    end

endmodule
