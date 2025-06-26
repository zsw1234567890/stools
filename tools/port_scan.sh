#!/bin/bash

# =============================== #
# 指定 IP 端口扫描脚本
# 作者: Kilo Code (基于 frogchou 的 stools 框架)
# 功能: 对指定的目标 IP 地址执行端口扫描。
# 特点:
#   - 自动检测并安装依赖 (nmap)
#   - 支持指定端口范围或常用端口扫描
#   - 清晰的参数使用提示和错误处理
#   - 详细注释，易于理解和修改
#
# 使用方式：
#   1. ./port_scan.sh <目标IP>                      # 扫描目标IP的常用端口 (nmap 默认)
#   2. ./port_scan.sh <目标IP> <端口号>             # 扫描目标IP的指定单个端口 (例如: 80)
#   3. ./port_scan.sh <目标IP> <起始端口-结束端口>  # 扫描目标IP的指定端口范围 (例如: 1-1024)
#   4. ./port_scan.sh <目标IP> <端口1,端口2,...>    # 扫描目标IP的多个指定端口 (例如: 22,80,443)
#   5. ./port_scan.sh <目标IP> -F                   # 快速扫描 (nmap -F，扫描 nmap-services 中列出的端口)
#   6. ./port_scan.sh <目标IP> -p-                  # 扫描目标IP的所有TCP端口 (1-65535)
# =============================== #

# --- 配置 ---
# 依赖的命令
REQUIRED_COMMANDS=("nmap")

# --- 函数定义 ---

# 打印错误信息并退出
# 参数:
#   $1: 错误信息字符串
error_exit() {
    echo "❌ 错误: $1" >&2
    exit 1
}

# 打印使用说明并退出
usage() {
    echo "❗ 参数错误或缺少参数。"
    echo "✅ 使用示例："
    echo "  $0 <目标IP>                      # 扫描目标IP的常用端口"
    echo "  $0 <目标IP> 80                    # 扫描目标IP的端口 80"
    echo "  $0 <目标IP> 1-1024                # 扫描目标IP的端口范围 1-1024"
    echo "  $0 <目标IP> 22,80,443             # 扫描目标IP的端口 22, 80, 和 443"
    echo "  $0 <目标IP> -F                    # 快速扫描 (nmap -F)"
    echo "  $0 <目标IP> -p-                   # 扫描所有TCP端口 (1-65535)"
    echo ""
    echo "ℹ️  <目标IP> 可以是单个IP地址或主机名。"
    echo "ℹ️  端口参数遵循 nmap 的 -p 选项格式。"
    exit 1
}

# 检查并安装依赖命令
install_dependencies() {
    local missing_deps=()
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "⚠️  检测到以下依赖命令缺失: ${missing_deps[*]}"
        echo "ℹ️  尝试自动安装..."
        # 尝试使用常见的包管理器安装
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y "${missing_deps[@]}"
        elif [ -x "$(command -v dnf)" ]; then
            sudo dnf install -y "${missing_deps[@]}"
        elif [ -x "$(command -v pacman)" ]; then
            sudo pacman -Syu --noconfirm "${missing_deps[@]}"
        elif [ -x "$(command -v zypper)" ]; then
            sudo zypper install -y "${missing_deps[@]}"
        else
            echo "❌ 无法确定包管理器或自动安装失败。"
            echo "   请手动安装以下命令: ${missing_deps[*]} 然后重试。"
            exit 1
        fi

        # 再次检查依赖是否安装成功
        for cmd in "${missing_deps[@]}"; do
            if ! command -v "$cmd" &> /dev/null; then
                error_exit "依赖命令 $cmd 安装后仍未找到。请手动检查安装。"
            fi
        done
        echo "✅ 依赖命令已成功安装。"
    else
        echo "✅ 所有依赖命令已满足。"
    fi
}

# 验证IP地址或主机名的基本格式 (非严格验证，nmap 会做最终判断)
# 参数:
#   $1: IP地址或主机名
validate_target() {
    local target="$1"
    # 简单的检查，不为空即可。nmap 会处理无效的目标。
    if [ -z "$target" ]; then
        return 1
    fi
    return 0
}

# 执行端口扫描
# 参数:
#   $1: 目标IP或主机名
#   $2: (可选) nmap 的端口参数 (例如 "80", "1-1024", "22,80,443", "-F", "-p-")
perform_scan() {
    local target="$1"
    local port_specifier="$2"
    local nmap_args=("-Pn") # -Pn: 跳过主机发现，直接扫描端口 (假设目标存活)

    echo "🎯 目标: $target"

    if [ -n "$port_specifier" ]; then
        # 如果 port_specifier 是 -F 或 -p-，它们本身就是 nmap 的选项
        if [[ "$port_specifier" == "-F" || "$port_specifier" == "-p-" ]]; then
            nmap_args+=("$port_specifier")
            echo " SCAN_TYPE: $port_specifier"
        else
            # 否则，它是一个端口列表/范围，需要 -p 选项
            nmap_args+=("-p" "$port_specifier")
            echo " SCAN_PORTS: $port_specifier"
        fi
    else
        echo " SCAN_TYPE: 常用端口 (nmap 默认)"
        # 如果不指定端口，nmap 默认扫描大约1000个常用端口
        # 可以添加 -F 进行快速扫描，或者不加参数让 nmap 自行决定
        # nmap_args+=("-F") # 或者移除此行，使用 nmap 纯默认
    fi

    echo "🔍 正在对 $target 执行端口扫描 (nmap ${nmap_args[*]})..."
    echo "--------------------------------------------------"
    # -v 用于增加详细程度，可以根据需要调整或移除
    # sudo nmap -v "${nmap_args[@]}" "$target"
    # 考虑到 stools 可能没有 sudo 权限，先尝试非 sudo 执行
    # 对于某些扫描类型 (如 -sS SYN扫描)，nmap 需要 root 权限
    # 如果需要 SYN 扫描等，用户需要以 sudo 方式运行 stl port_scan ...
    if command -v sudo &> /dev/null && [ "$EUID" -ne 0 ] && ( [[ " ${nmap_args[*]} " =~ " -sS " ]] || [[ " ${nmap_args[*]} " =~ " -sU " ]] ) ; then
        echo "ℹ️  某些nmap扫描类型 (如SYN扫描) 可能需要root权限以获得最佳效果或避免错误。"
        echo "    如果遇到问题，请尝试使用 'sudo stl port_scan ...' 或直接 'sudo $0 ...'"
    fi

    nmap "${nmap_args[@]}" "$target"
    echo "--------------------------------------------------"
    echo "✅ 端口扫描完成。"
}

# --- 主逻辑 ---
main() {
    # 步骤1: 检查并安装依赖
    install_dependencies

    # 步骤2: 解析参数
    if [ $# -lt 1 ] || [ $# -gt 2 ]; then
        usage
    fi

    local target_ip="$1"
    local port_argument="$2" # 可能为空

    # 步骤3: 验证目标IP/主机名
    if ! validate_target "$target_ip"; then
        usage # validate_target 内部不输出，所以这里调用 usage
    fi

    # 步骤4: 执行扫描
    perform_scan "$target_ip" "$port_argument"
}

# --- 脚本执行入口 ---
main "$@"