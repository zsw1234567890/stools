#!/bin/bash

# =============================== #
# 单主机 SSH 快速免密登录设置 (ssh_quick_trust.sh)
# 作者: frogchou (由 Kilo Code 适配到 stools 框架)
# 功能:
#   - 在本机生成 SSH 密钥对 (如果尚不存在)。
#   - 将本机的 SSH 公钥分发到指定的目标主机。
#   - 通过命令行参数接收目标主机 IP/主机名和用户密码。
#
# 使用方式:
#   ssh_quick_trust.sh <target_host> <username> <password>
#   例如: ssh_quick_trust.sh 192.168.1.20 root yourpassword
# =============================== #

# --- 配置 ---
REQUIRED_COMMANDS=("expect" "ssh-keygen" "ssh-copy-id")

# --- 工具函数 ---

# 打印错误信息并退出
error_exit() {
    echo "❌ 错误: $1" >&2
    exit 1
}

# 打印使用说明并退出
usage() {
    echo "❗ 参数错误或缺少参数。"
    echo "✅ 使用示例："
    echo "  $0 <目标主机IP/主机名> <用户名> <密码>"
    echo "  例如: $0 192.168.1.20 root yourpassword"
    exit 1
}

# 检查并安装依赖命令 (与 setup_ssh_trust.sh 中的类似)
_install_pkg_if_missing() {
    local pkg_to_install="$1"
    local cmd_to_check="$2"
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
            return 1
        fi
        if ! command -v "$cmd_to_check" &> /dev/null; then
            return 1
        fi
    fi
    return 0
}

install_dependencies() {
    echo "ℹ️ 正在检查并安装依赖..."
    for cmd_pkg in "expect" "openssh-clients:ssh-keygen" "openssh-clients:ssh-copy-id"; do
        IFS=':' read -r pkg cmd <<< "$cmd_pkg"
        if ! _install_pkg_if_missing "$pkg" "$cmd"; then
            if [[ "$pkg" == "openssh-clients" ]] && ! (_install_pkg_if_missing "ssh-keygen" && _install_pkg_if_missing "ssh-copy-id"); then
                 error_exit "必需命令 '$cmd' (来自 '$pkg' 或类似包) 安装失败。请手动安装。"
            elif [[ "$pkg" != "openssh-clients" ]]; then
                 error_exit "必需命令 '$cmd' (来自 '$pkg' 或类似包) 安装失败。请手动安装。"
            fi
        fi
    done
    # 可选安装 sshpass
    if ! _install_pkg_if_missing "sshpass"; then
        echo "⚠️  可选的 'sshpass' 包安装失败或未找到。ssh-copy-id 可能仍能通过 expect 工作。"
    fi
    echo "✅ 依赖检查完成。"
}

# 生成本机 SSH 密钥对 (如果不存在)
generate_ssh_key() {
    local private_key_path="$HOME/.ssh/id_rsa"
    local public_key_path="$HOME/.ssh/id_rsa.pub"

    if [ -f "$public_key_path" ]; then
        echo "ℹ️  本机 SSH 公钥 '$public_key_path' 已存在。"
    else
        echo "ℹ️  本机 SSH 公钥不存在，正在生成..."
/usr/bin/expect <<EOF
spawn ssh-keygen -t rsa -b 2048
expect {
    "Enter file in which to save the key ($private_key_path):" {
        send "\r"
        exp_continue
    }
    "Overwrite (y/n)?" {
        send "n\r"
        send_user "\n⚠️  私钥已存在但公钥缺失，或 ssh-keygen 行为异常。请手动检查 SSH 密钥。\n"
        exit 1
    }
    "Enter passphrase (empty for no passphrase):" {
        send "\r"
        exp_continue
    }
    "Enter same passphrase again:" {
        send "\r"
    }
}
expect eof
EOF
        if [ -f "$public_key_path" ]; then
            echo "✅ 本机 SSH 密钥对已成功生成。"
        else
            error_exit "本机 SSH 密钥对生成失败。请检查 ssh-keygen 命令的输出或手动生成。"
        fi
    fi
}

# --- 主逻辑 ---
main() {
    if [ "$#" -ne 3 ]; then
        usage
    fi

    local target_host="$1"
    local username="$2"
    local password="$3"

    echo "===== 单主机 SSH 快速互信设置 ====="
    echo "🎯 目标主机: $username@$target_host"

    # 步骤1: 检查并安装依赖
    install_dependencies

    # 步骤2: 生成本机 SSH 密钥对 (如果需要)
    generate_ssh_key

    # 步骤3: 分发公钥到远程主机
    echo "➡️  正在尝试将公钥复制到 $username@$target_host ..."

/usr/bin/expect <<EOF
set timeout 30
spawn ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$username@$target_host"
expect {
    timeout { send_user "❌ ssh-copy-id 到 $target_host 超时。\n"; exit 1 }
    eof { send_user "ℹ️  ssh-copy-id 到 $target_host 可能已完成或遇到问题。\n" }
    "(yes/no)?" {
        send "yes\r"
        expect {
            "*assword:" { send "$password\r" }
            timeout { send_user "❌ 发送 'yes' 后等待密码提示超时 ($target_host)。\n"; exit 1 }
        }
    }
    "*assword:" {
        send "$password\r"
    }
}
expect {
    "Number of key(s) added: 1" {
        send_user "✅ 公钥已成功添加到 $username@$target_host\n"
    }
    "Now try logging into the machine" {
        send_user "✅ 公钥可能已成功添加到 $username@$target_host (请验证)。\n"
    }
    eof {
        # 正常结束
    }
}
catch wait reason
# set exit_status [lindex \$reason 3]
# send_user "ssh-copy-id exit status: \$exit_status\n"
EOF

    if [ $? -eq 0 ]; then # 检查 expect 脚本的退出状态
      echo "✅ 公钥分发尝试完成。请尝试手动 SSH 登录到 $username@$target_host 以验证免密登录。"
    else
      echo "⚠️ 公钥分发过程中可能出现问题。请检查上面的输出。"
    fi
    echo "===== 操作完成 ====="
}

# --- 脚本执行入口 ---
main "$@"