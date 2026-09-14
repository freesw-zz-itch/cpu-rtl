// ============================================================
// 流水线控制器
// - 基于 IF/ID 中的指令产生 stall（避免自锁）
// - 用计数器控制停顿周期数（LW/SW/INT 各需不同周期）
// - 分支/跳转产生 flush
// ============================================================

`include "cpu_defines.v"

module pipeline_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  ifid_opcode,   // ← 改为 IF/ID 的 opcode
    input  wire        ifid_valid,    // ← IF/ID 有效
    input  wire        flush_in,      // ← 外部 flush（如中断）
    input  wire        pause,         // ← 新增：外部暂停请求
    output reg         stall,
    output reg         flush
);

    // ------------------------------------------------------------
    // 停顿周期数配置
    // ------------------------------------------------------------
    // LW : 需要 1 个停顿周期（等 MEM 阶段数据写回）
    // SW : 需要 1 个停顿周期（等写使能稳定）
    // INT: 需要 2 个停顿周期（等中断控制器握手）
    // BEQ/JMP: 不需要 stall，只 flush
    // ------------------------------------------------------------

    reg [1:0] stall_cnt;        // 剩余停顿周期数
    reg       stall_req;        // 本周期是否需要发起停顿

    // ------------------------------------------------------------
    // 判断当前 IF/ID 中的指令是否需要停顿
    // ------------------------------------------------------------
    always @* begin
        stall_req = 1'b0;
        if (ifid_valid) begin
            case (ifid_opcode)
                `OP_SW:  stall_req = `STALL_SW;   // 1 周期
                `OP_LW:  stall_req = `STALL_LW;   // 1 周期
                `OP_INT: stall_req = `STALL_INT;   // 2 周期
                default: stall_req = 1'b0;
            endcase
        end
    end

    // ------------------------------------------------------------
    // 停顿计数器
    // - 当 IF/ID 中出现需要停顿的指令，且当前没有在停顿中，
    //   则加载初始计数值
    // - 否则每周期递减
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stall_cnt <= 2'd0;
        end else if (flush_in) begin
            stall_cnt <= 2'd0;                  // 外部 flush 清除停顿
        end else if (stall_cnt == 2'd0) begin
            // 空闲状态：检测是否需要发起新停顿
            if (stall_req) begin
                if (ifid_opcode == `OP_INT)
                    stall_cnt <= 2'd2;          // INT 停 2 周期
                else
                    stall_cnt <= 2'd1;          // LW/SW 停 1 周期
            end
        end else begin
            stall_cnt <= stall_cnt - 2'd1;      // 递减
        end
    end

    // ------------------------------------------------------------
    // stall 输出：计数器非零时停顿
    // ------------------------------------------------------------
    always @* begin
        stall = (stall_cnt != 2'd0) || pause;
    end

    // ------------------------------------------------------------
    // flush 输出：分支/跳转指令产生 flush
    // - flush 优先于 stall
    // - 外部 flush_in 也合并进来
    // ------------------------------------------------------------
    always @* begin
        flush = flush_in;
        if (ifid_valid && (ifid_opcode == `OP_BEQ || ifid_opcode == `OP_JMP))
            flush = 1'b1;
    end

endmodule
