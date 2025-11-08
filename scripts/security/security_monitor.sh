#!/bin/bash

################################################################################
# 脚本名称: security_monitor.sh
# 功能描述: UFW和Fail2ban安全监控管理工具
# 作者: ULS
# 版本: 1.0.0
# 最后更新: 2025-11-08
#
# 功能说明:
# - 查看UFW拦截日志和统计
# - 查看Fail2ban封禁IP列表
# - 实时安全监控(自动刷新)
# - IP管理(解封/封禁/查看详情)
# - 统计报告和日志导出
# - Top 10攻击IP排行
#
# 使用方法:
#   sudo ./security_monitor.sh
################################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
        echo -e "${YELLOW}请使用 sudo 命令运行此脚本${NC}"
        exit 1
    fi
}

# 检查UFW是否安装
check_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo -e "${RED}UFW未安装${NC}"
        return 1
    fi
    return 0
}

# 检查Fail2ban是否安装
check_fail2ban() {
    if ! command -v fail2ban-client &> /dev/null; then
        echo -e "${RED}Fail2ban未安装${NC}"
        return 1
    fi
    return 0
}

# 显示标题
show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}          ${BOLD}安全监控与管理工具${NC} ${CYAN}v1.0.0${NC}                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}          UFW & Fail2ban 集中管理平台                     ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 查看UFW拦截日志
view_ufw_logs() {
    show_header
    echo -e "${BLUE}【UFW 拦截日志】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if ! check_ufw; then
        echo -e "${YELLOW}请先安装UFW${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo -e "\n${GREEN}1. 最近50条拦截记录:${NC}\n"
    if [[ -f /var/log/ufw.log ]]; then
        grep "\\[UFW BLOCK\\]" /var/log/ufw.log | tail -50 | while read -r line; do
            echo -e "${YELLOW}→${NC} $line"
        done
    else
        echo -e "${RED}未找到UFW日志文件${NC}"
    fi

    echo -e "\n${GREEN}2. 今日拦截统计:${NC}\n"
    today=$(date +%Y-%m-%d)
    if [[ -f /var/log/ufw.log ]]; then
        total_blocks=$(grep "\\[UFW BLOCK\\]" /var/log/ufw.log | grep "$today" | wc -l)
        echo -e "${CYAN}总拦截次数:${NC} ${BOLD}$total_blocks${NC}"

        echo -e "\n${GREEN}3. Top 10 被拦截源IP:${NC}\n"
        grep "\\[UFW BLOCK\\]" /var/log/ufw.log | grep "$today" | \
            grep -oP 'SRC=\K[0-9.]+' | sort | uniq -c | sort -rn | head -10 | \
            awk '{printf "  %-15s %s 次\n", $2, $1}'
    fi

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "按回车键返回..." dummy
}

# 查看Fail2ban封禁列表
view_fail2ban_bans() {
    show_header
    echo -e "${BLUE}【Fail2ban 封禁列表】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if ! check_fail2ban; then
        echo -e "${YELLOW}请先安装Fail2ban${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    # 检查fail2ban服务状态
    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${RED}Fail2ban服务未运行${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo -e "\n${GREEN}当前活跃的Jail和封禁情况:${NC}\n"

    # 获取所有jail
    jails=$(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,//g')

    if [[ -z "$jails" ]]; then
        echo -e "${YELLOW}没有配置任何Jail${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    total_banned=0
    for jail in $jails; do
        banned_ips=$(fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list" | sed 's/.*://; s/\s//g')
        banned_count=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')

        echo -e "${CYAN}Jail: ${BOLD}$jail${NC}"
        echo -e "  当前封禁数: ${YELLOW}$banned_count${NC}"

        if [[ -n "$banned_ips" && "$banned_ips" != "" ]]; then
            echo -e "  封禁IP列表:"
            for ip in ${banned_ips//,/ }; do
                echo -e "    ${RED}✗${NC} $ip"
            done
        fi
        echo ""

        total_banned=$((total_banned + banned_count))
    done

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}总计封禁IP数: ${BOLD}$total_banned${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    read -p "按回车键返回..." dummy
}

# 实时监控
realtime_monitor() {
    show_header
    echo -e "${BLUE}【实时安全监控】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出监控${NC}\n"

    ufw_available=0
    fail2ban_available=0

    check_ufw && ufw_available=1
    check_fail2ban && systemctl is-active --quiet fail2ban && fail2ban_available=1

    while true; do
        echo -e "\n${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC}"

        if [[ $ufw_available -eq 1 ]]; then
            echo -e "\n${CYAN}UFW 最新拦截:${NC}"
            if [[ -f /var/log/ufw.log ]]; then
                tail -5 /var/log/ufw.log | grep "\\[UFW BLOCK\\]" | while read -r line; do
                    echo -e "  ${YELLOW}→${NC} $line"
                done
            fi
        fi

        if [[ $fail2ban_available -eq 1 ]]; then
            echo -e "\n${CYAN}Fail2ban 封禁统计:${NC}"
            jails=$(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,//g')
            for jail in $jails; do
                banned_count=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
                echo -e "  ${jail}: ${RED}$banned_count${NC} IPs"
            done
        fi

        echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        sleep 5
    done
}

# IP管理
manage_ip() {
    while true; do
        show_header
        echo -e "${BLUE}【IP 管理】${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 解封IP (Fail2ban)"
        echo -e "${GREEN}2.${NC} 封禁IP (Fail2ban)"
        echo -e "${GREEN}3.${NC} 查看UFW规则"
        echo -e "${GREEN}4.${NC} 添加UFW拒绝规则"
        echo -e "${GREEN}5.${NC} 删除UFW规则"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1)
                unban_ip
                ;;
            2)
                ban_ip
                ;;
            3)
                view_ufw_rules
                ;;
            4)
                add_ufw_deny
                ;;
            5)
                delete_ufw_rule
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 解封IP
unban_ip() {
    show_header
    echo -e "${BLUE}【解封IP】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if ! check_fail2ban; then
        echo -e "${YELLOW}Fail2ban未安装${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo ""
    read -p "请输入要解封的IP地址: " ip

    if [[ -z "$ip" ]]; then
        echo -e "${RED}IP地址不能为空${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    # 从所有jail中解封
    jails=$(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,//g')

    echo -e "\n${YELLOW}正在从所有Jail中解封 $ip...${NC}\n"

    unbanned=0
    for jail in $jails; do
        if fail2ban-client set "$jail" unbanip "$ip" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} 从 $jail 解封成功"
            unbanned=1
        fi
    done

    if [[ $unbanned -eq 1 ]]; then
        echo -e "\n${GREEN}IP解封完成${NC}"
    else
        echo -e "\n${YELLOW}该IP可能未被封禁${NC}"
    fi

    read -p "按回车键返回..." dummy
}

# 封禁IP
ban_ip() {
    show_header
    echo -e "${BLUE}【封禁IP】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if ! check_fail2ban; then
        echo -e "${YELLOW}Fail2ban未安装${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo ""
    read -p "请输入要封禁的IP地址: " ip

    if [[ -z "$ip" ]]; then
        echo -e "${RED}IP地址不能为空${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    # 显示可用的jail
    jails=$(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,//g')

    echo -e "\n${GREEN}可用的Jail:${NC}"
    jail_array=($jails)
    i=1
    for jail in "${jail_array[@]}"; do
        echo -e "${CYAN}$i.${NC} $jail"
        ((i++))
    done

    echo ""
    read -p "请选择Jail编号 (或直接输入Jail名称): " jail_choice

    selected_jail=""
    if [[ "$jail_choice" =~ ^[0-9]+$ ]]; then
        if [[ $jail_choice -gt 0 && $jail_choice -le ${#jail_array[@]} ]]; then
            selected_jail="${jail_array[$((jail_choice-1))]}"
        fi
    else
        selected_jail="$jail_choice"
    fi

    if [[ -z "$selected_jail" ]]; then
        echo -e "${RED}无效的Jail选择${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo -e "\n${YELLOW}正在封禁 $ip 到 $selected_jail...${NC}\n"

    if fail2ban-client set "$selected_jail" banip "$ip" 2>/dev/null; then
        echo -e "${GREEN}✓ IP封禁成功${NC}"
    else
        echo -e "${RED}✗ IP封禁失败${NC}"
    fi

    read -p "按回车键返回..." dummy
}

# 查看UFW规则
view_ufw_rules() {
    show_header
    echo -e "${BLUE}【UFW 规则列表】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if ! check_ufw; then
        echo -e "${YELLOW}UFW未安装${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo ""
    ufw status numbered

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "按回车键返回..." dummy
}

# 添加UFW拒绝规则
add_ufw_deny() {
    show_header
    echo -e "${BLUE}【添加UFW拒绝规则】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if ! check_ufw; then
        echo -e "${YELLOW}UFW未安装${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo ""
    read -p "请输入要拒绝的IP地址或CIDR: " ip

    if [[ -z "$ip" ]]; then
        echo -e "${RED}IP地址不能为空${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo -e "\n${YELLOW}正在添加拒绝规则...${NC}\n"

    if ufw deny from "$ip" 2>/dev/null; then
        echo -e "${GREEN}✓ UFW规则添加成功${NC}"
        ufw status
    else
        echo -e "${RED}✗ UFW规则添加失败${NC}"
    fi

    read -p "按回车键返回..." dummy
}

# 删除UFW规则
delete_ufw_rule() {
    show_header
    echo -e "${BLUE}【删除UFW规则】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if ! check_ufw; then
        echo -e "${YELLOW}UFW未安装${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo ""
    ufw status numbered

    echo ""
    read -p "请输入要删除的规则编号: " rule_num

    if [[ -z "$rule_num" ]]; then
        echo -e "${RED}规则编号不能为空${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    echo -e "\n${YELLOW}正在删除规则...${NC}\n"

    if echo "y" | ufw delete "$rule_num" 2>/dev/null; then
        echo -e "${GREEN}✓ UFW规则删除成功${NC}"
    else
        echo -e "${RED}✗ UFW规则删除失败${NC}"
    fi

    read -p "按回车键返回..." dummy
}

# 统计报告
statistics_report() {
    show_header
    echo -e "${BLUE}【统计报告】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    echo -e "\n${GREEN}=== UFW 统计 ===${NC}\n"

    if check_ufw && [[ -f /var/log/ufw.log ]]; then
        today=$(date +%Y-%m-%d)
        yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

        today_blocks=$(grep "\\[UFW BLOCK\\]" /var/log/ufw.log | grep "$today" | wc -l)
        yesterday_blocks=$(grep "\\[UFW BLOCK\\]" /var/log/ufw.log | grep "$yesterday" | wc -l)
        total_blocks=$(grep "\\[UFW BLOCK\\]" /var/log/ufw.log | wc -l)

        echo -e "${CYAN}今日拦截:${NC}     ${BOLD}$today_blocks${NC} 次"
        echo -e "${CYAN}昨日拦截:${NC}     ${BOLD}$yesterday_blocks${NC} 次"
        echo -e "${CYAN}总计拦截:${NC}     ${BOLD}$total_blocks${NC} 次"

        echo -e "\n${GREEN}Top 10 被拦截IP (今日):${NC}\n"
        grep "\\[UFW BLOCK\\]" /var/log/ufw.log | grep "$today" | \
            grep -oP 'SRC=\K[0-9.]+' | sort | uniq -c | sort -rn | head -10 | \
            awk '{printf "  %-3s %-15s %s\n", NR".", $2, $1" 次"}'

        echo -e "\n${GREEN}Top 10 被攻击端口 (今日):${NC}\n"
        grep "\\[UFW BLOCK\\]" /var/log/ufw.log | grep "$today" | \
            grep -oP 'DPT=\K[0-9]+' | sort | uniq -c | sort -rn | head -10 | \
            awk '{printf "  %-3s 端口 %-6s %s\n", NR".", $2, $1" 次"}'
    else
        echo -e "${YELLOW}UFW未安装或日志文件不存在${NC}"
    fi

    echo -e "\n${GREEN}=== Fail2ban 统计 ===${NC}\n"

    if check_fail2ban && systemctl is-active --quiet fail2ban; then
        jails=$(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,//g')

        total_banned=0
        total_failed=0

        for jail in $jails; do
            banned_count=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
            failed_count=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently failed" | awk '{print $NF}')

            echo -e "${CYAN}Jail: ${BOLD}$jail${NC}"
            echo -e "  当前封禁: ${RED}$banned_count${NC} IPs"
            echo -e "  当前失败: ${YELLOW}$failed_count${NC} 次"
            echo ""

            total_banned=$((total_banned + banned_count))
            total_failed=$((total_failed + failed_count))
        done

        echo -e "${GREEN}总计:${NC}"
        echo -e "  封禁IP总数: ${RED}${BOLD}$total_banned${NC}"
        echo -e "  失败尝试总数: ${YELLOW}${BOLD}$total_failed${NC}"
    else
        echo -e "${YELLOW}Fail2ban未安装或未运行${NC}"
    fi

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "按回车键返回..." dummy
}

# 导出日志
export_logs() {
    show_header
    echo -e "${BLUE}【导出日志】${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    export_dir="/root/security_logs_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$export_dir"

    echo -e "\n${YELLOW}正在导出日志到: $export_dir${NC}\n"

    # 导出UFW日志
    if check_ufw && [[ -f /var/log/ufw.log ]]; then
        echo -e "${GREEN}✓${NC} 导出UFW日志..."
        cp /var/log/ufw.log "$export_dir/ufw.log"
        grep "\\[UFW BLOCK\\]" /var/log/ufw.log > "$export_dir/ufw_blocks.log"
    fi

    # 导出Fail2ban日志
    if check_fail2ban; then
        echo -e "${GREEN}✓${NC} 导出Fail2ban日志..."
        if [[ -f /var/log/fail2ban.log ]]; then
            cp /var/log/fail2ban.log "$export_dir/fail2ban.log"
        fi

        # 导出当前封禁列表
        jails=$(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,//g')
        echo "Fail2ban 封禁列表 - $(date)" > "$export_dir/fail2ban_banned_ips.txt"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$export_dir/fail2ban_banned_ips.txt"

        for jail in $jails; do
            echo "" >> "$export_dir/fail2ban_banned_ips.txt"
            echo "Jail: $jail" >> "$export_dir/fail2ban_banned_ips.txt"
            fail2ban-client status "$jail" >> "$export_dir/fail2ban_banned_ips.txt"
        done
    fi

    # 生成统计报告
    {
        echo "安全监控统计报告"
        echo "生成时间: $(date)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        if check_ufw && [[ -f /var/log/ufw.log ]]; then
            echo "=== UFW 统计 ==="
            today=$(date +%Y-%m-%d)
            today_blocks=$(grep "\\[UFW BLOCK\\]" /var/log/ufw.log | grep "$today" | wc -l)
            total_blocks=$(grep "\\[UFW BLOCK\\]" /var/log/ufw.log | wc -l)

            echo "今日拦截: $today_blocks 次"
            echo "总计拦截: $total_blocks 次"
            echo ""

            echo "Top 10 攻击IP (今日):"
            grep "\\[UFW BLOCK\\]" /var/log/ufw.log | grep "$today" | \
                grep -oP 'SRC=\K[0-9.]+' | sort | uniq -c | sort -rn | head -10
            echo ""
        fi

        if check_fail2ban && systemctl is-active --quiet fail2ban; then
            echo "=== Fail2ban 统计 ==="
            jails=$(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,//g')

            for jail in $jails; do
                echo "Jail: $jail"
                fail2ban-client status "$jail" | grep "Currently banned"
                fail2ban-client status "$jail" | grep "Currently failed"
                echo ""
            done
        fi
    } > "$export_dir/statistics_report.txt"

    echo -e "\n${GREEN}✓ 日志导出完成${NC}"
    echo -e "${CYAN}导出位置: ${BOLD}$export_dir${NC}"
    echo -e "\n${YELLOW}导出的文件:${NC}"
    ls -lh "$export_dir"

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "按回车键返回..." dummy
}

# 主菜单
main_menu() {
    while true; do
        show_header

        # 显示系统状态
        echo -e "${GREEN}系统状态:${NC}"

        if check_ufw; then
            ufw_status=$(ufw status | head -1 | awk '{print $2}')
            if [[ "$ufw_status" == "active" ]]; then
                echo -e "  UFW: ${GREEN}● 运行中${NC}"
            else
                echo -e "  UFW: ${RED}○ 未激活${NC}"
            fi
        else
            echo -e "  UFW: ${YELLOW}○ 未安装${NC}"
        fi

        if check_fail2ban; then
            if systemctl is-active --quiet fail2ban; then
                echo -e "  Fail2ban: ${GREEN}● 运行中${NC}"
            else
                echo -e "  Fail2ban: ${RED}○ 未运行${NC}"
            fi
        else
            echo -e "  Fail2ban: ${YELLOW}○ 未安装${NC}"
        fi

        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 查看UFW拦截日志"
        echo -e "${GREEN}2.${NC} 查看Fail2ban封禁列表"
        echo -e "${GREEN}3.${NC} 实时监控 (自动刷新)"
        echo -e "${GREEN}4.${NC} IP管理 (解封/封禁/规则)"
        echo -e "${GREEN}5.${NC} 统计报告"
        echo -e "${GREEN}6.${NC} 导出日志"
        echo -e "${GREEN}0.${NC} 退出"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        read -p "请选择操作 [0-6]: " choice

        case $choice in
            1)
                view_ufw_logs
                ;;
            2)
                view_fail2ban_bans
                ;;
            3)
                realtime_monitor
                ;;
            4)
                manage_ip
                ;;
            5)
                statistics_report
                ;;
            6)
                export_logs
                ;;
            0)
                echo -e "\n${GREEN}感谢使用安全监控工具!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择,请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 主程序入口
main() {
    check_root
    main_menu
}

main "$@"
