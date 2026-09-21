`include "cpu_defines.v"

module pipeline_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  ifid_opcode,
    input  wire        ifid_valid,
    input  wire [4:0]  ifid_rs1,
    input  wire [4:0]  ifid_rs2,
    input  wire [4:0]  idex_rd,
    input  wire        idex_rd_valid,
    input  wire        branch_taken,        // ★ 新增
    input  wire        flush_in,
    input  wire        pause,
    output reg         stall,
    output reg         flush
);

    wire raw_hazard = idex_rd_valid &&
                  (idex_rd != 5'b0) &&
                  ((idex_rd == ifid_rs1) || (idex_rd == ifid_rs2));

    // 固定停顿计数器
    reg [1:0] stall_cnt;
    reg [1:0] stall_req;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stall_cnt <= 2'd0;
        else if (flush_in || branch_taken)
            stall_cnt <= 2'd0;
        else if (stall_cnt == 2'd0) begin
            if (stall_req != 2'd0)
                stall_cnt <= stall_req;
        end else
            stall_cnt <= stall_cnt - 2'd1;
    end

    always @* begin
        stall = (stall_cnt != 2'd0) || raw_hazard || pause;
    end

    // flush = 外部 + 分支
    always @* begin
        flush = flush_in || branch_taken;
    end

endmodule
