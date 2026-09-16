// ============================================================
// 写回阶段 (WB) —— MEM/WB 流水线寄存器
// ============================================================

module write_back (
    input  wire        clk,
    input  wire        rst_n,

    // 来自 MEM 阶段（组合）
    input  wire [31:0] mem_result,
    input  wire [4:0]  mem_rd,
    input  wire        mem_valid,
    input  wire        mem_wr_en,

    // 到寄存器堆
    output reg  [31:0] wb_result,
    output reg  [4:0]  wb_rd,
    output reg         wb_valid,
    output reg         wb_wr_en
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_result <= 32'b0;
            wb_rd     <= 5'b0;
            wb_valid  <= 1'b0;
            wb_wr_en  <= 1'b0;
        end else begin
            wb_result <= mem_result;
            wb_rd     <= mem_rd;
            wb_valid  <= mem_valid;
            wb_wr_en  <= mem_wr_en;
        end
    end

endmodule
