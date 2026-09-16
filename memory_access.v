// ============================================================
// 访存阶段 (MEM) —— 纯组合逻辑
// - 产生数据存储器接口
// - 选择 LW 数据或 ALU 结果作为"待写回数据"
// ============================================================

module memory_access (
    // 来自 EX/MEM 寄存器
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_rs2,
    input  wire [4:0]  ex_rd,
    input  wire        ex_valid,
    input  wire        ex_mem_wr_en,
    input  wire        ex_is_load,
    input  wire        ex_is_alu,

    // 到 data_storage 接口
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wr_data,
    output wire        dmem_wr_en,
    input  wire [31:0] dmem_rd_data,

    // 到 WB 阶段（组合信号）
    output wire [31:0] mem_result,
    output wire [4:0]  mem_rd,
    output wire        mem_valid,
    output wire        mem_wr_en
);

    assign dmem_addr    = ex_alu_result;
    assign dmem_wr_data = ex_rs2;
    assign dmem_wr_en   = ex_valid && ex_mem_wr_en;

    assign mem_result   = ex_is_load ? dmem_rd_data : ex_alu_result;
    assign mem_rd       = ex_rd;
    assign mem_valid    = ex_valid;
    assign mem_wr_en    = ex_valid && (ex_is_alu || ex_is_load);

endmodule
