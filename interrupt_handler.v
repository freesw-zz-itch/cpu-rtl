// ============================================================
// 中断控制器
// ★ 优化：增加 status_restore_en 输出，支持 IRET 恢复
// ============================================================

`include "cpu_defines.v"

module interrupt_handler (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq,
    input  wire        cpu_ready,
    input  wire        irq_ret,
    input  wire [31:0] current_pc,
    input  wire [31:0] current_status,
    output reg         irq_pending,
    output reg         irq_ack,
    output reg  [31:0] saved_pc,
    output reg  [31:0] saved_status,
    output wire [31:0] irq_vector,
    // ★ 新增：IRET 时恢复 status
    output reg         status_restore_en,
    output wire [31:0] status_to_restore
);

    reg [1:0] state;

    assign irq_vector        = 32'h00000004;
    assign status_to_restore = saved_status;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_pending       <= 1'b0;
            irq_ack           <= 1'b0;
            saved_pc          <= 32'b0;
            saved_status      <= 32'b0;
            status_restore_en <= 1'b0;
            state             <= `IRQ_IDLE;
        end else begin
            status_restore_en <= 1'b0;   // 默认清零

            case (state)
                `IRQ_IDLE: begin
                    if (irq && cpu_ready) begin
                        saved_pc     <= current_pc;
                        saved_status <= current_status;
                        irq_pending  <= 1'b1;
                        state        <= `IRQ_PENDING;
                    end
                end
                `IRQ_PENDING: begin
                    irq_ack     <= 1'b1;
                    irq_pending <= 1'b1;
                    state       <= `IRQ_ACK;
                end
                `IRQ_ACK: begin
                    irq_ack     <= 1'b0;
                    irq_pending <= 1'b0;
                    state       <= `IRQ_IDLE;
                end
            endcase

            // ★ IRET 脉冲：恢复 status
            if (irq_ret) begin
                status_restore_en <= 1'b1;
                state             <= `IRQ_IDLE;
            end
        end
    end

endmodule
