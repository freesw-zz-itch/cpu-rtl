// ============================================================
// 数据前推单元
// ============================================================

`include "cpu_defines.v"

module data_forwarder (
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire [4:0]  ex_rd,
    input  wire [4:0]  mem_rd,
    input  wire        ex_valid,
    input  wire        mem_valid,
    input  wire        ex_wr_en,
    input  wire        mem_wr_en,
    output reg  [1:0]  fwd_a,
    output reg  [1:0]  fwd_b
);

    always @* begin
        fwd_a = `FWD_NONE;
        fwd_b = `FWD_NONE;

        // EX/MEM 前推 (最高优先级)
        if (ex_valid && ex_wr_en && ex_rd != `REG_R0) begin
            if (ex_rd == id_rs1) fwd_a = `FWD_EX;
            if (ex_rd == id_rs2) fwd_b = `FWD_EX;
        end

        // MEM/WB 前推
        if (mem_valid && mem_wr_en && mem_rd != `REG_R0) begin
            if (mem_rd == id_rs1 && fwd_a == `FWD_NONE) fwd_a = `FWD_MEM;
            if (mem_rd == id_rs2 && fwd_b == `FWD_NONE) fwd_b = `FWD_MEM;
        end
    end

endmodule
