#!/bin/bash

# BBR TCP Congestion Control Setup Script
# Requires kernel version 4.9 or higher

set -e

echo "检查内核版本..."
KERNEL_VERSION=$(uname -r)
echo "当前内核版本: $KERNEL_VERSION"

echo "检查是否有 root 权限..."
if [[ $EUID -ne 0 ]]; then
   echo "此脚本需要 root 权限运行"
   echo "请使用: sudo $0"
   exit 1
fi

echo "配置 BBR..."
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

echo "应用配置..."
sysctl -p

echo "验证 BBR 是否成功启用..."
AVAILABLE_CONTROL=$(sysctl net.ipv4.tcp_available_congestion_control)
echo "$AVAILABLE_CONTROL"

if echo "$AVAILABLE_CONTROL" | grep -q bbr; then
    echo "✓ BBR 已成功启用！"
else
    echo "✗ BBR 启用失败，请检查内核版本是否支持"
    exit 1
fi

echo "配置完成！"