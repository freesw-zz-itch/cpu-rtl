// ============================================================
// 流水线控制器 - 5 级流水线
// - 基于 IF/ID 的 opcode 触发停顿
// - 计数器控制停顿周期
// - 分支/跳转产生 flush
// - pause 外部暂停
// ============================================================

`include "cpu_defines.v"

module pipeline_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  ifid_opcode,
    input  wire        ifid_valid,
    input  wire        flush_in,
    input  wire        pause,
    output reg         stall,
    output reg         flush
);

    reg [1:0] stall_cnt;
    reg [1:0] stall_req;

    // 停顿请求判断
    always @* begin
        stall_req = 2'd0;
        if (ifid_valid) begin
            case (ifid_opcode)
                `OP_SW:  stall_req = `STALL_SW;
                `OP_LW:  stall_req = `STALL_LW;
                `OP_INT: stall_req = `STALL_INT;
                default: stall_req = 2'd0;
            endcase
        end
    end

    // 停顿计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stall_cnt <= 2'd0;
        end else if (flush_in) begin
            stall_cnt <= 2'd0;
        end else if (stall_cnt == 2'd0) begin
            if (stall_req != 2'd0)
                stall_cnt <= stall_req;
        end else begin
            stall_cnt <= stall_cnt - 2'd1;
        end
    end

    // stall 输出
    always @* begin
        stall = (stall_cnt != 2'd0) || pause;
    end

    // flush 输出
    always @* begin
        flush = flush_in;
        if (ifid_valid && (ifid_opcode == `OP_BEQ || ifid_opcode == `OP_JMP))
            flush = 1'b1;
    end

endmodule
