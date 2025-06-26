#!/bin/bash
# install.sh - stools 安装脚本，用于一键部署 stl 命令

INSTALL_DIR="/opt/stools"
BIN_DIR="/usr/local/bin"
STL_CMD="$BIN_DIR/stl"
CONFIG_FILE="$HOME/.stoolsrc"
REQUIRED_CMDS=("curl" "jq")

# 检查管理员权限
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 用户或 sudo 执行安装命令。"
    exit 1
  fi
}

# 检查并安装依赖
check_and_install_dependencies() {
  echo "ℹ️ 正在检查依赖命令..."
  local missing_deps=()
  for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  if [ ${#missing_deps[@]} -ne 0 ]; then
    echo "⚠️ 检测到以下依赖缺失：${missing_deps[*]}"
    echo "ℹ️ 尝试自动安装..."
    if [ -x "$(command -v apt-get)" ]; then
      sudo apt-get update
      sudo apt-get install -y "${missing_deps[@]}"
    elif [ -x "$(command -v yum)" ]; then
      sudo yum install -y "${missing_deps[@]}"
    elif [ -x "$(command -v dnf)" ]; then
      sudo dnf install -y "${missing_deps[@]}"
    else
      echo "❌ 无法自动安装依赖。请手动安装: ${missing_deps[*]} 然后重试。"
      exit 1
    fi
    # 再次检查是否安装成功
    for cmd in "${missing_deps[@]}"; do
      if ! command -v "$cmd" &> /dev/null; then
        echo "❌ 依赖 $cmd 安装失败。请手动安装后重试。"
        exit 1
      fi
    done
    echo "✅ 依赖已成功安装。"
  else
    echo "✅ 所有依赖已满足。"
  fi
}

# 检查冲突
check_conflicts() {
  echo "ℹ️ 正在检查冲突..."
  # 检查 stl 命令是否冲突
  if [ -e "$STL_CMD" ]; then
    # 如果存在，检查它是否是指向我们期望安装位置的软链接
    if [ -L "$STL_CMD" ] && [ "$(readlink -f "$STL_CMD")" == "$INSTALL_DIR/stl" ]; then
      echo "ℹ️ stl 命令已存在，并且是指向 $INSTALL_DIR/stl 的正确软链接。将覆盖安装。"
    else
      echo "❌ 命令 $STL_CMD 已存在且与 stools 冲突。请先卸载或移除冲突命令。"
      exit 1
    fi
  fi

  # 检查安装目录是否冲突
  if [ -d "$INSTALL_DIR" ]; then
    # 检查目录是否为空，除了可能的 . ..
    if [ -n "$(ls -A "$INSTALL_DIR")" ]; then
        # 进一步检查是否是我们自己的文件，如果是，则允许覆盖
        if [ -f "$INSTALL_DIR/stl" ] || [ -d "$INSTALL_DIR/tools" ] || [ -d "$INSTALL_DIR/meta" ]; then
            echo "ℹ️ 安装目录 $INSTALL_DIR 已存在 stools 文件，将进行覆盖安装。"
        else
            echo "❌ 安装目录 $INSTALL_DIR 已存在且包含其他文件。请先备份或清空该目录。"
            exit 1
        fi
    fi
  fi
  echo "✅ 未检测到冲突。"
}

# 主安装逻辑
main_install() {
  echo "ℹ️ 开始安装 stools..."

  # 创建目录结构
  echo "创建目录 $INSTALL_DIR/tools 和 $INSTALL_DIR/meta ..."
  mkdir -p "$INSTALL_DIR/tools"
  mkdir -p "$INSTALL_DIR/meta"

  # 下载 stl 主命令脚本
  echo "下载 stl 主命令脚本到 $INSTALL_DIR/stl ..."
  if curl -fsSL "https://raw.githubusercontent.com/frogchou/stools/main/stl" -o "$INSTALL_DIR/stl"; then
    chmod +x "$INSTALL_DIR/stl"
    echo "✅ stl 主命令脚本下载并设置权限成功。"
  else
    echo "❌ 下载 stl 主命令脚本失败。"
    exit 1
  fi

  # 创建软链接
  echo "创建软链接 $STL_CMD 指向 $INSTALL_DIR/stl ..."
  # -f 强制创建，如果目标已存在则覆盖
  # -s 创建符号链接
  ln -sf "$INSTALL_DIR/stl" "$STL_CMD"
  if [ $? -eq 0 ]; then
    echo "✅ 软链接创建成功。"
  else
    echo "❌ 创建软链接失败。"
    exit 1
  fi

  # 初始化配置文件
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ℹ️ 初始化配置文件 $CONFIG_FILE ..."
    echo "SOURCE=https://raw.githubusercontent.com/frogchou/stools/main" > "$CONFIG_FILE"
    echo "✅ 配置文件初始化成功。"
  else
    echo "ℹ️ 配置文件 $CONFIG_FILE 已存在。"
  fi

  # 下载工具元数据
  echo "下载工具元数据到 $INSTALL_DIR/meta/tools.json ..."
  if curl -fsSL "https://raw.githubusercontent.com/frogchou/stools/main/meta/tools.json" -o "$INSTALL_DIR/meta/tools.json"; then
    echo "✅ 工具元数据下载成功。"
  else
    echo "❌ 下载工具元数据失败。"
    # 允许元数据下载失败，stl 命令本身仍可使用，只是列表等功能受限
    echo "⚠️ 工具列表功能可能受限。"
  fi

  echo "✅ stools 安装成功！可使用 \`stl\` 命令开始体验。"
  echo "例如：stl list  查看工具列表"
}

# 执行安装流程
check_root
check_and_install_dependencies
check_conflicts
main_install

exit 0