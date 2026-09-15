// ============================================================
// 写回模块 - 5 级流水线的备用 MEM/WB 寄存器
// 与 memory_access.v 同源，用于验证与对照
// ============================================================

module result_writer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] ex_result,
    input  wire [4:0]  ex_rd,
    input  wire        ex_valid,
    input  wire        ex_is_load,
    input  wire        ex_is_alu,
    input  wire [31:0] dmem_data,
    output reg  [31:0] mem_result,
    output reg  [4:0]  mem_rd,
    output reg         mem_valid,
    output reg         mem_wr_en
);

    wire [31:0] wb_data = ex_is_load ? dmem_data : ex_result;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_result <= 32'b0;
            mem_rd     <= 5'b0;
            mem_valid  <= 1'b0;
            mem_wr_en  <= 1'b0;
        end else begin
            mem_result <= wb_data;
            mem_rd     <= ex_rd;
            mem_valid  <= ex_valid;
            // ★★★ 修复：去掉 ex_rd != 0 的限制 ★★★
            mem_wr_en  <= ex_valid && (ex_is_alu || ex_is_load);
        end
    end

endmodule
