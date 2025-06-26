#!/bin/bash

# =============================== #
# 局域网存活主机扫描脚本
# 兼容性强，自动安装依赖，支持掩码解析
# 使用方式：
# 1. ./lan_ping_scan.sh 192.168.1.0
# 2. ./lan_ping_scan.sh 192.168.0.0 16
# =============================== #

# 自动安装所需命令
install_dependencies() {
    for cmd in ip nmap; do
        if ! command -v $cmd &> /dev/null; then
            echo "缺少命令 [$cmd]，尝试自动安装..."
            if [ -x "$(command -v apt)" ]; then
                sudo apt update && sudo apt install -y $cmd
            elif [ -x "$(command -v yum)" ]; then
                sudo yum install -y $cmd
            elif [ -x "$(command -v dnf)" ]; then
                sudo dnf install -y $cmd
            else
                echo "不支持的包管理器，请手动安装 $cmd"
                exit 1
            fi
        fi
    done
}

# 使用说明
usage() {
    echo "❗ 参数错误"
    echo "✅ 使用示例："
    echo "  $0 192.168.1.0              # 默认使用 /24 掩码"
    echo "  $0 192.168.0.0 16           # 使用自定义掩码"
    exit 1
}

# 判断 IP 地址是否合法
valid_ip() {
    local ip=$1
    local stat=1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && \
           ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# 将掩码数字转为 CIDR 格式
cidr_to_range() {
    local ip=$1
    local maskbits=${2:-24}
    echo "$ip/$maskbits"
}

# 扫描存活主机
scan_alive_hosts() {
    local cidr_range=$1
    echo "🔍 正在扫描局域网: $cidr_range"
    nmap -n -sn --min-parallelism 50 "$cidr_range" | grep "Nmap scan report for" | awk '{print $5}' &
    wait
}

# 主逻辑
main() {
    install_dependencies

    if [[ $# -eq 1 ]]; then
        ip=$1
        mask=24
    elif [[ $# -eq 2 ]]; then
        ip=$1
        mask=$2
    else
        usage
    fi

    if ! valid_ip "$ip"; then
        echo "❌ 输入的 IP 地址 [$ip] 非法"
        usage
    fi

    if ! [[ "$mask" =~ ^[0-9]+$ ]] || [[ $mask -lt 1 || $mask -gt 32 ]]; then
        echo "❌ 输入的掩码 [$mask] 非法，应为1~32之间的整数"
        usage
    fi

    cidr=$(cidr_to_range "$ip" "$mask")
    scan_alive_hosts "$cidr"
}

# 运行主函数
main "$@"
