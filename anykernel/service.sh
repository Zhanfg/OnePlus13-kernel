#!/system/bin/sh
# ============================================================================
# service.sh - 一加13 自定义内核开机策略应用
# 由 AK3 刷写时生成, 在 /data/adb/modules/kernel_custom/system/etc/init.d/ 下
# 此文件为模板, 实际内容由 anykernel.sh 根据音量键选择动态生成
# ============================================================================

MODDIR=${0%/*}

# 等待系统启动完成
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# 额外等待 5 秒确保服务就绪
sleep 5

# ============================================================================
# 1. 调度策略
# ============================================================================
# 默认: wait (由 anykernel.sh 写入实际选择值)
SCHED_DEFAULT="wait"

if [ -f /sys/kernel/sched/enable_hmbird ]; then
    case "$SCHED_DEFAULT" in
        wait)
            echo 0 > /sys/kernel/sched/enable_hmbird 2>/dev/null
            ;;
        hmbird)
            echo 1 > /sys/kernel/sched/enable_hmbird 2>/dev/null
            ;;
    esac
fi

# ============================================================================
# 2. TCP 拥塞控制
# ============================================================================
TCP_DEFAULT="bbr3"

# 设置可用算法列表 (确保 bbr3 在列表中)
if [ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]; then
    CURRENT=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)
    case "$TCP_DEFAULT" in
        bbr3)
            if ! echo "$CURRENT" | grep -q "bbr3"; then
                modprobe tcp_bbr3 2>/dev/null || true
            fi
            ;;
        bbr)
            if ! echo "$CURRENT" | grep -q "bbr"; then
                modprobe tcp_bbr 2>/dev/null || true
            fi
            ;;
    esac
fi

echo "$TCP_DEFAULT" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null

# ============================================================================
# 3. 默认 qdisc
# ============================================================================
QDISC_DEFAULT="fq"
echo "$QDISC_DEFAULT" > /proc/sys/net/core/default_qdisc 2>/dev/null

# ============================================================================
# 4. ZRAM 压缩算法
# ============================================================================
ZRAM_DEFAULT="lz4"

if [ -f /sys/block/zram0/comp_algorithm ]; then
    AVAILABLE=$(cat /sys/block/zram0/comp_algorithm)
    # 去除括号标记
    AVAILABLE=$(echo "$AVAILABLE" | sed 's/\[//g; s/\]//g')
    if echo "$AVAILABLE" | grep -qw "$ZRAM_DEFAULT"; then
        echo "$ZRAM_DEFAULT" > /sys/block/zram0/comp_algorithm 2>/dev/null
    fi
fi

# ============================================================================
# 5. Baseband Guard
# ============================================================================
BBG_DEFAULT="on"

if [ -f /sys/module/baseband_guard/parameters/enabled ]; then
    case "$BBG_DEFAULT" in
        on)  echo 1 > /sys/module/baseband_guard/parameters/enabled 2>/dev/null ;;
        off) echo 0 > /sys/module/baseband_guard/parameters/enabled 2>/dev/null ;;
    esac
fi

# ============================================================================
# 6. 网络优化参数
# ============================================================================
# TCP Fast Open
echo 3 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null

# 禁用 slow start after idle
echo 0 > /proc/sys/net/ipv4/tcp_slow_start_after_idle 2>/dev/null

# TCP MTU probing
echo 1 > /proc/sys/net/ipv4/tcp_mtu_probing 2>/dev/null

# 缓冲区
echo "4096 87380 67108864" > /proc/sys/net/ipv4/tcp_rmem 2>/dev/null
echo "4096 65536 67108864" > /proc/sys/net/ipv4/tcp_wmem 2>/dev/null
echo 67108864 > /proc/sys/net/core/rmem_max 2>/dev/null
echo 67108864 > /proc/sys/net/core/wmem_max 2>/dev/null

# ============================================================================
# 7. 内存/VM 参数
# ============================================================================
echo 100 > /proc/sys/vm/swappiness 2>/dev/null
echo 0 > /proc/sys/vm/watermark_boost_factor 2>/dev/null
echo 10 > /proc/sys/vm/watermark_scale_factor 2>/dev/null

# 记录执行
echo "$(date): kernel_custom service.sh executed" >> /data/kernel_custom.log 2>/dev/null
