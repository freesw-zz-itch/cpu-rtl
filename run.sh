#!/bin/bash
# ============================================================
# 5级流水线CPU仿真运行脚本
# 支持双口RAM测试
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 创建 build 目录
mkdir -p build

# 删除旧波形文件
if [ -f "build/cpu_waveform.vcd" ]; then
    echo -e "${YELLOW}Removing old waveform file: build/cpu_waveform.vcd${NC}"
    rm -f build/cpu_waveform.vcd
fi

if [ -f "build/dual_port_wave.vcd" ]; then
    echo -e "${YELLOW}Removing old waveform file: build/dual_port_wave.vcd${NC}"
    rm -f build/dual_port_wave.vcd
fi

echo "========================================="
echo "5-Stage Pipeline CPU Simulator"
echo "(with Dual-Port RAM Support)"
echo "========================================="

# 检查 iverilog 是否安装
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}Error: iverilog not found.${NC}"
    echo "Ubuntu: sudo apt-get install iverilog"
    echo "macOS:  brew install icarus-verilog"
    exit 1
fi

# ============================================================
# 编译CPU测试
# ============================================================
echo -e "${GREEN}Compiling CPU testbench...${NC}"

iverilog -g2012 -Wall -o build/cpu_sim \
    cpu_defines.v \
    register_bank.v \
    mem_arbiter.v \
    data_storage.v \
    program_storage.v \
    interrupt_handler.v \
    instruction_fetcher.v \
    instruction_decoder.v \
    arithmetic_unit.v \
    memory_access.v \
    write_back.v \
    data_forwarder.v \
    pipeline_controller.v \
    cpu_core.v \
    cpu_tb.v

if [ $? -ne 0 ]; then
    echo -e "${RED}CPU compilation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}CPU compilation successful!${NC}"

# ============================================================
# 编译双口RAM独立测试
# ============================================================
echo -e "${GREEN}Compiling Dual-Port RAM testbench...${NC}"

iverilog -g2012 -Wall -o build/dual_port_test \
    data_storage.v \
    test_dual_port.v

if [ $? -ne 0 ]; then
    echo -e "${RED}Dual-Port RAM compilation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Dual-Port RAM compilation successful!${NC}"
echo ""

# ============================================================
# 运行双口RAM独立测试
# ============================================================
echo -e "${GREEN}Running Dual-Port RAM test...${NC}"
cd build
vvp dual_port_test
cd ..

if [ $? -ne 0 ]; then
    echo -e "${RED}Dual-Port RAM test failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Dual-Port RAM test completed!${NC}"
echo ""

# ============================================================
# 运行CPU仿真
# ============================================================
echo -e "${GREEN}Running CPU simulation...${NC}"
cd build
vvp cpu_sim

if [ $? -ne 0 ]; then
    echo -e "${RED}CPU simulation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}CPU simulation completed successfully!${NC}"
echo ""

cd ..

# ============================================================
# 检查波形文件
# ============================================================
if [ -f "build/cpu_waveform.vcd" ]; then
    echo -e "${GREEN}CPU Waveform saved to build/cpu_waveform.vcd${NC}"
else
    echo -e "${RED}Warning: CPU Waveform file not found!${NC}"
fi

if [ -f "build/dual_port_wave.vcd" ]; then
    echo -e "${GREEN}Dual-Port RAM Waveform saved to build/dual_port_wave.vcd${NC}"
else
    echo -e "${RED}Warning: Dual-Port RAM Waveform file not found!${NC}"
fi

if command -v gtkwave &> /dev/null; then
    echo -e "${YELLOW}Do you want to open the waveform with GTKWave? (y/n)${NC}"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        echo "Opening waveform viewer..."
        gtkwave build/cpu_waveform.vcd &
    fi
else
    echo -e "${YELLOW}GTKWave not found. Install it to view waveform:${NC}"
    echo "Ubuntu: sudo apt-get install gtkwave"
    echo "macOS:  brew install gtkwave"
fi

echo ""
echo -e "${GREEN}Done!${NC}"
