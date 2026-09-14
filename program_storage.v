// ============================================================
// 程序存储器
// ============================================================

`include "cpu_defines.v"

module program_storage (
    input  wire [31:0] addr,
    output reg  [31:0] data
);

    parameter MEM_SIZE = 1024;
    reg [31:0] mem [0:MEM_SIZE-1];

    // ============================================================
    // 指令构建函数
    // ============================================================
    
    function [31:0] build_instr;
        input [4:0]  opcode;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [4:0]  rs2;
        input [11:0] imm;
        begin
            build_instr = {opcode, rd, rs1, rs2, imm};
        end
    endfunction

    initial begin
        // ============================================================
        // 测试程序: (10 + 5) * 2 = 30
        // ============================================================
        
        // // 地址 0x00: ADDI R1, R0, #10
        // mem[0] = build_instr(`OP_ADDI, `REG_R1, `REG_R0, `REG_R0, 12'h00A);
        
        // // 地址 0x04: MOVE R2, #5
        // mem[1] = build_instr(`OP_MOVE, `REG_R2, `REG_R0, `REG_R0, 12'h005);
        
        // // 地址 0x08: ADD R3, R1, R2
        // mem[2] = build_instr(`OP_ADD, `REG_R3, `REG_R1, `REG_R2, 12'h000);
        
        // // 地址 0x0C: MUL R0, R3, #2
        // mem[3] = build_instr(`OP_MUL, `REG_R0, `REG_R3, `REG_R0, 12'h002);
        
        // // 地址 0x10: NOP
        // mem[4] = 32'h00000000;

        // mem[0] = 32'h8840000A;  // 地址 0x00
        // mem[1] = 32'h80800005;  // 地址 0x04
        // mem[2] = 32'h08C22000;  // 地址 0x08
        // mem[3] = 32'h18060002;  // 地址 0x0C
        // mem[4] = 32'h81000000;  // 地址 0x10
        // mem[5] = 32'h58080000;  // 地址 0x14
        // mem[6] = 32'h51480000;  // 地址 0x18
        // mem[7] = 32'h00000000;  // 地址 0x1C
        mem[0] = 32'h80400005;  // 地址 0x00
        mem[1] = 32'h80800000;  // 地址 0x04
        mem[2] = 32'h58041000;  // 地址 0x08
        mem[3] = 32'h00000000;  // 地址 0x0C
        
        // 其余填充 NOP
        for (int i = 4; i < MEM_SIZE; i = i + 1) begin
            mem[i] = 32'h00000000;
        end
    end

    always @(*) begin
        data = mem[addr[7:2]];
    end

endmodule
