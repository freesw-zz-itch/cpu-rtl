// ============================================================
// 数据存储器: 256 × 32 位 双口RAM
// 端口A: 读操作 (组合逻辑)
// 端口B: 写操作 (同步)
// ============================================================

module data_storage (
    input  wire        clk,
    input  wire        rst_n,
    // 端口A: 读操作
    input  wire [31:0] addr_a,
    output reg  [31:0] rd_data_a,
    // 端口B: 写操作
    input  wire        wr_en_b,
    input  wire [31:0] addr_b,
    input  wire [31:0] wr_data_b,
    output reg  [31:0] rd_data_b
);

    reg [31:0] mem [0:255];
    integer i;

    // 端口A读数据 (组合逻辑)
    always @(*) begin
        rd_data_a = mem[addr_a[7:0]];
    end

    // 端口B: 写操作 (同步)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 256; i = i + 1)
                mem[i] <= 32'b0;
            rd_data_b <= 32'b0;
        end else begin
            if (wr_en_b) begin
                mem[addr_b[7:0]] <= wr_data_b;
            end
            rd_data_b <= mem[addr_b[7:0]];
        end
    end

endmodule
