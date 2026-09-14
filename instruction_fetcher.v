// ============================================================
// 取指模块
// 根据PC从指令存储器读取指令
// ============================================================

module instruction_fetcher (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,
    // 中断响应
    input  wire        irq_ack,
    input  wire [31:0] irq_vector,
    // 中断返回
    input  wire        irq_ret,
    input  wire [31:0] saved_pc,
    // 输出到译码阶段
    output reg  [31:0] if_pc,
    output reg  [31:0] if_instr,
    output reg         if_valid
);

    reg [31:0] pc;
    reg [31:0] pc_next;
    reg        if_flush;

    always @* begin
        if (irq_ack) begin
            pc_next = irq_vector;
        end else if (irq_ret) begin
            pc_next = saved_pc;
        end else if (branch_taken) begin
            pc_next = branch_target;
        end else if (stall) begin
            pc_next = pc;
        end else begin
            pc_next = pc + 4;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h00000000;
        end else if (!stall) begin
            pc <= pc_next;
        end
    end

    assign imem_addr = pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_pc    <= 32'b0;
            if_instr <= 32'b0;
            if_valid <= 1'b0;
        end else if (flush) begin
            if_valid <= 1'b0;
        end else if (!stall) begin
            if_pc    <= pc;
            if_instr <= imem_data;
            if_valid <= 1'b1;
        end
    end

endmodule
