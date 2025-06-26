#!/bin/bash

# =============================== #
# 智能抓包与分析工具 (smart_capture.sh)
# 作者: frogchou
# 功能:
#   - 列出可用的网络接口。
#   - 使用 tcpdump 捕获网络流量并保存到 pcap 文件。
#   - (可选) 调用 OpenAI API 对捕获的数据进行智能分析。
#
# 使用方式：
#   smart_capture.sh list-interfaces
#   smart_capture.sh capture <interface> <output.pcap> [-c count | -G seconds] [--analyze] [tcpdump_filter_expression]
#   smart_capture.sh analyze <input.pcap>
# =============================== #

# --- 配置 ---
REQUIRED_COMMANDS=("tcpdump" "curl" "jq")
OPTIONAL_COMMANDS=("tshark") # tshark (Wireshark CLI) 可以提供更详细的 pcap 解析
OPENAI_API_BASE_URL="http://d.frogchou.com/v1"
OPENAI_MODEL="gpt-4o-mini"

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
    echo "ℹ️ 用法: $0 <command> [options]"
    echo ""
    echo "命令:"
    echo "  list-interfaces                            列出所有可用的网络接口。"
    echo "  capture <interface> <output.pcap> [opts]   捕获网络流量。"
    echo "    <interface>: 要抓包的网络接口 (例如 eth0, any)。"
    echo "    <output.pcap>: 保存抓包数据的文件名。"
    echo "    [opts]:"
    echo "      -c <count>          : 捕获指定数量的数据包后停止。"
    echo "      -G <seconds>        : 每隔指定秒数转储到一个新文件 (与 -W 配合使用，此处简化为达到秒数后停止)。"
    echo "                            注意: tcpdump 的 -G 行为复杂，此处简化为抓包持续时间。"
    echo "      --analyze           : 抓包结束后自动调用 OpenAI 进行分析 (需要 OPENAI_API_KEY 环境变量)。"
    echo "      [filter_expression] : (可选) tcpdump 的 BPF 过滤表达式 (例如 'port 80')。"
    echo "                          必须放在其他选项之后。"
    echo "  analyze <input.pcap>                       分析指定的 pcap 文件 (需要 OPENAI_API_KEY 环境变量)。"
    echo ""
    echo "示例:"
    echo "  $0 list-interfaces"
    echo "  $0 capture eth0 capture.pcap -c 100 --analyze"
    echo "  $0 capture any mytraffic.pcap -G 60 'host 1.1.1.1 and port 53'"
    echo "  $0 analyze existing_capture.pcap"
    exit 1
}

# 检查并安装依赖命令
# 参数:
#   $1: "required" 或 "optional"
#   $@: 命令列表 (从第二个参数开始)
_install_commands_if_missing() {
    local type="$1"
    shift
    local cmds_to_check=("$@")
    local missing_cmds=()
    local cmd_found_on_system

    for cmd in "${cmds_to_check[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
        fi
    done

    if [ ${#missing_cmds[@]} -ne 0 ]; then
        echo "---"
        if [ "$type" == "required" ]; then
            echo "⚠️  检测到以下必需命令缺失: ${missing_cmds[*]}"
            echo "ℹ️  尝试自动安装..."
        elif [ "$type" == "optional" ]; then
            echo "ℹ️  可选增强命令缺失: ${missing_cmds[*]}"
            echo "   如果需要更详细的本地 pcap 解析功能，建议安装它们。"
            echo "ℹ️  尝试自动安装 (可选)..."
        fi

        # 尝试使用常见的包管理器安装
        # (省略了所有包管理器的具体实现，实际脚本中应包含)
        local installed_one=false
        if [ -x "$(command -v apt-get)" ]; then
            echo "   (使用 apt-get)"
            sudo apt-get update -qq && sudo apt-get install -y -qq "${missing_cmds[@]}" && installed_one=true
        elif [ -x "$(command -v yum)" ]; then
            echo "   (使用 yum)"
            sudo yum install -y "${missing_cmds[@]}" && installed_one=true
        elif [ -x "$(command -v dnf)" ]; then
            echo "   (使用 dnf)"
            sudo dnf install -y "${missing_cmds[@]}" && installed_one=true
        elif [ -x "$(command -v pacman)" ]; then
            echo "   (使用 pacman)"
            sudo pacman -Syu --noconfirm "${missing_cmds[@]}" && installed_one=true
        elif [ -x "$(command -v zypper)" ]; then
            echo "   (使用 zypper)"
            sudo zypper install -y "${missing_cmds[@]}" && installed_one=true
        else
            if [ "$type" == "required" ]; then
                echo "❌ 无法确定包管理器或自动安装失败。"
            else
                echo "ℹ️  无法确定包管理器，跳过可选组件的自动安装。"
            fi
        fi

        # 再次检查依赖是否安装成功
        local still_missing_after_install=()
        for cmd in "${missing_cmds[@]}"; do
            if ! command -v "$cmd" &> /dev/null; then
                still_missing_after_install+=("$cmd")
            fi
        done
        
        if [ ${#still_missing_after_install[@]} -ne 0 ]; then
            if [ "$type" == "required" ]; then
                error_exit "必需命令 ${still_missing_after_install[*]} 安装后仍未找到。请手动安装后重试。"
            else
                echo "   部分可选命令 ${still_missing_after_install[*]} 未能自动安装。您可以尝试手动安装。"
            fi
        else
             if [ "$installed_one" = true ] || [ ${#missing_cmds[@]} -gt 0 ]; then # 只有当尝试过安装或确实有缺失时才显示
                echo "✅ 依赖检查完成 (部分或全部已安装/已存在)。"
             fi
        fi
        echo "---"
    fi
}

install_dependencies() {
    echo "ℹ️ 正在检查依赖命令..."
    _install_commands_if_missing "required" "${REQUIRED_COMMANDS[@]}"
    _install_commands_if_missing "optional" "${OPTIONAL_COMMANDS[@]}"
    echo "✅ 所有必需依赖已满足。"
}

# --- 功能函数 ---

list_interfaces_func() {
    echo "🔎 可用的网络接口:"
    if command -v tcpdump &> /dev/null; then
        tcpdump -D
    elif command -v ip &> /dev/null; then
        ip -br link | awk '{print NR". "$1}' | sed 's/@.*//' # 简化输出
    else
        echo "   无法找到 tcpdump 或 ip 命令来列出接口。"
    fi
}

call_openai_api() {
    local prompt_text="$1"
    local pcap_filename="$2" # 用于在错误消息中引用

    if [ -z "$OPENAI_API_KEY" ]; then
        error_exit "OPENAI_API_KEY 环境变量未设置。无法调用 OpenAI API。"
    fi

    echo "🧠 正在准备调用 OpenAI API 进行分析 ($OPENAI_MODEL)..."

    # 构建 JSON payload
    # 注意：jq 的 -c (compact) 和 -R (raw input) 以及 -s (slurp) 组合用于正确编码字符串到 JSON 值
    local json_payload
    json_payload=$(jq -nc --arg model "$OPENAI_MODEL" --arg prompt_content "$prompt_text" \
        '{model: $model, messages: [{role: "user", content: $prompt_content}], max_tokens: 1000, temperature: 0.5}')

    if [ -z "$json_payload" ]; then
        error_exit "创建 OpenAI JSON payload 失败。"
    fi
    
    # echo "Debug: JSON Payload: $json_payload" # 用于调试

    local response
    response=$(curl -s -X POST "$OPENAI_API_BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$json_payload")

    local curl_exit_code=$?
    if [ $curl_exit_code -ne 0 ]; then
        error_exit "调用 OpenAI API 失败 (curl 错误码: $curl_exit_code)。请检查网络连接和 API 端点 ($OPENAI_API_BASE_URL)。"
    fi

    if [ -z "$response" ]; then
        error_exit "OpenAI API 未返回任何响应。请检查 API 密钥和端点。"
    fi

    # echo "Debug: Raw API Response: $response" # 用于调试

    # 检查 API 是否返回了错误
    if echo "$response" | jq -e '.error' > /dev/null; then
        local error_message
        error_message=$(echo "$response" | jq -r '.error.message // "未知API错误"')
        error_exit "OpenAI API 返回错误: $error_message (文件: $pcap_filename)"
    fi

    # 提取并显示分析结果
    local analysis_result
    analysis_result=$(echo "$response" | jq -r '.choices[0].message.content // "未能提取分析结果。"')

    if [ -z "$analysis_result" ] || [ "$analysis_result" == "未能提取分析结果。" ]; then
         echo "⚠️  未能从API响应中提取有效的分析结果。"
         echo "   原始响应: $response"
         return 1
    fi
    
    echo "💡 OpenAI 分析结果:"
    echo "--------------------------------------------------"
    echo -e "$analysis_result" # 使用 -e 来解释转义字符，如 \n
    echo "--------------------------------------------------"
    return 0
}

analyze_pcap_func() {
    local pcap_file="$1"

    if [ ! -f "$pcap_file" ]; then
        error_exit "指定的 pcap 文件 '$pcap_file' 不存在。"
    fi

    echo "📊 准备分析 pcap 文件: $pcap_file"
    local summary_for_ai="捕获文件 '$pcap_file' 的网络流量分析请求。\n"
    local pcap_text_summary=""

    if command -v tshark &> /dev/null; then
        echo "ℹ️ 使用 tshark 生成 pcap 文件摘要..."
        # 提取一些基本统计信息和前N条对话的摘要
        # -nr: 不解析名称，读取文件
        # -q: quiet，只打印摘要
        # -z io,phs: 协议分层统计
        # -z conv,tcp: TCP 对话统计
        # -c 20: 只处理前20个包用于快速文本输出 (可选，避免过长)
        # tshark -nr "$pcap_file" -q -z io,phs -z conv,tcp -c 20 2>/dev/null
        # 上述命令输出可能过于结构化，尝试更通用的文本输出
        pcap_text_summary=$(tshark -nr "$pcap_file" -Tfields -e frame.number -e frame.time_relative -e ip.src -e ip.dst -e tcp.srcport -e tcp.dstport -e udp.srcport -e udp.dstport -e dns.qry.name -e http.request.method -e http.host -e _ws.col.Protocol -e _ws.col.Info -Eheader=y -Eseparator=, -c 50 2>/dev/null)
        
        if [ -n "$pcap_text_summary" ]; then
            summary_for_ai+="以下是使用 tshark 从 pcap 文件中提取的前50个数据包的摘要信息 (CSV格式):\n${pcap_text_summary}\n\n"
            summary_for_ai+="请基于以上摘要信息，分析此网络流量中可能存在的关键活动、潜在问题或有趣的模式。重点关注常见的网络协议如HTTP, DNS, TCP等。分析应包括：\n1. 主要通信方和协议。\n2. 是否有异常连接或错误？\n3. 是否有可疑的DNS查询或HTTP请求？\n4. 流量的总体特征是什么？\n请以简洁、易懂的方式总结。"
        else
            echo "⚠️ 未能使用 tshark 生成详细摘要。将提供基本文件信息。"
            summary_for_ai+="无法使用 tshark 生成详细摘要。这是一个名为 '$pcap_file' 的网络抓包文件。请根据通用网络知识，推测此文件中可能包含哪些类型的流量，并给出一些常见的分析方向或建议。"
        fi
    else
        echo "⚠️ tshark 命令未找到。AI 分析将基于有限信息。"
        summary_for_ai+="tshark 命令未安装。这是一个名为 '$pcap_file' 的网络抓包文件。请根据通用网络知识，推测此文件中可能包含哪些类型的流量，并给出一些常见的分析方向或建议，例如用户可以如何使用 Wireshark 或其他工具手动分析此文件。"
    fi
    
    # 调用 OpenAI API
    call_openai_api "$summary_for_ai" "$pcap_file"
}

capture_func() {
    local interface=""
    local output_file=""
    local count_packets=""
    local duration_seconds=""
    local analyze_flag=false
    local filter_expression=""
    local tcpdump_extra_args=() # Store -c or -G related args

    # 解析参数
    if [ $# -lt 2 ]; then
        echo "❌ capture: 缺少接口和输出文件名参数。"
        usage
    fi
    interface="$1"
    output_file="$2"
    shift 2 # 移除了接口和文件名

    # 解析可选参数
    while [ $# -gt 0 ]; do
        case "$1" in
            -c)
                if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    count_packets="$2"
                    tcpdump_extra_args+=("-c" "$count_packets")
                    shift 2
                else
                    error_exit "capture: -c 选项需要一个有效的数字参数。"
                fi
                ;;
            -G)
                if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    duration_seconds="$2"
                    # tcpdump -G is for file rotation, using timeout for simple duration control
                    shift 2
                else
                    error_exit "capture: -G 选项需要一个有效的数字参数 (秒)。"
                fi
                ;;
            --analyze)
                analyze_flag=true
                shift
                ;;
            *)
                # 剩余的参数都作为 BPF 过滤表达式
                filter_expression="$*"
                break # 过滤器表达式是最后一个参数
                ;;
        esac
    done

    if [ -z "$interface" ]; then error_exit "capture: 未指定网络接口。"; fi
    if [ -z "$output_file" ]; then error_exit "capture: 未指定输出 pcap 文件名。"; fi

    # 检查 tcpdump 是否可用
    if ! command -v tcpdump &> /dev/null; then
        error_exit "tcpdump 命令未找到。请先安装。"
    fi

    # 构造 tcpdump 命令
    local cmd_prefix_parts=() # 用于构建 timeout 命令前缀
    local tcpdump_cmd=("tcpdump" "-i" "$interface" "-w" "$output_file")
    
    if [ -n "$duration_seconds" ]; then
        if ! command -v timeout &> /dev/null; then
            error_exit "timeout 命令未找到，无法使用 -G <seconds> 选项。请安装 coreutils 包。"
        fi
        cmd_prefix_parts+=("timeout" "$duration_seconds")
        echo "ℹ️ 将抓包 $duration_seconds 秒..."
    elif [ -n "$count_packets" ]; then
        tcpdump_cmd+=("${tcpdump_extra_args[@]}") # 包含 -c <count>
        echo "ℹ️ 将抓包 $count_packets 个数据包..."
    else
        echo "ℹ️ 未指定抓包数量或时长，将持续抓包直到手动停止 (Ctrl+C)。"
    fi

    if [ -n "$filter_expression" ]; then
        # 将过滤器表达式的每个部分作为单独的参数传递，以处理带空格的过滤器
        read -r -a filter_array <<< "$filter_expression"
        tcpdump_cmd+=("${filter_array[@]}")
        echo "ℹ️ 使用过滤器: $filter_expression"
    fi

    echo "🚀 开始抓包到 $output_file ... (按 Ctrl+C 停止，除非指定了 -c 或 -G)"
    
    local full_command_str=""
    # tcpdump 通常需要 root 权限
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo &> /dev/null; then
            error_exit "sudo 命令未找到，无法以非 root 用户执行 tcpdump。请使用 root 用户或安装 sudo。"
        fi
        cmd_prefix_parts+=("sudo")
    fi
    
    # 将命令前缀部分和 tcpdump 命令组合
    full_command_str="${cmd_prefix_parts[*]} ${tcpdump_cmd[*]}"
    echo "   执行命令: $full_command_str"

    # 执行抓包
    # 使用 eval 来正确处理包含空格和引号的过滤器表达式以及命令前缀
    if eval "$full_command_str"; then
        echo "✅ 抓包完成，数据已保存到 $output_file"
        if $analyze_flag; then
            if [ -f "$output_file" ]; then
                echo "---"
                analyze_pcap_func "$output_file" # 调用分析函数
            else
                echo "⚠️  抓包似乎已完成，但输出文件 $output_file 未找到，无法进行分析。"
            fi
        fi
    else
        local exit_code=$?
        # 检查是否是 timeout 命令导致的退出 (通常是 124)
        is_timeout_exit=false
        for part in "${cmd_prefix_parts[@]}"; do
            if [[ "$part" == "timeout" ]]; then
                is_timeout_exit=true
                break
            fi
        done

        if $is_timeout_exit && [ $exit_code -eq 124 ]; then
             echo "✅ 抓包已达到指定时长，数据已保存到 $output_file"
             if $analyze_flag; then
                if [ -f "$output_file" ]; then
                    echo "---"
                    analyze_pcap_func "$output_file"
                else
                    echo "⚠️  抓包似乎已完成，但输出文件 $output_file 未找到，无法进行分析。"
                fi
             fi
        else
            echo "❌ 抓包失败或被中断。退出码: $exit_code"
        fi
    fi
}

# --- 主逻辑 ---
main() {
    # 预检查：确保至少有一个命令参数
    if [ $# -eq 0 ]; then
        usage
    fi

    local command="$1"
    shift # 移除命令参数，剩下的是该命令的参数

    # 安装依赖 (每次运行时都检查，确保环境就绪)
    install_dependencies

    case "$command" in
        list-interfaces)
            list_interfaces_func
            ;;
        capture)
            capture_func "$@"
            ;;
        analyze)
            analyze_pcap_func "$@"
            ;;
        *)
            echo "❌ 未知命令: $command"
            usage
            ;;
    esac
}

# --- 脚本执行入口 ---
main "$@"