# 常用Linux脚本集合

这是一个常用Linux系统管理脚本的集合，包含了系统优化、安全配置、网络设置等实用工具。

## 🚀 快速开始

### 一键管理工具 (推荐)

使用 `uls.sh` 统一管理脚本，提供交互式菜单，无需记忆复杂命令：

```bash
# 下载并运行ULS工具箱
curl -fsSL https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/uls.sh -o uls.sh
chmod +x uls.sh
sudo ./uls.sh
```

**ULS工具箱功能：**
- 🎯 交互式菜单，操作简单直观
- 📥 每次执行都下载最新脚本版本，确保功能最新
- 🔄 基于GitHub Release的自动版本管理
- 🤖 GitHub Actions自动测试和发布
- 🗑️ 完整卸载功能，干净移除所有文件
- ⚡ 可选安装到系统路径，全局使用

---

## 📜 独立脚本使用

### 🖥️ 系统优化脚本

#### 🔄 Swap空间管理脚本
一键添加swap空间的交互式脚本，会先显示当前swap状态，支持自定义swap大小。

```bash
wget -O add-swap.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/system/add-swap.sh
chmod +x add-swap.sh
sudo ./add-swap.sh
```

#### 🚀 BBR TCP优化脚本
检查内核版本并启用BBR TCP拥塞控制算法，显著提升网络传输性能。

```bash
bash <(curl -s https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/system/enable_bbr.sh)
```

### 🔒 安全防护脚本

#### 🛡️ UFW防火墙配置脚本
自动检测并安装UFW防火墙，配置常用端口(22,80,443)，支持自定义端口设置，启用防火墙并设置开机自启。

```bash
wget -O setup_ufw.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/security/setup_ufw.sh
chmod +x setup_ufw.sh
sudo ./setup_ufw.sh
```

#### 🚫 Fail2ban入侵防护脚本
自动安装配置Fail2ban入侵检测系统，配置SSH永久封禁模式，与UFW防火墙深度集成。

```bash
wget -O setup_fail2ban.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/security/setup_fail2ban.sh
chmod +x setup_fail2ban.sh
sudo ./setup_fail2ban.sh
```

### 🌐 网络配置脚本

#### 🌐 DNS配置锁定脚本
设置DNS为8.8.8.8和1.1.1.1，通过多种机制防止DNS配置被篡改。支持systemd-resolved和传统resolv.conf两种模式，包含自动恢复和定时检查功能。

```bash
wget -O setup_dns.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/network/setup_dns.sh
chmod +x setup_dns.sh
sudo ./setup_dns.sh
```

卸载DNS锁定：
```bash
sudo ./setup_dns.sh --uninstall
```