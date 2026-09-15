// ============================================================
// CPU 宏定义文件
// ============================================================
// 包含:
//   - 指令操作码 (opcode)
//   - 寄存器编号
//   - 前推控制编码
//   - 流水线状态
// ============================================================

`ifndef CPU_DEFINES_V
`define CPU_DEFINES_V

// ============================================================
// 指令操作码定义 (5-bit)
// ============================================================

// ---------- 算术运算 ----------
`define OP_NOP   5'b00000
`define OP_ADD   5'b00001
`define OP_SUB   5'b00010
`define OP_MUL   5'b00011
`define OP_DIV   5'b00100

// ---------- 移位运算 ----------
`define OP_SHL   5'b00101
`define OP_SHR   5'b00110

// ---------- 逻辑运算 ----------
`define OP_AND   5'b00111
`define OP_OR    5'b01000
`define OP_XOR   5'b01001

// ---------- 内存访问 ----------
`define OP_LW    5'b01010
`define OP_SW    5'b01011

// ---------- 分支/跳转 ----------
`define OP_BEQ   5'b01100
`define OP_JMP   5'b01101

// ---------- 中断 ----------
`define OP_INT   5'b01110
`define OP_IRET  5'b01111

// ---------- 数据传输 ----------
`define OP_MOVE  5'b10000
`define OP_ADDI  5'b10001
`define OP_SUBI  5'b10010

// ============================================================
// 寄存器编号定义
// ============================================================

`define REG_R0   5'b00000
`define REG_R1   5'b00001
`define REG_R2   5'b00010
`define REG_R3   5'b00011
`define REG_R4   5'b00100
`define REG_R5   5'b00101
`define REG_R6   5'b00110
`define REG_R7   5'b00111
`define REG_R8   5'b01000
`define REG_R9   5'b01001
`define REG_R10  5'b01010
`define REG_R11  5'b01011
`define REG_R12  5'b01100
`define REG_R13  5'b01101
`define REG_R14  5'b01110
`define REG_R15  5'b01111
`define REG_R16  5'b10000
`define REG_R17  5'b10001
`define REG_R18  5'b10010
`define REG_R19  5'b10011
`define REG_R20  5'b10100
`define REG_R21  5'b10101
`define REG_R22  5'b10110
`define REG_R23  5'b10111
`define REG_R24  5'b11000
`define REG_R25  5'b11001
`define REG_R26  5'b11010
`define REG_R27  5'b11011
`define REG_R28  5'b11100
`define REG_R29  5'b11101
`define REG_R30  5'b11110
`define REG_R31  5'b11111

// ============================================================
// 前推控制编码
// ============================================================

`define FWD_NONE  2'b00   // 无前推，使用寄存器堆
`define FWD_MEM   2'b01   // 从 MEM 阶段前推
`define FWD_EX    2'b10   // 从 EX 阶段前推

// ============================================================
// 中断控制器状态
// ============================================================

`define IRQ_IDLE   2'b00
`define IRQ_PENDING 2'b01
`define IRQ_ACK    2'b10

// ============================================================
// 指令格式字段位
// ============================================================

`define INSTR_OPCODE_POS 27
`define INSTR_RD_POS     22
`define INSTR_RS1_POS    17
`define INSTR_RS2_POS    12

// ============================================================
// 功能辅助宏
// ============================================================

// 判断是否为 ALU 指令
`define IS_ALU_OP(op) \
    ((op) == `OP_ADD  || (op) == `OP_SUB  || (op) == `OP_MUL  || \
     (op) == `OP_DIV  || (op) == `OP_SHL  || (op) == `OP_SHR  || \
     (op) == `OP_AND  || (op) == `OP_OR   || (op) == `OP_XOR  || \
     (op) == `OP_MOVE || (op) == `OP_ADDI || (op) == `OP_SUBI)

// 判断是否为立即数模式 (rs2 == 0)
`define IS_IMM_MODE(rs2) ((rs2) == `REG_R0)

// ============================================================
// 流水线停顿周期数
// ============================================================
`define STALL_LW    2'd2   // LW 停顿 2 周期（等数据到 MEM/WB）
`define STALL_SW    2'd1   // SW 停顿 1 周期
`define STALL_INT   2'd2   // INT 停顿 2 周期

`endif // CPU_DEFINES_V
