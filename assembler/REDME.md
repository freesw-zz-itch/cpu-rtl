# 赋予执行权限
chmod +x assembler.sh

# 运行汇编器
./assembler.sh test.asm

# 或者指定输出文件
./assembler.sh -o program.mem test.asm

# 详细模式
./assembler.sh -v test.asm
