# 常用linux脚本

## 脚本列表
- [add-swap.sh](./sh/add-swap.sh) 一键添加 swap 空间 (交互式版本，先显示当前 swap)
  - 脚本功能：一键添加 swap 空间 (交互式版本，先显示当前 swap)
  - 脚本使用：
```bash
wget -O add-swap.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/sh/add-swap.sh
chmod +x add-swap.sh
sudo ./add-swap.sh
```

- [enable_bbr.sh](./enable_bbr.sh) 一键启用 BBR TCP 拥塞控制算法
  - 脚本功能：检查内核版本并启用 BBR TCP 拥塞控制算法以提升网络性能
  - 脚本使用：
```bash
bash <(curl -s https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/enable_bbr.sh)
```