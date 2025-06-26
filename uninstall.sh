#!/bin/bash
# uninstall.sh - stools 卸载脚本

INSTALL_DIR="/opt/stools"
BIN_DIR="/usr/local/bin"
STL_CMD="$BIN_DIR/stl"
CONFIG_FILE="$HOME/.stoolsrc"

echo "ℹ️ 开始卸载 stools..."

# 检查管理员权限
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户或 sudo 执行卸载命令。"
  exit 1
fi

# 删除软链接
if [ -L "$STL_CMD" ]; then
  echo "🗑️ 删除软链接 $STL_CMD..."
  rm -f "$STL_CMD"
  if [ $? -eq 0 ]; then
    echo "✅ 软链接 $STL_CMD 已删除。"
  else
    echo "⚠️ 未能删除软链接 $STL_CMD。"
  fi
else
  echo "ℹ️ 软链接 $STL_CMD 不存在。"
fi

# 删除安装目录
if [ -d "$INSTALL_DIR" ]; then
  echo "🗑️ 删除安装目录 $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
  if [ $? -eq 0 ]; then
    echo "✅ 安装目录 $INSTALL_DIR 已删除。"
  else
    echo "⚠️ 未能删除安装目录 $INSTALL_DIR。"
  fi
else
  echo "ℹ️ 安装目录 $INSTALL_DIR 不存在。"
fi

# 删除配置文件
if [ -f "$CONFIG_FILE" ]; then
  echo "🗑️ 删除配置文件 $CONFIG_FILE..."
  rm -f "$CONFIG_FILE"
  if [ $? -eq 0 ]; then
    echo "✅ 配置文件 $CONFIG_FILE 已删除。"
  else
    echo "⚠️ 未能删除配置文件 $CONFIG_FILE。"
  fi
else
  echo "ℹ️ 配置文件 $CONFIG_FILE 不存在。"
fi

echo "✅ stools 卸载完成。"