// ============================================================
// 取指模块 (清理版)
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
    input  wire        irq_ack,
    input  wire [31:0] irq_vector,
    input  wire        irq_ret,
    input  wire [31:0] saved_pc,
    output reg  [31:0] if_pc,
    output reg  [31:0] if_instr,
    output reg         if_valid
);

    reg [31:0] pc;
    reg [31:0] pc_next;

    always @* begin
        if (irq_ack)
            pc_next = irq_vector;
        else if (irq_ret)
            pc_next = saved_pc;
        else if (branch_taken)
            pc_next = branch_target;
        else if (stall)
            pc_next = pc;
        else
            pc_next = pc + 4;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'h0000_0000;
        else if (!stall)
            pc <= pc_next;
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
