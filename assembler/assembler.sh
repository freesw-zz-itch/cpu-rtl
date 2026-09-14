#!/bin/bash
# ============================================================
# CPU 汇编器 - 将汇编代码转换为 32 位机器码
#
# 使用方法:
#   ./assembler.sh [选项] <输入文件>
#
# 示例:
#   ./assembler.sh test.asm
#   ./assembler.sh -v test.asm
#   ./assembler.sh -v -o output.mem test.asm
# ============================================================

# ============================================================
# 颜色定义
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# 指令编码映射
# ============================================================
#
# 32 bit 指令格式:
#
# R:
#   opcode[4:0] | rd[4:0] | rs1[4:0] | rs2[4:0] | 0[11:0]
#
# RI (R 型带立即数支持):
#   寄存器模式: opcode | rd | rs1 | rs2 | 12'b0
#   立即数模式: opcode | rd | rs1 | 5'b0 | imm[11:0]
#
# MV (MOVE):
#   opcode[4:0] | rd[4:0] | rs1[4:0] | 0[4:0] | 0[11:0]
#
# I:
#   opcode[4:0] | rd[4:0] | rs1[4:0] | 0[4:0] | imm[11:0]
#
# S:
#   opcode[4:0] | 0[4:0] | rs1[4:0] | rs2[4:0] | imm[11:0]
#
# B:
#   opcode[4:0] | 0[4:0] | rs1[4:0] | rs2[4:0] | imm[11:0]
#
# J:
#   opcode[4:0] | 0[15:0] | imm[11:0]
#
# Z:
#   opcode[4:0] | 0[27:0]
#
# ============================================================

declare -A OPCODES=(
    ["NOP"]="00000"

    ["ADD"]="00001"
    ["SUB"]="00010"
    ["MUL"]="00011"
    ["DIV"]="00100"

    ["SHL"]="00101"
    ["SHR"]="00110"

    ["AND"]="00111"
    ["OR"]="01000"
    ["XOR"]="01001"

    ["LW"]="01010"
    ["SW"]="01011"

    ["BEQ"]="01100"
    ["JMP"]="01101"

    ["INT"]="01110"
    ["IRET"]="01111"

    ["MOVE"]="10000"

    # ADDI: 立即数加法
    ["ADDI"]="10001"

    # SUBI: 立即数减法
    ["SUBI"]="10010"
)

# ============================================================
# 指令格式
# ============================================================

declare -A INSTR_FORMATS=(
    ["NOP"]="Z"

    ["ADD"]="R"
    ["SUB"]="R"
    ["MUL"]="R"
    ["DIV"]="R"

    ["ADDI"]="I"
    ["SUBI"]="I"

    ["SHL"]="I"
    ["SHR"]="I"

    ["AND"]="R"
    ["OR"]="R"
    ["XOR"]="R"

    ["LW"]="M"
    ["SW"]="S"

    ["BEQ"]="B"
    ["JMP"]="J"

    ["INT"]="Z"
    ["IRET"]="Z"

    # MOVE: 专用格式，2 个操作数
    ["MOVE"]="MV"
)

# ============================================================
# 寄存器映射
# ============================================================

declare -A REGS=(
    ["R0"]="00000"
    ["R1"]="00001"
    ["R2"]="00010"
    ["R3"]="00011"
    ["R4"]="00100"
    ["R5"]="00101"
    ["R6"]="00110"
    ["R7"]="00111"

    ["R8"]="01000"
    ["R9"]="01001"
    ["R10"]="01010"
    ["R11"]="01011"
    ["R12"]="01100"
    ["R13"]="01101"
    ["R14"]="01110"
    ["R15"]="01111"

    ["R16"]="10000"
    ["R17"]="10001"
    ["R18"]="10010"
    ["R19"]="10011"
    ["R20"]="10100"
    ["R21"]="10101"
    ["R22"]="10110"
    ["R23"]="10111"

    ["R24"]="11000"
    ["R25"]="11001"
    ["R26"]="11010"
    ["R27"]="11011"
    ["R28"]="11100"
    ["R29"]="11101"
    ["R30"]="11110"
    ["R31"]="11111"
)

# ============================================================
# 全局变量
# ============================================================

INPUT_FILE=""
OUTPUT_FILE=""

VERBOSE=0
LINE_NUMBER=0

declare -A LABELS
declare -a INSTRUCTION_LINES
declare -a BINARY_OUTPUT

# ============================================================
# 辅助函数
# ============================================================

print_usage() {

    cat << EOF

使用方法:
  $0 [选项] <输入文件>

选项:
  -o <文件>    指定输出文件
               默认: 输入文件名.mem

  -v           显示详细编码信息

  -h           显示帮助信息


汇编语法:

  R 型 (3 个操作数):
    ADD  rd, rs1, rs2
    SUB  rd, rs1, rs2
    MUL  rd, rs1, rs2   # 也支持 MUL rd, rs1, #imm
    DIV  rd, rs1, rs2
    AND  rd, rs1, rs2
    OR   rd, rs1, rs2
    XOR  rd, rs1, rs2

  MV 型 (2 个操作数):
    MOVE rd, rs1          # 寄存器到寄存器复制
    MOVE rd, #imm         # 立即数赋值到寄存器

  I 型 (3 个操作数):
    ADDI rd, rs1, imm   # 立即数加法
    SUBI rd, rs1, imm   # 立即数减法
    SHL  rd, rs1, imm
    SHR  rd, rs1, imm

  内存:
    LW   rd, rs1, imm
    SW   rs2, rs1, imm

  分支:
    BEQ  rs1, rs2, imm
    BEQ  rs1, rs2, label

  跳转:
    JMP  imm
    JMP  label

  无操作数:
    NOP
    INT
    IRET


立即数支持:

  10
  #10
  0x10
  #0x10
  0b1010
  #0b1010


注释支持:

  整行注释:
    # 这是整行注释
    ; 这是整行注释

  行尾注释:
    ADD R1, R0, #1       # 行尾注释
    ADD R1, R0, #1       ; 行尾注释


示例:

  _start:

      MOVE R1, #10        # R1 = 10
      MOVE R2, R1         # R2 = R1 = 10
      ADD  R3, R1, R2     # R3 = 20
      MUL  R4, R3, #2     # R4 = 20 * 2 = 40

      BEQ R3, R1, _end

  _end:

      NOP

EOF
}

error() {

    echo -e "${RED}错误 [行 $LINE_NUMBER]: $1${NC}" >&2

    exit 1
}

warn() {

    echo -e "${YELLOW}警告 [行 $LINE_NUMBER]: $1${NC}" >&2
}

info() {

    echo -e "${BLUE}$1${NC}"
}

success() {

    echo -e "${GREEN}$1${NC}"
}

# ============================================================
# 二进制转十六进制
# ============================================================

bin_to_hex() {

    local bin="$1"

    if [[ ${#bin} -ne 32 ]]; then
        echo "00000000"
        return 1
    fi

    printf "%08X" "$((2#$bin))"
}

# ============================================================
# 十进制转二进制
# ============================================================

dec_to_bin() {

    local num="$1"
    local bits="$2"

    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "0"
        return 1
    fi

    printf "%0${bits}s" \
        "$(echo "obase=2; $num" | bc)" |
        tr ' ' '0'
}

# ============================================================
# 判断是否为寄存器
# ============================================================

is_register() {

    local str="$1"

    str=$(echo "$str" |
        tr '[:lower:]' '[:upper:]' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ -n "${REGS[$str]}" ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================
# 解析数字
#
# 支持:
#
#   10
#   -10
#   #10
#   #-10
#
#   0x10
#   #0x10
#
#   0b1010
#   #0b1010
#
# 如果不是数字，则原样返回，用于标签。
# ============================================================

parse_number() {

    local num="$1"

    num=$(echo "$num" |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 去掉立即数前缀 #
    if [[ "$num" =~ ^# ]]; then
        num="${num:1}"
    fi

    # 十六进制
    if [[ "$num" =~ ^0[xX][0-9a-fA-F]+$ ]]; then

        echo $((16#${num:2}))

        return 0
    fi

    # 二进制
    if [[ "$num" =~ ^0[bB][01]+$ ]]; then

        echo $((2#${num:2}))

        return 0
    fi

    # 十进制
    if [[ "$num" =~ ^-?[0-9]+$ ]]; then

        echo "$num"

        return 0
    fi

    # 标签
    echo "$num"
}

# ============================================================
# 判断是否为立即数
# ============================================================

is_immediate() {

    local str="$1"

    str=$(echo "$str" |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 以 # 开头
    if [[ "$str" =~ ^# ]]; then
        return 0
    fi

    # 数字 (包括负数和十六进制/二进制)
    if [[ "$str" =~ ^-?[0-9]+$ ]] || \
       [[ "$str" =~ ^0[xX][0-9a-fA-F]+$ ]] || \
       [[ "$str" =~ ^0[bB][01]+$ ]]; then
        return 0
    fi

    return 1
}

# ============================================================
# 解析寄存器
# ============================================================

parse_reg() {

    local reg="$1"

    reg=$(echo "$reg" |
        tr '[:lower:]' '[:upper:]' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ -n "${REGS[$reg]}" ]]; then

        echo "${REGS[$reg]}"

    else

        error "未知寄存器: $reg"
    fi
}

# ============================================================
# 获取指令格式
# ============================================================

get_format() {

    local instr="$1"

    instr=$(echo "$instr" |
        tr '[:lower:]' '[:upper:]')

    echo "${INSTR_FORMATS[$instr]}"
}

# ============================================================
# 获取操作码
# ============================================================

get_opcode() {

    local instr="$1"

    instr=$(echo "$instr" |
        tr '[:lower:]' '[:upper:]')

    echo "${OPCODES[$instr]}"
}

# ============================================================
# 清理注释
#
# 重点:
#
#   #1
#   #-1
#   #0x10
#
# 是立即数，不能当注释删除。
#
# 支持注释分隔符:
#
#   #    (当它不在数字前面时)
#   ;
#   //
#
# ============================================================

strip_comment() {

    local line="$1"
    local result=""
    local i=0
    local len=${#line}
    local in_comment=0

    # 逐字符处理
    while [[ $i -lt $len ]]; do

        local char="${line:$i:1}"

        # 如果已经在注释中，跳过
        if [[ $in_comment -eq 1 ]]; then
            ((i++))
            continue
        fi

        # ; 注释
        if [[ "$char" == ";" ]]; then
            in_comment=1
            ((i++))
            continue
        fi

        # // 注释
        if [[ "$char" == "/" ]] && [[ $((i+1)) -lt $len ]] && [[ "${line:$((i+1)):1}" == "/" ]]; then
            in_comment=1
            ((i+=2))
            continue
        fi

        # # 注释 - 需要判断是否紧跟数字或十六进制/二进制前缀
        if [[ "$char" == "#" ]]; then

            # 检查 # 后面是否紧跟数字、负号、或 0x/0b 前缀
            local next_char=""
            local next_two=""

            if [[ $((i+1)) -lt $len ]]; then
                next_char="${line:$((i+1)):1}"
            fi

            if [[ $((i+2)) -lt $len ]]; then
                next_two="${line:$((i+1)):2}"
            fi

            # 判断是否是立即数
            # #数字, #-数字, #0x, #0b
            if [[ "$next_char" =~ ^[0-9]$ ]] || \
               [[ "$next_char" == "-" ]] || \
               [[ "$next_two" == "0x" ]] || \
               [[ "$next_two" == "0X" ]] || \
               [[ "$next_two" == "0b" ]] || \
               [[ "$next_two" == "0B" ]]; then

                # 是立即数，保留 #
                result+="$char"
                ((i++))
                continue
            else
                # 是注释，跳过
                in_comment=1
                ((i++))
                continue
            fi
        fi

        # 正常字符
        result+="$char"
        ((i++))
    done

    echo "$result"
}

# ============================================================
# 解析操作数
# ============================================================

split_operands() {

    local str="$1"

    # 注意:
    #
    # 不能删除 #，因为 #1 是合法立即数

    str=$(echo "$str" |
        tr -d ' \t')

    # 逗号转换为空格

    echo "$str" |
        tr ',' ' '
}

# ============================================================
# 12 位补码转换
#
# 将负数转换为 12 位补码
# ============================================================

to_twos_complement_12() {

    local val="$1"

    if [[ "$val" -lt 0 ]]; then

        val=$((4096 + val))
    fi

    echo "$val"
}

# ============================================================
# 编码 R 型
#
# opcode | rd | rs1 | rs2 | 12'b0
#
# 5 + 5 + 5 + 5 + 12 = 32
# ============================================================

encode_r_type() {

    local opcode="$1"
    local rd="$2"
    local rs1="$3"
    local rs2="$4"

    echo "${opcode}${rd}${rs1}${rs2}000000000000"
}

# ============================================================
# 编码 RI 型 (R 型带立即数支持)
#
# 当使用立即数时，rs2 固定为 0
#
# 寄存器模式:
#   opcode | rd | rs1 | rs2 | 12'b0
#
# 立即数模式:
#   opcode | rd | rs1 | 5'b0 | imm
#
# 5 + 5 + 5 + 5 + 12 = 32
# ============================================================

encode_ri_type() {

    local opcode="$1"
    local rd="$2"
    local rs1="$3"
    local rs2_or_imm="$4"
    local is_imm="$5"

    if [[ "$is_imm" -eq 1 ]]; then

        # 立即数模式: rs2 = 0, 使用 imm
        local imm="$rs2_or_imm"

        # 转换为 12 位补码
        imm=$(to_twos_complement_12 "$imm")

        local imm_bin

        imm_bin=$(printf "%012s" \
            "$(echo "obase=2; $imm" | bc 2>/dev/null || echo "0")" |
            tr ' ' '0')

        echo "${opcode}${rd}${rs1}00000${imm_bin}"

    else

        # 寄存器模式
        local rs2="$rs2_or_imm"

        echo "${opcode}${rd}${rs1}${rs2}000000000000"
    fi
}

# ============================================================
# 编码 I 型
#
# opcode | rd | rs1 | 5'b0 | imm
#
# 5 + 5 + 5 + 5 + 12 = 32
# ============================================================

encode_i_type() {

    local opcode="$1"
    local rd="$2"
    local rs1="$3"
    local imm="$4"

    # 转换为 12 位补码
    imm=$(to_twos_complement_12 "$imm")

    local imm_bin

    imm_bin=$(printf "%012s" \
        "$(echo "obase=2; $imm" | bc 2>/dev/null || echo "0")" |
        tr ' ' '0')

    echo "${opcode}${rd}${rs1}00000${imm_bin}"
}

# ============================================================
# 编码 M 型
#
# 当前与 I 型相同
# ============================================================

encode_m_type() {

    encode_i_type "$1" "$2" "$3" "$4"
}

# ============================================================
# 编码 S 型
#
# opcode | 0 | rs1 | rs2 | imm
#
# 5 + 5 + 5 + 5 + 12 = 32
# ============================================================

encode_s_type() {

    local opcode="$1"
    local rs1="$2"
    local rs2="$3"
    local imm="$4"

    # 转换为 12 位补码
    imm=$(to_twos_complement_12 "$imm")

    local imm_bin

    imm_bin=$(printf "%012s" \
        "$(echo "obase=2; $imm" | bc 2>/dev/null || echo "0")" |
        tr ' ' '0')

    echo "${opcode}00000${rs1}${rs2}${imm_bin}"
}

# ============================================================
# 编码 B 型
#
# opcode | 0 | rs1 | rs2 | imm
#
# 5 + 5 + 5 + 5 + 12 = 32
# ============================================================

encode_b_type() {

    local opcode="$1"
    local rs1="$2"
    local rs2="$3"
    local imm="$4"

    # 转换为 12 位补码
    imm=$(to_twos_complement_12 "$imm")

    local imm_bin

    imm_bin=$(printf "%012s" \
        "$(echo "obase=2; $imm" | bc 2>/dev/null || echo "0")" |
        tr ' ' '0')

    echo "${opcode}00000${rs1}${rs2}${imm_bin}"
}

# ============================================================
# 编码 J 型
#
# opcode | 15'b0 | imm
#
# 5 + 15 + 12 = 32
# ============================================================

encode_j_type() {

    local opcode="$1"
    local imm="$2"

    # 转换为 12 位补码
    imm=$(to_twos_complement_12 "$imm")

    local imm_bin

    imm_bin=$(printf "%012s" \
        "$(echo "obase=2; $imm" | bc 2>/dev/null || echo "0")" |
        tr ' ' '0')

    echo "${opcode}000000000000000${imm_bin}"
}

# ============================================================
# 编码 Z 型
#
# opcode | 27'b0
#
# 5 + 27 = 32
# ============================================================

encode_z_type() {

    local opcode="$1"

    echo "${opcode}000000000000000000000000000"
}

# ============================================================
# 检查立即数
#
# 当前 ISA 使用 12 bit 有符号立即数:
#
#   -2048 ~ +2047
#
# ============================================================

check_imm() {

    local imm="$1"
    local name="$2"

    if ! [[ "$imm" =~ ^-?[0-9]+$ ]]; then

        error "$name 不是有效数字: $imm"
    fi

    if [[ "$imm" -lt -2048 ]] || [[ "$imm" -gt 2047 ]]; then

        error "$name 超出范围 (-2048 ~ 2047): $imm"
    fi
}

# ============================================================
# 编码单条指令
# ============================================================

encode_instruction() {

    local line="$1"
    local addr="$2"

    local instr=""
    local operands=""

    # ----------------------------------------
    # 删除注释
    # ----------------------------------------

    line=$(strip_comment "$line")

    line=$(echo "$line" |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 空行
    [[ -z "$line" ]] && return 0

    # ----------------------------------------
    # 标签
    # ----------------------------------------

    if echo "$line" |
        grep -qE '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*:$'; then

        return 0
    fi

    # ----------------------------------------
    # 提取指令和操作数
    # ----------------------------------------

    if [[ "$line" =~ ^([a-zA-Z]+)[[:space:]]+(.*)$ ]]; then

        instr="${BASH_REMATCH[1]}"
        operands="${BASH_REMATCH[2]}"

    else

        instr="$line"
        operands=""
    fi

    # ----------------------------------------
    # 指令转大写
    # ----------------------------------------

    instr=$(echo "$instr" |
        tr '[:lower:]' '[:upper:]')

    # ----------------------------------------
    # 检查指令
    # ----------------------------------------

    if [[ -z "${OPCODES[$instr]}" ]]; then

        error "未知指令: $instr"
    fi

    local opcode
    local fmt

    opcode=$(get_opcode "$instr")
    fmt=$(get_format "$instr")

    # ----------------------------------------
    # 解析操作数
    # ----------------------------------------

    local op_str

    op_str=$(split_operands "$operands")

    # shellcheck disable=SC2086
    set -- $op_str

    local op_array=("$@")
    local num_ops=${#op_array[@]}

    local binary=""

    # ========================================================
    # R 型 (3 个操作数)
    #
    # ADD  rd, rs1, rs2
    # SUB  rd, rs1, rs2
    # MUL  rd, rs1, rs2   # 支持立即数: MUL rd, rs1, #imm
    # DIV  rd, rs1, rs2
    # AND  rd, rs1, rs2
    # OR   rd, rs1, rs2
    # XOR  rd, rs1, rs2
    # ========================================================

    case "$fmt" in

        "R")

            if [[ "$num_ops" -ne 3 ]]; then

                error "$instr 需要 3 个操作数 (rd, rs1, src)，当前有 $num_ops 个: ${op_array[*]}"
            fi

            local rd
            local rs1
            local src

            rd=$(parse_reg "${op_array[0]}")
            rs1=$(parse_reg "${op_array[1]}")
            src="${op_array[2]}"

            # 检查第三个操作数是否是立即数
            local is_imm=0
            local imm=""

            if is_immediate "$src"; then

                is_imm=1

                imm=$(parse_number "$src")

                # 检查是否是有效数字
                if ! [[ "$imm" =~ ^-?[0-9]+$ ]]; then
                    if [[ -n "${LABELS[$imm]}" ]]; then
                        imm="${LABELS[$imm]}"
                    else
                        error "无效的立即数: $src"
                    fi
                fi

                # 检查立即数范围 (12位有符号)
                check_imm "$imm" "立即数"

                # MUL 支持立即数，其他指令不支持
                if [[ "$instr" != "MUL" ]]; then
                    error "$instr 不支持立即数模式，请使用寄存器"
                fi

                binary=$(encode_ri_type \
                    "$opcode" \
                    "$rd" \
                    "$rs1" \
                    "$imm" \
                    1)

            else

                # 寄存器模式
                local rs2

                rs2=$(parse_reg "$src")

                binary=$(encode_ri_type \
                    "$opcode" \
                    "$rd" \
                    "$rs1" \
                    "$rs2" \
                    0)
            fi

            ;;

        # ====================================================
        # MV 型 (MOVE - 2 个操作数)
        #
        # 支持两种模式:
        #   1. MOVE rd, rs1  -> 寄存器到寄存器复制
        #   2. MOVE rd, #imm -> 立即数赋值到寄存器 (rs2=0)
        #
        # 编码: opcode | rd | rs1 | rs2 | 0
        #       rd = 目标寄存器
        #       rs1 = 源寄存器 (如果第二个参数是立即数，则 rs1 = 0)
        #       rs2 = 0
        # ====================================================

        "MV")

            if [[ "$num_ops" -ne 2 ]]; then

                error "$instr 需要 2 个操作数 (rd, src)，当前有 $num_ops 个: ${op_array[*]}"
            fi

            local rd
            local src
            local rs1
            local rs2

            rd=$(parse_reg "${op_array[0]}")
            src="${op_array[1]}"

            # 判断第二个操作数是寄存器还是立即数
            if is_register "$src"; then

                # 模式1: MOVE rd, rs1 (寄存器到寄存器)
                rs1=$(parse_reg "$src")
                rs2="00000"

                # 寄存器模式: 使用 R 型编码，rs2 固定为 0
                binary=$(encode_r_type \
                    "$opcode" \
                    "$rd" \
                    "$rs1" \
                    "$rs2")

            else

                # 模式2: MOVE rd, #imm (立即数赋值)
                # 此时 rs1 = 0，rs2 = 0
                rs1="00000"
                rs2="00000"

                # 检查是否是有效的立即数
                local imm
                imm=$(parse_number "$src")

                if ! [[ "$imm" =~ ^-?[0-9]+$ ]]; then
                    if [[ -n "${LABELS[$imm]}" ]]; then
                        imm="${LABELS[$imm]}"
                    else
                        error "MOVE 的第二个操作数必须是寄存器或立即数: $src"
                    fi
                fi

                # 检查立即数范围 (12位有符号)
                check_imm "$imm" "立即数"

                # 使用 I 型编码: opcode | rd | 0 | 0 | imm
                binary=$(encode_i_type \
                    "$opcode" \
                    "$rd" \
                    "00000" \
                    "$imm")

                # 直接输出并返回
                if [[ ${#binary} -ne 32 ]]; then
                    error "编码错误: 二进制长度为 ${#binary} (期望 32)"
                fi

                local hex
                hex=$(bin_to_hex "$binary")

                if [[ "$VERBOSE" -eq 1 ]]; then
                    printf \
                        "  0x%08X: %-30s -> 0x%s\n" \
                        "$((addr * 4))" \
                        "$line" \
                        "$hex"
                fi

                BINARY_OUTPUT[$addr]="$hex"
                return 0
            fi

            ;;

        # ====================================================
        # I 型
        #
        # ADDI
        # SUBI
        # SHL
        # SHR
        #
        # rd, rs1, imm
        # ====================================================

        "I")

            if [[ "$num_ops" -ne 3 ]]; then

                error "$instr 需要 3 个操作数 (rd, rs1, imm)，当前有 $num_ops 个: ${op_array[*]}"
            fi

            local rd
            local rs1
            local imm

            rd=$(parse_reg "${op_array[0]}")
            rs1=$(parse_reg "${op_array[1]}")
            imm=$(parse_number "${op_array[2]}")

            # --------------------------------------------
            # 标签
            # --------------------------------------------

            if ! [[ "$imm" =~ ^-?[0-9]+$ ]]; then

                if [[ -n "${LABELS[$imm]}" ]]; then

                    imm="${LABELS[$imm]}"

                else

                    error "未定义的标签: $imm"
                fi
            fi

            check_imm "$imm" "立即数"

            binary=$(encode_i_type \
                "$opcode" \
                "$rd" \
                "$rs1" \
                "$imm")

            ;;

        # ====================================================
        # M 型
        #
        # LW rd, rs1, imm
        # ====================================================

        "M")

            if [[ "$num_ops" -ne 3 ]]; then

                error "$instr 需要 3 个操作数 (rd, rs1, imm)，当前有 $num_ops 个: ${op_array[*]}"
            fi

            local rd
            local rs1
            local imm

            rd=$(parse_reg "${op_array[0]}")
            rs1=$(parse_reg "${op_array[1]}")
            imm=$(parse_number "${op_array[2]}")

            if ! [[ "$imm" =~ ^-?[0-9]+$ ]]; then

                if [[ -n "${LABELS[$imm]}" ]]; then

                    imm="${LABELS[$imm]}"

                else

                    error "未定义的标签: $imm"
                fi
            fi

            check_imm "$imm" "立即数"

            binary=$(encode_m_type \
                "$opcode" \
                "$rd" \
                "$rs1" \
                "$imm")

            ;;

        # ====================================================
        # S 型
        #
        # SW rs2, rs1, imm
        # ====================================================

        "S")

            if [[ "$num_ops" -ne 3 ]]; then

                error "$instr 需要 3 个操作数 (rs2, rs1, imm)，当前有 $num_ops 个: ${op_array[*]}"
            fi

            local rs2
            local rs1
            local imm

            rs2=$(parse_reg "${op_array[0]}")
            rs1=$(parse_reg "${op_array[1]}")
            imm=$(parse_number "${op_array[2]}")

            if ! [[ "$imm" =~ ^-?[0-9]+$ ]]; then

                if [[ -n "${LABELS[$imm]}" ]]; then

                    imm="${LABELS[$imm]}"

                else

                    error "未定义的标签: $imm"
                fi
            fi

            check_imm "$imm" "立即数"

            binary=$(encode_s_type \
                "$opcode" \
                "$rs1" \
                "$rs2" \
                "$imm")

            ;;

        # ====================================================
        # B 型
        #
        # BEQ rs1, rs2, imm
        # BEQ rs1, rs2, label
        #
        # 注意: label 是索引地址，需要左移 2 位得到字节地址
        # ====================================================

        "B")

            if [[ "$num_ops" -ne 3 ]]; then

                error "$instr 需要 3 个操作数 (rs1, rs2, imm/label)，当前有 $num_ops 个: ${op_array[*]}"
            fi

            local rs1
            local rs2
            local imm

            rs1=$(parse_reg "${op_array[0]}")
            rs2=$(parse_reg "${op_array[1]}")
            imm=$(parse_number "${op_array[2]}")

            if ! [[ "$imm" =~ ^-?[0-9]+$ ]]; then

                if [[ -n "${LABELS[$imm]}" ]]; then

                    local target

                    target="${LABELS[$imm]}"

                    # PC 相对偏移
                    # target 是索引地址，需要左移 2 位得到字节地址
                    # 偏移 = (target - current - 1) 条指令
                    # 然后左移 2 位
                    imm=$(( (target - addr - 1) << 2 ))

                else

                    error "未定义的标签: $imm"
                fi
            fi

            check_imm "$imm" "分支偏移"

            binary=$(encode_b_type \
                "$opcode" \
                "$rs1" \
                "$rs2" \
                "$imm")

            ;;

        # ====================================================
        # J 型
        #
        # JMP imm
        # JMP label
        #
        # 注意: label 是索引地址，需要左移 2 位得到字节地址
        # ====================================================

        "J")

            if [[ "$num_ops" -ne 1 ]]; then

                error "$instr 需要 1 个操作数 (imm/label)，当前有 $num_ops 个: ${op_array[*]}"
            fi

            local imm

            imm=$(parse_number "${op_array[0]}")

            if ! [[ "$imm" =~ ^-?[0-9]+$ ]]; then

                if [[ -n "${LABELS[$imm]}" ]]; then

                    # label 是索引地址，左移 2 位得到字节地址
                    imm=$((imm << 2))

                else

                    error "未定义的标签: $imm"
                fi
            fi

            check_imm "$imm" "跳转地址"

            binary=$(encode_j_type \
                "$opcode" \
                "$imm")

            ;;

        # ====================================================
        # Z 型
        # ====================================================

        "Z")

            if [[ "$num_ops" -ne 0 ]]; then

                error "$instr 不需要操作数，当前有 $num_ops 个: ${op_array[*]}"
            fi

            binary=$(encode_z_type "$opcode")

            ;;

        *)

            error "未知指令格式: $fmt"

            ;;
    esac

    # ========================================================
    # 检查最终编码长度
    # ========================================================

    if [[ ${#binary} -ne 32 ]]; then

        error "编码错误: 二进制长度为 ${#binary} (期望 32)"
    fi

    # ========================================================
    # 转十六进制
    # ========================================================

    local hex

    hex=$(bin_to_hex "$binary")

    # ========================================================
    # verbose
    # ========================================================

    if [[ "$VERBOSE" -eq 1 ]]; then

        printf \
            "  0x%08X: %-30s -> 0x%s\n" \
            "$((addr * 4))" \
            "$line" \
            "$hex"
    fi

    # ========================================================
    # 保存
    # ========================================================

    BINARY_OUTPUT[$addr]="$hex"

    return 0
}

# ============================================================
# 第一遍扫描
#
# 作用:
#
#   1. 找到所有标签
#   2. 计算标签对应的指令地址
#   3. 保存指令
#
# ============================================================

first_pass() {

    local line_num=0
    local addr=0

    while IFS= read -r line || [[ -n "$line" ]]; do

        ((line_num++))

        LINE_NUMBER="$line_num"

        # ----------------------------------------
        # 清理注释
        # ----------------------------------------

        local clean_line

        clean_line=$(strip_comment "$line")

        clean_line=$(echo "$clean_line" |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 空行
        [[ -z "$clean_line" ]] && continue

        # ----------------------------------------
        # 标签
        # ----------------------------------------

        if echo "$clean_line" |
            grep -qE '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*:$'; then

            local label

            label=$(echo "$clean_line" |
                sed 's/[[:space:]]*://')

            # 检查重复标签
            if [[ -n "${LABELS[$label]}" ]]; then

                error "重复定义的标签: $label"
            fi

            LABELS["$label"]="$addr"

            if [[ "$VERBOSE" -eq 1 ]]; then

                info "  标签收集: $label = 0x$(printf "%08X" "$((addr * 4))")"
            fi

            continue
        fi

        # ----------------------------------------
        # 指令
        # ----------------------------------------

        if [[ "$clean_line" =~ ^[a-zA-Z] ]]; then

            INSTRUCTION_LINES[$addr]="$clean_line"

            ((addr++))
        fi

    done < "$INPUT_FILE"

    if [[ "$VERBOSE" -eq 1 ]]; then

        info "  总指令数: $addr"
    fi
}

# ============================================================
# 第二遍扫描
# ============================================================

second_pass() {

    for ((i = 0; i < ${#INSTRUCTION_LINES[@]}; i++)); do

        if [[ -n "${INSTRUCTION_LINES[$i]}" ]]; then

            LINE_NUMBER=$((i + 1))

            encode_instruction \
                "${INSTRUCTION_LINES[$i]}" \
                "$i"
        fi
    done
}

# ============================================================
# 生成 MEM 文件
# ============================================================

generate_output() {

    local output_file="$1"

    local output_dir

    output_dir=$(dirname "$output_file")

    if [[ "$output_dir" != "." ]] &&
       [[ ! -d "$output_dir" ]]; then

        mkdir -p "$output_dir"
    fi

    cat > "$output_file" << 'EOF'
// ============================================================
// 自动生成的机器码
//
// 格式:
//   mem[index] = 32'hxxxxxxxx;
//
// 地址:
//   index * 4
//
// ============================================================

EOF

    local max_addr=0

    for addr in "${!BINARY_OUTPUT[@]}"; do

        if [[ "$addr" -gt "$max_addr" ]]; then

            max_addr="$addr"
        fi
    done

    for ((addr = 0; addr <= max_addr; addr++)); do

        if [[ -n "${BINARY_OUTPUT[$addr]}" ]]; then

            printf \
                "mem[%d] = 32'h%s;  // 地址 0x%02X\n" \
                "$addr" \
                "${BINARY_OUTPUT[$addr]}" \
                "$((addr * 4))" \
                >> "$output_file"

        else

            printf \
                "mem[%d] = 32'h00000000;  // NOP\n" \
                "$addr" \
                >> "$output_file"
        fi
    done

    success \
        "  生成 ${#BINARY_OUTPUT[@]} 条指令到 $output_file"
}

# ============================================================
# 生成 LST
# ============================================================

generate_listing() {

    local list_file="${OUTPUT_FILE%.mem}.lst"

    cat > "$list_file" << 'EOF'
; ============================================================
; 汇编列表文件
;
; 地址: 机器码 | 汇编指令
; ============================================================

EOF

    local max_addr=0

    for addr in "${!BINARY_OUTPUT[@]}"; do

        if [[ "$addr" -gt "$max_addr" ]]; then

            max_addr="$addr"
        fi
    done

    for ((addr = 0; addr <= max_addr; addr++)); do

        if [[ -n "${BINARY_OUTPUT[$addr]}" ]]; then

            local hex="${BINARY_OUTPUT[$addr]}"
            local instr="${INSTRUCTION_LINES[$addr]}"

            printf \
                "0x%08X: 0x%s | %s\n" \
                "$((addr * 4))" \
                "$hex" \
                "$instr" \
                >> "$list_file"

        else

            printf \
                "0x%08X: 0x00000000 | NOP\n" \
                "$((addr * 4))" \
                >> "$list_file"
        fi
    done

    if [[ "$VERBOSE" -eq 1 ]]; then

        info "  生成列表文件: $list_file"
    fi
}

# ============================================================
# 生成 Verilog 测试代码
# ============================================================

generate_verilog_test() {

    local test_file="test_program.v"

    cat > "$test_file" << 'EOF'
// ============================================================
// 测试程序
//
// 可用于 program_storage.v
// ============================================================

module test_program;

    reg [31:0] mem [0:63];

    initial begin

EOF

    local max_addr=0

    for addr in "${!BINARY_OUTPUT[@]}"; do

        if [[ "$addr" -gt "$max_addr" ]]; then

            max_addr="$addr"
        fi
    done

    for ((addr = 0; addr <= max_addr; addr++)); do

        if [[ -n "${BINARY_OUTPUT[$addr]}" ]]; then

            printf \
                "        mem[%d] = 32'h%s;\n" \
                "$addr" \
                "${BINARY_OUTPUT[$addr]}" \
                >> "$test_file"

        else

            printf \
                "        mem[%d] = 32'h00000000;\n" \
                "$addr" \
                >> "$test_file"
        fi
    done

    cat >> "$test_file" << 'EOF'

        // 其余填充 NOP

        for (int i = 32; i < 64; i = i + 1) begin

            mem[i] = 32'h00000000;

        end

    end

endmodule
EOF

    if [[ "$VERBOSE" -eq 1 ]]; then

        info "  生成 Verilog 测试文件: $test_file"
    fi
}

# ============================================================
# 参数解析
# ============================================================

parse_args() {

    while [[ $# -gt 0 ]]; do

        case "$1" in

            -o)

                if [[ -z "$2" ]]; then

                    echo "错误: -o 需要指定输出文件"

                    exit 1
                fi

                OUTPUT_FILE="$2"

                shift 2

                ;;

            -v)

                VERBOSE=1

                shift

                ;;

            -h|--help)

                print_usage

                exit 0

                ;;

            -*)

                echo "未知选项: $1"

                print_usage

                exit 1

                ;;

            *)

                if [[ -n "$INPUT_FILE" ]]; then

                    echo "错误: 指定了多个输入文件"

                    exit 1
                fi

                INPUT_FILE="$1"

                shift

                ;;
        esac
    done

    # ----------------------------------------
    # 检查输入文件
    # ----------------------------------------

    if [[ -z "$INPUT_FILE" ]]; then

        echo "错误: 未指定输入文件"

        print_usage

        exit 1
    fi

    if [[ ! -f "$INPUT_FILE" ]]; then

        echo "错误: 文件不存在: $INPUT_FILE"

        exit 1
    fi

    # ----------------------------------------
    # 默认输出文件
    # ----------------------------------------

    if [[ -z "$OUTPUT_FILE" ]]; then

        OUTPUT_FILE="${INPUT_FILE%.asm}.mem"
    fi
}

# ============================================================
# 主函数
# ============================================================

main() {

    echo "========================================"
    echo "    CPU 汇编器"
    echo "========================================"

    echo ""

    parse_args "$@"

    info "输入文件: $INPUT_FILE"
    info "输出文件: $OUTPUT_FILE"

    if [[ "$VERBOSE" -eq 1 ]]; then

        info "详细模式: 开启"
    fi

    echo ""

    # ========================================================
    # 第一遍
    # ========================================================

    info "第一遍扫描: 收集标签..."

    first_pass

    if [[ "$VERBOSE" -eq 1 ]]; then

        echo ""

        info "发现的标签:"

        if [[ ${#LABELS[@]} -gt 0 ]]; then

            for label in "${!LABELS[@]}"; do

                printf \
                    "  %s = 0x%08X\n" \
                    "$label" \
                    "$(( ${LABELS[$label]} * 4 ))"
            done

        else

            info "  (无标签)"
        fi

        echo ""
    fi

    # ========================================================
    # 第二遍
    # ========================================================

    info "第二遍扫描: 编码指令..."

    second_pass

    # ========================================================
    # 输出
    # ========================================================

    info "生成输出文件..."

    generate_output "$OUTPUT_FILE"

    generate_listing

    generate_verilog_test

    echo ""

    success "汇编完成!"

    echo ""

    info "生成的文件:"

    echo "  - $OUTPUT_FILE (机器码)"
    echo "  - ${OUTPUT_FILE%.mem}.lst (汇编列表)"
    echo "  - test_program.v (Verilog 测试文件)"
}

# ============================================================
# 程序入口
# ============================================================

main "$@"