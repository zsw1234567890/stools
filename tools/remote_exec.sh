#!/bin/bash

# =============================== #
# 远程批量执行与文件传输工具 (remote_exec.sh)
# 作者: frogchou
# 功能:
#   - 从 'hostsinfo' 文件读取目标主机列表 (IP, 用户名, 密码)。
#   - 自动安装 'expect' 依赖。
#   - 批量在目标主机上执行命令。
#   - 批量向目标主机传输文件或目录。
#
# hostsinfo 文件格式 (与脚本在同一目录):
#   <host_ip>   <username>   <password>
#   192.168.1.10 root         yourpassword
#   192.168.1.11 admin        anotherpass
# =============================== #

# --- 配置 ---
HOSTS_INFO_FILE="hostsinfo" # 主机信息文件，应与脚本在同一目录
REQUIRED_COMMANDS=("expect")

# --- 工具函数 ---

# 打印错误信息并退出
error_exit() {
    echo "❌ 错误: $1" >&2
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
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update -qq && sudo apt-get install -y -qq "${missing_deps[@]}"
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y "${missing_deps[@]}"
        elif [ -x "$(command -v dnf)" ]; then
            sudo dnf install -y "${missing_deps[@]}"
        elif [ -x "$(command -v pacman)" ]; then
            sudo pacman -Syu --noconfirm "${missing_deps[@]}"
        elif [ -x "$(command -v zypper)" ]; then
            sudo zypper install -y "${missing_deps[@]}"
        else
            error_exit "无法确定包管理器或自动安装失败。请手动安装: ${missing_deps[*]} 然后重试。"
        fi

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

# 检查 hostsinfo 文件是否存在且可读
check_hostsinfo_file() {
    if [ ! -f "$HOSTS_INFO_FILE" ]; then
        echo "❌ 错误: 主机信息文件 '$HOSTS_INFO_FILE' 不存在于脚本所在目录！" >&2
        echo "   请在脚本同目录下创建 '$HOSTS_INFO_FILE' 文件，内容格式如下 (以空格或制表符分隔):" >&2
        echo "   <host_ip>   <username>   <password>" >&2
        echo "   例如:" >&2
        echo "   192.168.1.10 root         yourpassword" >&2
        echo "   192.168.1.11 user1        complex_!@#" >&2
        exit 1
    fi
    if [ ! -r "$HOSTS_INFO_FILE" ]; then
        error_exit "主机信息文件 '$HOSTS_INFO_FILE' 不可读。"
    fi
}

# 远程执行命令函数
# 参数:
#   $@: 要在远程主机上执行的命令
run_remote_command() {
    local remote_command="$*" # 将所有参数视为一个命令字符串

    if [ -z "$remote_command" ]; then
        echo "ℹ️  未提供任何命令来执行。"
        return
    fi

    echo "批量执行命令: $remote_command"
    echo "-------------------------------------"

    # 读取 hostsinfo 文件并处理每一行
    # 使用 IFS= 防止行首行尾空格被ตัด掉，-r 防止反斜杠转义
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释行 (以 # 开头)
        if [[ -z "$line" || "$line" =~ ^\s*# ]]; then
            continue
        fi

        # 解析主机信息 (IP, 用户, 密码)
        # 假设以空格或制表符分隔
        read -r host_ip username password <<< "$line"
        
        if [ -z "$host_ip" ] || [ -z "$username" ] || [ -z "$password" ]; then
            echo "⚠️  警告: 跳过格式不正确的主机信息行: '$line' (在 '$HOSTS_INFO_FILE' 中)"
            continue
        fi

        echo "➡️  在 $host_ip (用户: $username) 上执行命令..."

/usr/bin/expect <<EOF
set timeout 20 # 设置超时时间，防止永久等待
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$username@$host_ip" "$remote_command"
expect {
    timeout { send_user "❌ SSH 连接到 $host_ip 超时。\n"; exit 1 }
    eof { send_user "ℹ️  SSH 连接到 $host_ip 可能立即关闭或命令无输出。\n" }
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
expect eof
catch wait reason
# exit [lindex \$reason 3] # 返回远程命令的退出状态 (可选)
EOF
        echo "-------------------------------------"
    done < "$HOSTS_INFO_FILE"
}

# 远程传输文件函数
# 参数:
#   $1: 源文件/目录路径
#   $2: 目标路径 (在远程主机上)
run_file_transfer() {
    local source_path="$1"
    local destination_path="$2"

    if [ ! -e "$source_path" ]; then
        error_exit "源文件/目录 '$source_path' 不存在。"
    fi
    if [ -z "$destination_path" ]; then
        error_exit "未指定远程目标路径。"
    fi

    echo "批量传输文件: $source_path -> <host>:$destination_path"
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

        echo "➡️  传输文件到 $host_ip (用户: $username)..."
/usr/bin/expect <<EOF
set timeout 600 # 为文件传输设置更长的超时时间
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r "$source_path" "$username@$host_ip:$destination_path"
expect {
    timeout { send_user "❌ SCP 到 $host_ip 超时。\n"; exit 1 }
    eof { send_user "ℹ️  SCP 到 $host_ip 可能立即关闭。\n" }
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
expect eof
catch wait reason
# exit [lindex \$reason 3]
EOF
        echo "✅ 文件已传输到 $host_ip:$destination_path"
        echo "-------------------------------------"
    done < "$HOSTS_INFO_FILE"
}

# 主交互函数
interactive_main() {
    while true; do
        echo ""
        read -r -p "请选择操作 (1: 执行命令, 2: 传输文件, q: 退出): " choice
        case "$choice" in
            1)
                read -r -p "请输入要在远程主机上执行的命令: " cmd_to_run
                if [ -n "$cmd_to_run" ]; then
                    run_remote_command "$cmd_to_run"
                else
                    echo "ℹ️  未输入命令，操作取消。"
                fi
                ;;
            2)
                read -r -p "请输入源文件或目录的本地路径: " src_path
                if [ ! -e "$src_path" ]; then
                     echo "❌ 源文件/目录 '$src_path' 不存在。请重新输入。"
                     continue
                fi
                read -r -p "请输入远程主机上的目标路径: " dst_path
                if [ -n "$src_path" ] && [ -n "$dst_path" ]; then
                    run_file_transfer "$src_path" "$dst_path"
                else
                    echo "ℹ️  源路径或目标路径未完整输入，操作取消。"
                fi
                ;;
            q|Q)
                echo "👋 退出程序。"
                exit 0
                ;;
            *)
                echo "❌ 无效的选择 '$choice'。请输入 1, 2, 或 q。"
                ;;
        esac
    done
}

# --- 脚本执行入口 ---
# 步骤1: 检查并安装依赖
install_dependencies

# 步骤2: 检查 hostsinfo 文件
check_hostsinfo_file

# 步骤3: 进入交互模式
interactive_main