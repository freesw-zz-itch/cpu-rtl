// ============================================================
// 写回模块
// 选择数据写回寄存器
// ============================================================

module result_writer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
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
        end else if (flush) begin
            mem_valid <= 1'b0;
        end else if (ex_valid) begin
            mem_result <= wb_data;
            mem_rd     <= ex_rd;
            mem_valid  <= 1'b1;
            mem_wr_en  <= (ex_is_alu || ex_is_load) && (ex_rd != 5'b0);
        end
    end

endmodule
