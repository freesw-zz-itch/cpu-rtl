// ============================================================
// ÖĞ¶Ï¿ØÖÆÆ÷
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
    output wire [31:0] irq_vector
);

    reg [1:0] state;
    
    assign irq_vector = 32'h00000004;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_pending  <= 1'b0;
            irq_ack      <= 1'b0;
            saved_pc     <= 32'b0;
            saved_status <= 32'b0;
            state        <= `IRQ_IDLE;
        end else begin
            case (state)
                `IRQ_IDLE: begin
                    if (irq && cpu_ready) begin
                        saved_pc     <= current_pc;
                        saved_status <= current_status;
                        irq_pending  <= 1'b1;
                        state        <= `IRQ_PENDING;
                    end
                    if (irq_ret)
                        state <= `IRQ_IDLE;
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
        end
    end

endmodule
