#!/bin/bash
#
# sys_info.sh
# 作用：输出当前 Linux 系统的详细信息，包括发行版、内核、资源使用率等。
# 兼容性强，自动检测系统类型并自动安装缺失命令。
# 使用方法：
#   bash sys_info.sh
#
# 参数校验：不接受参数，若有参数则提示错误并给出示例。
#
# 作者：AI 运维助手
# 更新时间：2025-07-02

# ===================== 参数校验 =====================
if [ "$#" -ne 0 ]; then
  echo "参数错误！本脚本不接受任何参数。"
  echo "用法示例："
  echo "  bash sys_info.sh"
  exit 1
fi

# ===================== 工具函数 =====================
# 检查命令是否存在，不存在则自动安装
check_and_install() {
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "检测到缺少命令：$cmd，正在尝试自动安装..."
    if [ "$PKG_MGR" = "apt" ]; then
      sudo apt-get update && sudo apt-get install -y "$pkg"
    elif [ "$PKG_MGR" = "yum" ]; then
      sudo yum install -y "$pkg"
    elif [ "$PKG_MGR" = "dnf" ]; then
      sudo dnf install -y "$pkg"
    elif [ "$PKG_MGR" = "zypper" ]; then
      sudo zypper install -y "$pkg"
    elif [ "$PKG_MGR" = "apk" ]; then
      sudo apk add "$pkg"
    else
      echo "未知的包管理器，无法自动安装 $cmd，请手动安装后重试。"
      exit 2
    fi
  fi
}

# ===================== 检测系统类型 =====================
# 默认包管理器
PKG_MGR=""

if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="$ID"
  OS_NAME="$NAME"
  OS_VERSION="$VERSION"
  case "$ID" in
    ubuntu|debian|deepin|kali)
      PKG_MGR="apt"
      ;;
    centos|rhel)
      PKG_MGR="yum"
      ;;
    fedora)
      PKG_MGR="dnf"
      ;;
    opensuse*|sles)
      PKG_MGR="zypper"
      ;;
    alpine)
      PKG_MGR="apk"
      ;;
    *)
      # 尝试检测常见包管理器
      if command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
      elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
      elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
      elif command -v zypper >/dev/null 2>&1; then
        PKG_MGR="zypper"
      elif command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
      else
        echo "无法识别的 Linux 发行版，且未检测到常见包管理器。"
        exit 3
      fi
      ;;
  esac
else
  echo "无法检测到 /etc/os-release，无法识别系统类型。"
  exit 4
fi

# ===================== 检查并安装依赖命令 =====================
# 依赖命令及其包名（不同系统可能包名不同，已做兼容）
check_and_install "lsb_release" "lsb-release"
check_and_install "uname" "coreutils"
check_and_install "free" "procps"
check_and_install "df" "coreutils"
check_and_install "top" "procps"
check_and_install "vmstat" "procps"
check_and_install "ip" "iproute2"
check_and_install "uptime" "procps"
check_and_install "awk" "gawk"
check_and_install "grep" "grep"
check_and_install "sed" "sed"

# ===================== 输出系统信息 =====================
echo "==================== 系统基本信息 ===================="
echo "发行版名称: $OS_NAME"
echo "发行版ID: $OS_ID"
echo "发行版版本: $OS_VERSION"
echo "内核信息: $(uname -a)"
echo "主机名: $(hostname)"
echo "系统启动时间: $(uptime -s 2>/dev/null || who -b | awk '{print $3,$4}')"
echo

echo "==================== CPU 信息 ===================="
lscpu 2>/dev/null | grep -E 'Model name|Socket|Thread|Core|CPU\(s\)|MHz|Architecture' || cat /proc/cpuinfo | grep -E 'model name|processor|cpu cores|siblings|MHz|arch'
echo

echo "==================== 内存使用情况 ===================="
free -h
echo

echo "==================== 磁盘使用情况 ===================="
df -hT --total | grep -v tmpfs
echo

echo "==================== 网络信息 ===================="
ip addr show | awk '/inet /{print $2, $NF}' | grep -v '127.0.0.1'
echo

echo "==================== 负载与运行时间 ===================="
uptime
echo

echo "==================== 进程与资源占用前5 ===================="
echo "CPU占用前5："
top -b -n 1 | head -12 | tail -5
echo
echo "内存占用前5："
top -b -n 1 | head -17 | tail -5
echo

echo "==================== 结束 ===================="
echo "如需修改脚本内容，请参考每一部分的详细注释。"