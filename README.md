# 常用Linux脚本集合

这是一个常用Linux系统管理脚本的集合，包含了系统优化、安全配置、网络设置等实用工具。

## 🚀 快速开始

### 一键管理工具 (推荐)

使用 `uls.sh` 统一管理脚本，提供交互式菜单，无需记忆复杂命令：

#### 方式一: 一键安装运行 (推荐)

使用短链接:
```bash
curl -fsSL https://l.czl.net/q/uls | sudo bash
```

或使用完整链接:
```bash
curl -fsSL https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/uls.sh | sudo bash
```

#### 方式二: 下载后运行

```bash
# 使用短链接
curl -fsSL https://l.czl.net/q/uls -o uls.sh && chmod +x uls.sh && sudo ./uls.sh

# 或使用完整链接
curl -fsSL https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/uls.sh -o uls.sh && chmod +x uls.sh && sudo ./uls.sh
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

### 🐳 Docker管理脚本

#### 🐳 Docker Volumes迁移脚本
将Docker volumes从一台服务器迁移到另一台服务器的完整解决方案。支持SSH密钥认证和密码认证,提供批量迁移和选择性迁移功能。

```bash
wget -O migrate_volumes.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/docker/migrate_volumes.sh
chmod +x migrate_volumes.sh
sudo ./migrate_volumes.sh
```

**功能特性：**
- ✅ 支持单个或批量迁移Docker volumes
- 🔐 支持SSH密钥认证（推荐）和密码认证
- 📦 自动压缩备份,节省传输时间
- 🔄 智能容器管理,自动处理正在使用的volume
- 🛡️ 完整的错误处理和连接测试
- 🧹 迁移完成后可选清理临时文件
- 📊 详细的迁移进度和状态反馈

**使用场景：**
- 服务器迁移时转移Docker数据
- Docker数据备份到远程服务器
- 多环境之间同步Docker volumes

### 🚄 代理节点管理脚本

#### 🚄 V2bX节点管理脚本
一键安装和管理V2bX (V2board节点服务端),自动调用上游官方脚本,确保功能始终保持最新。

```bash
wget -O setup_v2bx.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/proxy/setup_v2bx.sh
chmod +x setup_v2bx.sh
sudo ./setup_v2bx.sh
```

**关于 V2bX:**
- 基于多核心的 V2board 节点服务端
- 支持协议: Vmess/Vless, Trojan, Shadowsocks, Hysteria
- 支持自动申请和续签 TLS 证书
- 支持多节点管理和跨节点 IP 限制
- 项目地址: https://github.com/wyx2685/V2bX

**功能特性:**
- 🔄 自动同步上游官方脚本最新功能
- 📦 自动安装所有必要依赖
- 🛠️ 完整的服务管理命令提示
- 📝 详细的配置文档链接

**常用管理命令:**
```bash
systemctl start V2bX      # 启动服务
systemctl stop V2bX       # 停止服务
systemctl restart V2bX    # 重启服务
systemctl status V2bX     # 查看状态
journalctl -u V2bX -f     # 查看实时日志
```

**配置文件位置:** `/etc/V2bX/config.yml`

**注意事项:**
- 需要配合修改版 V2board 使用
- 建议在干净的系统上安装
- 安装前请确保服务器时间正确