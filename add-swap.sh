#!/bin/bash
# 一键添加 swap 空间 (交互式版本，先显示当前 swap)

SWAPFILE="/swapfile"

echo "🔍 当前 swap 状态:"
swapon --show || echo "没有启用任何 swap"
free -h

# 如果已有 swapfile 就退出
if swapon --show | grep -q "$SWAPFILE"; then
  echo "⚠️ 系统已经有 $SWAPFILE, 不需要重复创建."
  exit 0
fi

# 交互式输入大小
read -p "请输入要创建的 swap 大小 (例如 4G 或 512M): " SIZE

if [ -z "$SIZE" ]; then
  echo "❌ 你没有输入大小, 退出."
  exit 1
fi

echo "👉 开始创建 swap 文件: $SIZE"

# 创建 swap 文件
fallocate -l $SIZE $SWAPFILE 2>/dev/null || dd if=/dev/zero of=$SWAPFILE bs=1M count=${SIZE%G*}000 status=progress

# 设置权限
chmod 600 $SWAPFILE

# 格式化为 swap
mkswap $SWAPFILE

# 启用 swap
swapon $SWAPFILE

# 写入 fstab 保持开机生效
if ! grep -q "$SWAPFILE" /etc/fstab; then
  echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

# 调整 swappiness
sysctl vm.swappiness=10
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
  echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

echo "✅ 已成功创建并启用 $SIZE swap"
swapon --show
free -h
