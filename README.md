# 常用Linux脚本集合

这是一个常用Linux系统管理脚本的集合，包含了系统优化、安全配置、网络设置等实用工具。

## 🚀 快速开始

### 一键管理工具 (推荐)

使用 `uls.sh` 统一管理脚本，提供交互式菜单，无需记忆复杂命令：

#### 一键安装运行 (推荐)

**使用短链接**
```bash
curl -fsSL https://l.czl.net/q/uls -o uls.sh && chmod +x uls.sh && sudo ./uls.sh
```


**或使用完整链接**
```bash
curl -fsSL https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/uls.sh -o uls.sh && chmod +x uls.sh && sudo ./uls.sh
```

> **💡 提示:** ULS工具箱需要交互式终端运行,因此不支持通过管道直接执行 (如 `curl ... | bash`)。
> 如果尝试通过管道运行,脚本会自动提示正确的安装命令。

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

#### 🔍 安全监控管理工具
UFW和Fail2ban的集中监控管理平台，提供实时监控、IP管理、统计报告等功能。

```bash
wget -O security_monitor.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/security/security_monitor.sh
chmod +x security_monitor.sh
sudo ./security_monitor.sh
```

**核心功能：**
- 📊 **UFW拦截监控** - 查看最新拦截日志、Top 10攻击IP、被攻击端口统计
- 🚫 **Fail2ban封禁管理** - 查看所有Jail的封禁列表、封禁数量统计
- 🔴 **实时监控** - 自动刷新显示最新拦截和封禁情况(5秒刷新)
- 🎯 **IP管理功能**：
  - 解封IP (从所有Fail2ban Jail中移除)
  - 封禁IP (添加到指定Jail)
  - 查看UFW规则列表
  - 添加/删除UFW规则
- 📈 **统计报告** - 今日/昨日/总计拦截统计、Top 10攻击源分析
- 💾 **日志导出** - 一键导出UFW和Fail2ban完整日志及统计报告

**界面特点：**
- 🎨 彩色交互式界面，操作直观
- 🖥️ 实时显示UFW和Fail2ban服务状态
- 📋 分类清晰的菜单结构
- ⚡ 快速查看系统安全状况

### 🌐 网络配置脚本

#### 🌐 DNS配置锁定脚本
设置DNS为8.8.8.8和1.1.1.1，支持IPv6 DNS服务器，通过多种机制防止DNS配置被篡改。支持systemd-resolved和传统resolv.conf两种模式，包含自动恢复和定时检查功能。

```bash
wget -O setup_dns.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/network/setup_dns.sh
chmod +x setup_dns.sh
sudo ./setup_dns.sh
```

**功能特性：**
- 🌐 **IPv4 DNS**: Google DNS (8.8.8.8) 和 Cloudflare DNS (1.1.1.1)
- 🌐 **IPv6 DNS**: 自动检测IPv6支持，用户可选择是否配置IPv6 DNS
  - 选项1：同时配置IPv4和IPv6 DNS (推荐)
  - 选项2：仅配置IPv4 DNS
  - Google IPv6 DNS: 2001:4860:4860::8888
  - Cloudflare IPv6 DNS: 2606:4700:4700::1111
- 🔒 **多重保护**: chattr锁定 + systemd定时检查 + 自动恢复
- 🔧 **智能适配**: 支持systemd-resolved和传统resolv.conf模式
- ✅ **完整测试**: 根据配置测试IPv4和/或IPv6解析功能

卸载DNS锁定：
```bash
sudo ./setup_dns.sh --uninstall
```

#### 🌍 IPv6管理工具
提供IPv4优先级设置和IPv6禁用功能，解决IPv6网络环境下的连接问题，配置灵活易用。

```bash
wget -O ipv6_manager.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/network/ipv6_manager.sh
chmod +x ipv6_manager.sh
sudo ./ipv6_manager.sh
```

**核心功能：**
- 🎯 **IPv4优先级设置** - 保留IPv6但优先使用IPv4地址（推荐）
  - 通过 `/etc/gai.conf` 配置地址族优先级
  - 不影响IPv6功能，只改变连接顺序
  - 适合双栈环境优化连接速度
- 🚫 **完全禁用IPv6** - 彻底关闭IPv6功能
  - 通过 sysctl 和 GRUB 双重禁用
  - 适合纯IPv4环境或IPv6连接问题
  - 需要重启系统完全生效
- ✅ **启用IPv6** - 恢复IPv6功能
  - 清理所有禁用配置
  - 恢复系统默认IPv6设置
- 🔄 **恢复默认优先级** - 还原系统默认地址族优先级
- 📊 **状态查看** - 实时显示IPv6状态和网络地址
  - IPv6启用/禁用状态
  - 当前地址族优先级
  - IPv4和IPv6地址列表
- 💾 **自动备份** - 修改前自动备份配置文件

**使用场景：**
- 双栈环境下优化连接速度（优先IPv4）
- 解决某些应用IPv6兼容性问题
- 纯IPv4环境下禁用无用的IPv6
- 测试和调试网络连接问题

**配置说明：**
- 地址族优先级配置文件：`/etc/gai.conf`
- sysctl配置文件：`/etc/sysctl.conf`
- GRUB配置文件：`/etc/default/grub`
- 所有修改前都会自动备份，带时间戳

#### 🔌 GOST代理管理工具
一键安装、配置和管理GOST代理服务，支持HTTP/HTTPS和SOCKS5协议，使用systemd进行服务管理。

```bash
wget -O setup_gost.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/network/setup_gost.sh
chmod +x setup_gost.sh
sudo ./setup_gost.sh
```

**核心功能：**
- 📦 **一键安装** - 自动检测系统架构(amd64/arm64)，下载对应版本
- 🔧 **交互式配置**：
  - 选择代理协议（HTTP/HTTPS 或 SOCKS5）
  - 自定义监听端口
  - 可选用户认证（用户名/密码）
  - 端口占用检测
- 🔄 **服务管理**：
  - 启动/停止/重启代理服务
  - 查看实时运行状态
  - 查看服务日志
  - 自动重启机制
- 📊 **状态监控** - 显示服务状态、配置信息、监听端口、进程信息
- 🗑️ **完整卸载** - 一键清理所有文件和配置

**使用场景：**
- 快速搭建HTTP/SOCKS5代理服务器
- 内网穿透和流量转发
- 开发测试环境代理配置
- 多协议代理需求

**配置文件位置：**
- GOST二进制文件：`/usr/local/bin/gost`
- systemd服务文件：`/etc/systemd/system/gost.service`
- 配置信息文件：`/etc/gost/config.txt`

**关于GOST：**
- GOST是一个功能强大的GO语言编写的安全隧道工具
- 支持多种协议：HTTP/HTTPS, SOCKS4/5, SS等
- 项目地址：https://github.com/ginuerzh/gost
- 当前支持版本：v2.12.0

**支持架构：**
- x86_64 (amd64)
- aarch64 (arm64)

#### ☁️ Cloudflare WARP代理管理工具
一键安装、配置和管理Cloudflare WARP代理服务，支持SOCKS5代理，提供完整的账号和IP管理功能。

```bash
wget -O setup_warp.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/network/setup_warp.sh
chmod +x setup_warp.sh
sudo ./setup_warp.sh
```

**核心功能：**
- 📦 **一键安装** - 自动检测系统类型，配置WARP软件源并安装
- 🔧 **SOCKS5代理配置**：
  - 自定义代理端口（默认40000）
  - 自动注册WARP账号
  - 自动连接并验证
- 🔄 **服务管理**：
  - 启用/禁用WARP服务
  - 查看连接状态和配置信息
  - 查看账户信息
- 🔄 **账号管理**：
  - 更换WARP账号
  - 重新注册新账号
- 🌐 **IP管理**：
  - 快速更换出口IP
  - 显示当前IP地址
- 🧪 **连接测试**：
  - 测试直连IP和WARP IP
  - 测试代理延迟
  - 验证代理可用性
- 📊 **状态监控** - 显示连接状态、服务状态、账户信息
- 🗑️ **完整卸载** - 一键清理所有文件和配置

**使用场景：**
- 解锁Cloudflare网络优化
- 需要更换IP的应用场景
- 作为SOCKS5代理使用
- 绕过地理位置限制

**支持系统：**
- Debian/Ubuntu系列
- CentOS/RHEL系列（7及以上）

**配置文件位置：**
- WARP配置目录：`/etc/cloudflare-warp/`
- systemd服务：`warp-svc`

**关于Cloudflare WARP：**
- WARP是Cloudflare提供的免费VPN服务
- 基于WireGuard协议，性能优秀
- 提供1.1.1.1 with WARP的增强隐私保护
- 官方文档：https://developers.cloudflare.com/warp-client/

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

### 📊 服务器性能测试脚本

#### 📊 服务器性能测试工具
集成多个主流服务器性能测试工具,提供综合性能评估和网络质量测试。

```bash
wget -O server_benchmark.sh https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/scripts/benchmark/server_benchmark.sh
chmod +x server_benchmark.sh
sudo ./server_benchmark.sh
```

**可用测试工具:**

1. **NodeQuality测试**
   - 节点质量综合测试
   - 测试网络质量、延迟等指标
   - 适合测试服务器网络性能

2. **VPS融合怪服务器测评**
   - CPU、内存、磁盘、网络全方位测试
   - 综合性服务器性能评估
   - 适合VPS/云服务器全面测试

**功能特性:**
- 🎯 交互式菜单选择测试工具
- 🔄 自动调用最新上游测试脚本
- 📊 详细的性能测试报告
- 🧹 自动清理临时文件