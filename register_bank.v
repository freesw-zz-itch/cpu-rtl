// ============================================================
// ¼Ä´æÆ÷¶Ñ: 32 ¸ö 32 Î»¼Ä´æÆ÷
// R0 Ó²Á¬ÏßÎª 0
// ============================================================

module register_bank (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr_en,
    input  wire [4:0]  wr_addr,
    input  wire [31:0] wr_data,
    input  wire [4:0]  rd_addr_a,
    output reg  [31:0] rd_data_a,
    input  wire [4:0]  rd_addr_b,
    output reg  [31:0] rd_data_b
);

    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (wr_en) begin
            regs[wr_addr] <= wr_data;
        end
    end

    always @(*) begin
        rd_data_a = (rd_addr_a == 5'b0) ? 32'b0 : regs[rd_addr_a];
        rd_data_b = (rd_addr_b == 5'b0) ? 32'b0 : regs[rd_addr_b];
    end

endmodule
