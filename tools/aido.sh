#!/bin/bash

# =============================== #
# AI Linux 命令生成助手 (aido.sh)
# 作者: Kilo Code (基于 frogchou 的 stools 框架)
# 功能:
#   - 接收用户的自然语言需求。
#   - 收集基本的系统信息 (OS, Arch) 以辅助 AI。
#   - 调用 OpenAI API 生成对应的 Linux 命令。
#   - 提供交互式选项，让用户确认后直接执行生成的命令。
#
# 使用方式：
#   aido.sh <你的需求...>
#   echo "查找所有大于100M的日志文件" | aido.sh
# =============================== #

# --- 配置 ---
OPENAI_API_BASE_URL="http://d.frogchou.com/v1"
OPENAI_MODEL="gpt-4o-mini"
REQUIRED_COMMANDS=("curl" "jq")

# --- 工具函数 ---

# 打印错误信息并退出
error_exit() {
    echo "❌ 错误: $1" >&2
    exit 1
}

# 打印使用说明并退出
usage() {
    echo "ℹ️ 用法:"
    echo "  $0 <你的需求...>"
    echo "  echo \"你的需求\" | $0"
    echo ""
    echo "描述:"
    echo "  此脚本将您的需求发送给 AI，以生成一个可执行的 Linux 命令。"
    echo "  AI 生成的命令会显示给您，并询问是否执行。"
    echo "  API 密钥需通过 OPENAI_API_KEY 环境变量设置。"
    exit 1
}

# 检查并安装依赖命令
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
        echo "✅ '$pkg_to_install' 已安装。"
    fi
    return 0
}

install_dependencies() {
    echo "ℹ️ 正在检查并安装依赖..."
    local all_deps_ok=true
    for cmd_pkg_pair in "curl:curl" "jq:jq"; do
        IFS=':' read -r pkg cmd <<< "$cmd_pkg_pair"
        if ! _install_pkg_if_missing "$pkg" "$cmd"; then
            error_exit "必需命令 '$cmd' (来自 '$pkg' 包) 安装失败。请手动安装。"
            all_deps_ok=false
        fi
    done
    if $all_deps_ok; then
        echo "✅ 所有必需依赖已满足。"
    fi
}

# 收集基本的系统信息
get_system_info() {
    local os_name="Unknown"
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        os_name=$(. /etc/os-release; echo "$PRETTY_NAME")
    elif command -v lsb_release &> /dev/null; then
        os_name=$(lsb_release -ds)
    elif [ -f /etc/redhat-release ]; then
        os_name=$(cat /etc/redhat-release)
    fi
    local arch
    arch=$(uname -m)
    echo "OS: $os_name, Architecture: $arch"
}

# 调用 OpenAI API 并处理响应
# 参数:
#   $1: 用户的原始需求
call_openai_api_for_command() {
    local user_prompt="$1"
    local system_info

    system_info=$(get_system_info)

    if [ -z "$OPENAI_API_KEY" ]; then
        error_exit "OPENAI_API_KEY 环境变量未设置。无法调用 OpenAI API。"
    fi

    # 构造系统提示词，指导 AI 的行为
    local system_prompt="You are an expert Linux command-line assistant. Your task is to generate a single, executable shell command based on the user's request.
- ONLY respond with the raw command.
- Do NOT provide any explanation, comments, or surrounding text like 'Here is the command:'.
- Do NOT use placeholders like '<your_file>'. If a placeholder is necessary, use a generic and obvious one like 'path/to/your/file'.
- The user's system information is: ${system_info}. Use this information to generate a compatible command (e.g., use 'apt' for Debian/Ubuntu, 'yum' for CentOS)."

    echo "🧠 正在根据您的需求生成命令... 请稍候..."

    # 构建 JSON payload
    local json_payload
    json_payload=$(jq -nc \
        --arg model "$OPENAI_MODEL" \
        --arg system_prompt "$system_prompt" \
        --arg user_prompt "$user_prompt" \
        '{model: $model, messages: [{"role": "system", "content": $system_prompt}, {"role": "user", "content": $user_prompt}], max_tokens: 200, temperature: 0.2}')

    if [ -z "$json_payload" ]; then
        error_exit "创建 OpenAI JSON payload 失败。"
    fi

    local response
    response=$(curl --connect-timeout 15 --max-time 60 -s -X POST "$OPENAI_API_BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$json_payload")

    local curl_exit_code=$?
    if [ $curl_exit_code -ne 0 ]; then
        error_exit "调用 OpenAI API 失败 (curl 错误码: $curl_exit_code)。"
    fi

    if [ -z "$response" ]; then
        error_exit "OpenAI API 未返回任何响应。"
    fi

    if echo "$response" | jq -e '.error' > /dev/null; then
        local error_message
        error_message=$(echo "$response" | jq -r '.error.message // "未知API错误"')
        error_exit "OpenAI API 返回错误: $error_message"
    fi

    local generated_command
    generated_command=$(echo "$response" | jq -r '.choices[0].message.content // ""' | sed 's/^`//; s/`$//' | sed 's/^```sh//; s/^```bash//; s/^```//; s/```$//' | tr -d '\n')

    if [ -z "$generated_command" ]; then
         echo "⚠️  AI 未能生成任何命令。"
         return 1
    fi
    
    # 显示并请求确认
    echo "💡 AI 生成的命令是:"
    echo "--------------------------------------------------"
    echo -e "\033[1;33m${generated_command}\033[0m" # 黄色高亮显示命令
    echo "--------------------------------------------------"
    
    read -r -p "是否执行此命令? (y/N/e) [y=执行, N=取消, e=编辑]: " choice
    case "$choice" in
        y|Y)
            echo "🚀 正在执行命令..."
            eval "$generated_command"
            ;;
        e|E)
            read -r -e -p "编辑命令: " -i "$generated_command" edited_command
            echo "🚀 正在执行编辑后的命令..."
            eval "$edited_command"
            ;;
        *)
            echo "ℹ️  操作已取消。"
            ;;
    esac
}

# --- 主逻辑 ---
main() {
    install_dependencies

    local user_input=""
    if [ ! -t 0 ]; then
        user_input=$(cat -)
    fi

    local args_content="$*"
    if [ -n "$user_input" ] && [ -n "$args_content" ]; then
        user_input="$args_content"$'\n'"$user_input"
    elif [ -n "$args_content" ]; then
        user_input="$args_content"
    fi

    if [ -z "$user_input" ]; then
        usage
    fi

    call_openai_api_for_command "$user_input"
}

# --- 脚本执行入口 ---
main "$@"