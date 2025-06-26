#!/bin/bash

# =============================== #
# AI 助手 (ai_assistant.sh)
# 作者: Kilo Code (基于 frogchou 的 stools 框架)
# 功能:
#   - 接收用户通过命令行参数或管道输入的提示词。
#   - 调用 OpenAI API (gpt-4o-mini) 获取回答。
#   - 以友好方式展示结果。
#
# 使用方式：
#   ai_assistant.sh <你的问题或提示词...>
#   echo "你的问题" | ai_assistant.sh
#   cat my_prompt.txt | ai_assistant.sh
#   ls -l | ai_assistant.sh "请总结这个目录列表"
# =============================== #

# --- 配置 ---
OPENAI_API_BASE_URL="http://d.frogchou.com/v1"
OPENAI_MODEL="gpt-4o-mini" # 使用 gpt-4o-mini 模型
REQUIRED_COMMANDS=("curl" "jq")

# --- 工具函数 ---

# 打印错误信息并退出
# 参数:
#   $1: 错误信息字符串
error_exit() {
    echo "❌ 错误: $1" >&2
    exit 1
}

# 打印使用说明并退出
usage() {
    echo "ℹ️ 用法:"
    echo "  $0 <你的问题或提示词...>"
    echo "  echo \"你的问题\" | $0"
    echo "  cat prompt_file.txt | $0"
    echo ""
    echo "描述:"
    echo "  此脚本将您提供的文本作为提示词发送给 OpenAI API ($OPENAI_MODEL 模型)，"
    echo "  并显示 AI 的回答。API 密钥需通过 OPENAI_API_KEY 环境变量设置。"
    echo "  API 端点: $OPENAI_API_BASE_URL"
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
            return 1 # 表示安装尝试失败或无法确定包管理器
        fi
        if ! command -v "$cmd_to_check" &> /dev/null; then
            return 1 # 安装后仍未找到
        fi
        echo "✅ '$pkg_to_install' 已安装。"
    fi
    return 0 # 命令已存在或安装成功
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

# 调用 OpenAI API 并处理响应
# 参数:
#   $1: 要发送给 AI 的完整提示文本
call_openai_api_for_text_prompt() {
    local prompt_text="$1"

    if [ -z "$OPENAI_API_KEY" ]; then
        error_exit "OPENAI_API_KEY 环境变量未设置。无法调用 OpenAI API。"
    fi

    echo "🧠 正在处理您的请求并调用 OpenAI API ($OPENAI_MODEL)... 请稍候..."

    # 构建 JSON payload
    local json_payload
    # 使用 jq 的 --argjson 来处理 messages 数组，确保 content 是一个正确的 JSON 字符串
    json_payload=$(jq -nc \
        --arg model "$OPENAI_MODEL" \
        --arg prompt_content "$prompt_text" \
        '{model: $model, messages: [{"role": "user", "content": $prompt_content}], max_tokens: 1500, temperature: 0.7}')
        # 增加了 max_tokens 和调整了 temperature

    if [ -z "$json_payload" ]; then
        error_exit "创建 OpenAI JSON payload 失败。"
    fi
    
    # echo "Debug: JSON Payload: $json_payload" # 用于调试

    local response
    # 添加 --connect-timeout 和 --max-time 来控制 curl 的超时
    response=$(curl --connect-timeout 10 --max-time 120 -s -X POST "$OPENAI_API_BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$json_payload")

    local curl_exit_code=$?
    if [ $curl_exit_code -ne 0 ]; then
        error_exit "调用 OpenAI API 失败 (curl 错误码: $curl_exit_code)。请检查网络连接、API 端点 ($OPENAI_API_BASE_URL) 和 API 密钥。"
    fi

    if [ -z "$response" ]; then
        error_exit "OpenAI API 未返回任何响应。请检查 API 密钥、端点或网络。"
    fi

    # echo "Debug: Raw API Response: $response" # 用于调试

    # 检查 API 是否返回了错误
    if echo "$response" | jq -e '.error' > /dev/null; then
        local error_message
        error_message=$(echo "$response" | jq -r '.error.message // "未知API错误"')
        error_exit "OpenAI API 返回错误: $error_message"
    fi

    # 提取并显示分析结果
    local ai_answer
    ai_answer=$(echo "$response" | jq -r '.choices[0].message.content // ""')

    if [ -z "$ai_answer" ]; then
         echo "⚠️  未能从API响应中提取有效的回答，或者AI返回了空内容。"
         echo "   原始响应 (部分): $(echo "$response" | jq -c . | cut -c 1-200)..." # 显示部分原始响应以便调试
         return 1
    fi
    
    echo "💡 AI 回答:"
    echo "--------------------------------------------------"
    echo -e "$ai_answer" # 使用 -e 来解释转义字符，如 \n
    echo "--------------------------------------------------"
    return 0
}

# --- 主逻辑 ---
main() {
    # 步骤1: 检查并安装依赖
    install_dependencies

    local prompt_input=""

    # 步骤2: 获取用户输入 (命令行参数或管道)
    if [ "$#" -gt 0 ]; then
        # 从命令行参数获取输入
        prompt_input="$*" # 将所有参数合并为一个字符串
    elif [ -p /dev/stdin ]; then
        # 从管道获取输入
        prompt_input=$(cat -)
    else
        # 没有参数也没有管道输入，显示用法
        usage
    fi

    # 检查输入是否为空
    if [ -z "$prompt_input" ]; then
        echo "ℹ️ 未提供任何提示词。"
        usage
    fi

    # 步骤3: 调用 OpenAI API
    call_openai_api_for_text_prompt "$prompt_input"
}

# --- 脚本执行入口 ---
main "$@"