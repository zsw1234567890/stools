#!/bin/bash

# =============================== #
# 批量建立 SSH 免密登录工具 (setup_ssh_trust.sh)
# 作者: frogchou (由 Kilo Code 适配到 stools 框架)
# 功能:
#   - 在本机生成 SSH 密钥对 (如果尚不存在)。
#   - 从 'hostsinfo' 文件读取目标主机列表 (IP, 用户名, 密码)。
#   - 使用 'ssh-copy-id' 将本机的 SSH 公钥分发到目标主机。
#   - 自动安装 'expect' 和 'sshpass' (ssh-copy-id 可能需要) 依赖。
#
# hostsinfo 文件格式 (与脚本在同一目录):
#   <host_ip>   <username>   <password>
#   192.168.1.10 root         yourpassword
#   192.168.1.11 admin        anotherpass
#
# 注意: 此脚本旨在简化多台新机器的初始信任建立。
#       对于已配置 SSH 密钥的环境，请谨慎使用。
# =============================== #

# --- 配置 ---
HOSTS_INFO_FILE="hostsinfo" # 主机信息文件，应与脚本在同一目录
REQUIRED_COMMANDS=("expect" "ssh-keygen" "ssh-copy-id")
# sshpass 是一些 ssh-copy-id 实现或特定情况下需要的，或者 expect 可以完全处理
# 为了更广泛的兼容性，也加入检查
OPTIONAL_DEPENDENCIES=("sshpass")


# --- 工具函数 ---

# 打印错误信息并退出
error_exit() {
    echo "❌ 错误: $1" >&2
    exit 1
}

# 检查并安装依赖命令
_install_pkg_if_missing() {
    local pkg_to_install="$1"
    local cmd_to_check="$2"
    # 如果 cmd_to_check 为空，则默认为 pkg_to_install
    cmd_to_check="${cmd_to_check:-$pkg_to_install}"

    if ! command -v "$cmd_to_check" &> /dev/null; then
        echo "ℹ️  尝试安装 '$pkg_to_install' (提供 '$cmd_to_check')..."
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg_to_install"
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y "$pkg_to_install"
        elif [ -x "$(command -v dnf)" ]; then
            sudo dnf install -y "$pkg_to_install"
        elif [ -x "$(command -v pacman)" ]; then
            sudo pacman -Syu --noconfirm "$pkg_to_install"
        elif [ -x "$(command -v zypper)" ]; then
            sudo zypper install -y "$pkg_to_install"
        else
            return 1 # 表示安装尝试失败或无法确定包管理器
        fi
        if ! command -v "$cmd_to_check" &> /dev/null; then
            return 1 # 安装后仍未找到
        fi
    fi
    return 0 # 命令已存在或安装成功
}

install_dependencies() {
    echo "ℹ️ 正在检查并安装依赖..."
    local all_ok=true
    for cmd_pkg in "expect" "openssh-clients:ssh-keygen" "openssh-clients:ssh-copy-id"; do
        IFS=':' read -r pkg cmd <<< "$cmd_pkg"
        if ! _install_pkg_if_missing "$pkg" "$cmd"; then
            # 如果 openssh-clients 安装失败，尝试单独的包名（某些系统可能不同）
            if [[ "$pkg" == "openssh-clients" ]] && ! (_install_pkg_if_missing "ssh-keygen" && _install_pkg_if_missing "ssh-copy-id"); then
                 error_exit "必需命令 '$cmd' (来自 '$pkg' 或类似包) 安装失败。请手动安装。"
            elif [[ "$pkg" != "openssh-clients" ]]; then
                 error_exit "必需命令 '$cmd' (来自 '$pkg' 或类似包) 安装失败。请手动安装。"
            fi
        fi
    done
    
    # 安装可选的 sshpass
    if ! _install_pkg_if_missing "sshpass"; then
        echo "⚠️  可选的 'sshpass' 包安装失败或未找到。ssh-copy-id 可能仍能通过 expect 工作，但某些情况下 sshpass 能提供帮助。"
    fi

    echo "✅ 依赖检查完成。"
}


# 检查 hostsinfo 文件是否存在且可读
check_hostsinfo_file() {
    if [ ! -f "$HOSTS_INFO_FILE" ]; then
        echo "❌ 错误: 主机信息文件 '$HOSTS_INFO_FILE' 不存在于脚本所在目录！" >&2
        echo "   请在脚本同目录下创建 '$HOSTS_INFO_FILE' 文件，内容格式如下 (以空格或制表符分隔):" >&2
        echo "   <host_ip>   <username>   <password>" >&2
        exit 1
    fi
    if [ ! -r "$HOSTS_INFO_FILE" ]; then
        error_exit "主机信息文件 '$HOSTS_INFO_FILE' 不可读。"
    fi
}

# 生成本机 SSH 密钥对 (如果不存在)
generate_ssh_key() {
    local private_key_path="$HOME/.ssh/id_rsa"
    local public_key_path="$HOME/.ssh/id_rsa.pub"

    if [ -f "$public_key_path" ]; then
        echo "ℹ️  SSH 公钥 '$public_key_path' 已存在。"
    else
        echo "ℹ️  SSH 公钥不存在，正在生成..."
        # 使用 expect 自动处理 ssh-keygen 的提示
/usr/bin/expect <<EOF
spawn ssh-keygen -t rsa -b 2048
expect {
    "Enter file in which to save the key ($private_key_path):" {
        send "\r" ;# 使用默认路径
        exp_continue
    }
    "Overwrite (y/n)?" {
        send "n\r" ;# 如果已存在私钥但无公钥（不太可能），则不覆盖
        send_user "\n⚠️  私钥已存在但公钥缺失，或 ssh-keygen 行为异常。请手动检查 SSH 密钥。\n"
        exit 1
    }
    "Enter passphrase (empty for no passphrase):" {
        send "\r" ;# 无密码短语
        exp_continue
    }
    "Enter same passphrase again:" {
        send "\r" ;# 再次确认无密码短语
    }
}
expect eof
EOF
        if [ -f "$public_key_path" ]; then
            echo "✅ SSH 密钥对已成功生成。"
        else
            error_exit "SSH 密钥对生成失败。请检查 ssh-keygen 命令的输出或手动生成。"
        fi
    fi
}

# 将本机公钥分发到远程主机
distribute_ssh_keys() {
    echo "ℹ️  开始将本机 SSH 公钥分发到远程主机..."
    echo "-------------------------------------"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" || "$line" =~ ^\s*# ]]; then
            continue
        fi
        read -r host_ip username password <<< "$line"

        if [ -z "$host_ip" ] || [ -z "$username" ] || [ -z "$password" ]; then
            echo "⚠️  警告: 跳过格式不正确的主机信息行: '$line' (在 '$HOSTS_INFO_FILE' 中)"
            continue
        fi

        echo "➡️  正在尝试将公钥复制到 $username@$host_ip ..."

# 使用 expect 来处理 ssh-copy-id 的提示
/usr/bin/expect <<EOF
set timeout 30 ; # 设置超时
spawn ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$username@$host_ip"
expect {
    timeout { send_user "❌ ssh-copy-id 到 $host_ip 超时。\n"; exit 1 }
    eof { send_user "ℹ️  ssh-copy-id 到 $host_ip 可能已完成或遇到问题。\n" }
    "(yes/no)?" {
        send "yes\r"
        expect {
            "*assword:" { send "$password\r" }
            timeout { send_user "❌ 发送 'yes' 后等待密码提示超时 ($host_ip)。\n"; exit 1 }
        }
    }
    "*assword:" {
        send "$password\r"
    }
}
# 等待 ssh-copy-id 完成
expect {
    "Number of key(s) added: 1" {
        send_user "✅ 公钥已成功添加到 $username@$host_ip\n"
    }
    "Now try logging into the machine" {
        send_user "✅ 公钥可能已成功添加到 $username@$host_ip (请验证)。\n"
    }
    eof {
        # 捕获 ssh-copy-id 的退出状态可能比较复杂，因为它可能通过 expect 脚本的 eof 退出
        # 这里简单地假设如果 expect 块没有因错误退出，则操作可能成功或部分成功
        # 可以在这里添加更复杂的退出码检查，或者依赖 ssh-copy-id 本身的输出
    }
}
catch wait reason
# 如果需要，可以检查 reason 来判断 ssh-copy-id 的真实退出状态
# set exit_status [lindex \$reason 3]
# send_user "ssh-copy-id exit status: \$exit_status\n"
EOF
        echo "-------------------------------------"
    done < "$HOSTS_INFO_FILE"
    echo "✅ 所有主机的公钥分发尝试完成。"
    echo "ℹ️  请尝试手动 SSH 登录到目标主机以验证免密登录是否生效。"
}

# --- 脚本执行入口 ---
echo "===== SSH 批量互信设置工具 ====="
# 步骤1: 检查并安装依赖
install_dependencies

# 步骤2: 检查 hostsinfo 文件
check_hostsinfo_file

# 步骤3: 生成本机 SSH 密钥对 (如果需要)
generate_ssh_key

# 步骤4: 分发公钥到远程主机
distribute_ssh_keys

echo "===== 操作完成 ====="