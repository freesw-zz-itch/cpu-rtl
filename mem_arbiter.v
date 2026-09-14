// ============================================================
// 存储器仲裁器
// - 位于 CPU/测试接口 与 data_storage 之间
// - 仲裁规则:
//     写: CPU (cpu_wr_en) 优先于 测试 (test_wr_en)
//     读: CPU 读走端口A；测试读走端口B
// - 输出到 data_storage 的端口信号
// ============================================================

module mem_arbiter (
    // ---- CPU 侧 ----
    input  wire [31:0] cpu_addr,       // CPU 访问地址 (读或写)
    input  wire        cpu_wr_en,      // CPU 写使能 (SW 时为 1)
    input  wire [31:0] cpu_wr_data,    // CPU 写数据 (SW 的 rs2)
    output wire [31:0] cpu_rd_data,    // CPU 读数据 (LW 的返回值)

    // ---- 测试侧 ----
    input  wire [31:0] test_addr,
    input  wire        test_wr_en,
    input  wire [31:0] test_wr_data,
    output wire [31:0] test_rd_data,

    // ---- 到 data_storage 端口A (只读) ----
    output wire [31:0] mem_addr_a,
    input  wire [31:0] mem_rd_data_a,

    // ---- 到 data_storage 端口B (读写) ----
    output wire        mem_wr_en_b,
    output wire [31:0] mem_addr_b,
    output wire [31:0] mem_wr_data_b,
    input  wire [31:0] mem_rd_data_b
);

    // ------------------------------------------------------------
    // 端口A: 只读，服务 CPU 读
    // CPU 的 LW 需要读，SW 不需要读（读数据被忽略）
    // 无论 CPU 是读还是写，地址都用 cpu_addr
    // ------------------------------------------------------------
    assign mem_addr_a   = cpu_addr;
    assign cpu_rd_data  = mem_rd_data_a;

    // ------------------------------------------------------------
    // 端口B: 读写
    // 写: CPU 优先，测试次之
    // 读: 服务测试接口
    // ------------------------------------------------------------

    // 写使能仲裁
    assign mem_wr_en_b = cpu_wr_en | test_wr_en;

    // 写地址仲裁: CPU 优先
    assign mem_addr_b  = cpu_wr_en ? cpu_addr : test_addr;

    // 写数据仲裁: CPU 优先
    assign mem_wr_data_b = cpu_wr_en ? cpu_wr_data : test_wr_data;

    // 端口B读数据返回给测试接口
    assign test_rd_data = mem_rd_data_b;

endmodule
