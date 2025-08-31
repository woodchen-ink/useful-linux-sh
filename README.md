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

- [setup_ufw.sh](./setup_ufw.sh) UFW防火墙一键配置脚本
  - 脚本功能：自动检测并安装UFW防火墙，配置默认端口(22,80,443)，支持自定义端口，启用防火墙并设置开机自启
  - 脚本使用：
```bash
wget -O setup_ufw.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/setup_ufw.sh
chmod +x setup_ufw.sh
sudo ./setup_ufw.sh
```

- [setup_fail2ban.sh](./setup_fail2ban.sh) Fail2ban一键安装配置脚本
  - 脚本功能：自动检测并安装Fail2ban，配置SSH永久封禁模式(bantime = -1)，集成UFW防火墙
  - 脚本使用：
```bash
wget -O setup_fail2ban.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/setup_fail2ban.sh
chmod +x setup_fail2ban.sh
sudo ./setup_fail2ban.sh
```