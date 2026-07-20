#!/system/bin/sh
# ============================================================================
# 运行时验收脚本 - 一加13 (sun/SM8750) 自定义内核
# 规格 §4.2.3 + §6
#
# 在真机 ColorOS 16 国行上执行 (需 root)
# 用法: sh verify_runtime.sh
# ============================================================================

PASS=0
FAIL=0
WARN=0

# 颜色
G='\033[32m'; R='\033[31m'; Y='\033[33m'; B='\033[34m'; N='\033[0m'
ok()   { echo -e "${G}[PASS]${N} $1"; PASS=$((PASS+1)); }
no()   { echo -e "${R}[FAIL]${N} $1"; FAIL=$((FAIL+1)); }
wn()   { echo -e "${Y}[WARN]${N} $1"; WARN=$((WARN+1)); }
info() { echo -e "${B}[INFO]${N} $1"; }

echo "========================================"
echo " 一加13 自定义内核 - 运行时验收"
echo " 规格 §4.2.3 + §6"
echo "========================================"
echo "日期: $(date)"
echo "内核: $(uname -r)"
echo "设备: $(getprop ro.product.device 2>/dev/null)"
echo ""

# ============================================================================
# A. 默认 wait 验收 (规格 §4.2.3-B)
# ============================================================================
echo "=== A. 默认调度验收 ==="

info "搜索调度相关 sysfs 节点..."
WAIT_NODES=$(find /sys -iname '*wait*' 2>/dev/null | head -20)
SCHED_NODES=$(find /sys/devices /sys/kernel -iname '*sched*' 2>/dev/null | head -40)

if [ -n "$WAIT_NODES" ]; then
    info "wait 相关节点:"
    echo "$WAIT_NODES" | while read n; do echo "  $n"; done
fi

if [ -n "$SCHED_NODES" ]; then
    info "sched 相关节点 (前20):"
    echo "$SCHED_NODES" | head -20 | while read n; do echo "  $n"; done
fi

# 检查 schedstat
if [ -f /proc/schedstat ]; then
    info "/proc/schedstat 前5行:"
    head -5 /proc/schedstat
    ok "/proc/schedstat 存在"
else
    no "/proc/schedstat 不存在"
fi

# 检查 dmesg 中的调度信息
DMESG_SCHED=$(dmesg 2>/dev/null | grep -iE 'wait|sched|hmbird|fengchi' | tail -30)
if [ -n "$DMESG_SCHED" ]; then
    info "dmesg 调度日志 (后30行):"
    echo "$DMESG_SCHED" | while read line; do echo "  $line"; done
fi

echo ""

# ============================================================================
# B. HMBIRD / 风驰 是否「有实装」(规格 §4.2.3-C)
# ============================================================================
echo "=== B. HMBIRD / 风驰 实装检查 ==="

HMBIRD_NODES=$(find /sys /proc -iname '*hmbird*' 2>/dev/null)
FENGCHI_NODES=$(find /sys /proc -iname '*fengchi*' 2>/dev/null)
SCX_NODES=$(find /sys /proc -iname '*scx*' 2>/dev/null)

if [ -n "$HMBIRD_NODES" ]; then
    info "HMBIRD 节点:"
    echo "$HMBIRD_NODES" | while read n; do echo "  $n"; done
    ok "HMBIRD 控制节点存在"
else
    wn "未找到 HMBIRD sysfs/proc 节点 (可能未启用或路径不同)"
fi

if [ -n "$FENGCHI_NODES" ]; then
    info "风驰节点:"
    echo "$FENGCHI_NODES" | while read n; do echo "  $n"; done
    ok "风驰控制节点存在"
fi

# dmesg 检查
DMESG_HMBIRD=$(dmesg 2>/dev/null | grep -iE 'hmbird|fengchi|scx')
if [ -n "$DMESG_HMBIRD" ]; then
    info "dmesg HMBIRD/风驰日志:"
    echo "$DMESG_HMBIRD" | while read line; do echo "  $line"; done
    ok "dmesg 中有 HMBIRD/风驰记录"
else
    wn "dmesg 中未找到 HMBIRD/风驰 日志"
fi

echo ""

# ============================================================================
# C. TCP / 网络 (规格 §6.2)
# ============================================================================
echo "=== C. 网络栈验收 ==="

# TCP 拥塞控制
TCP_CC=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
info "当前 TCP 拥塞控制: $TCP_CC"
if echo "$TCP_CC" | grep -q "bbr3"; then
    ok "TCP = bbr3 (规格要求)"
else
    no "TCP != bbr3 (当前: $TCP_CC)"
fi

TCP_AVAIL=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)
info "可用 TCP 算法: $TCP_AVAIL"
if echo "$TCP_AVAIL" | grep -q "bbr3"; then
    ok "bbr3 在可用列表中"
else
    no "bbr3 不在可用列表中"
fi

# qdisc
QDISC=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)
info "默认 qdisc: $QDISC"
if echo "$QDISC" | grep -q "fq"; then
    ok "qdisc = fq (规格要求)"
else
    no "qdisc != fq (当前: $QDISC)"
fi

# WireGuard
if [ -d /sys/module/wireguard ] || lsmod 2>/dev/null | grep -q wireguard; then
    ok "WireGuard 已加载"
else
    wn "WireGuard 模块未加载 (可能需手动 modprobe)"
fi

# IP_SET
if [ -d /sys/module/ip_set ] || lsmod 2>/dev/null | grep -q ip_set; then
    ok "IP_SET 已加载"
else
    wn "IP_SET 模块未加载"
fi

echo ""

# ============================================================================
# D. ZRAM (规格 §6.2)
# ============================================================================
echo "=== D. ZRAM 验收 ==="

if [ -f /sys/block/zram0/comp_algorithm ]; then
    ZRAM_ALGO=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)
    info "ZRAM 压缩算法: $ZRAM_ALGO"
    if echo "$ZRAM_ALGO" | grep -q '\[lz4\]'; then
        ok "ZRAM 默认 = lz4 (规格要求)"
    else
        wn "ZRAM 默认非 lz4 (当前: $ZRAM_ALGO)"
    fi

    # 检查多算法支持
    ZRAM_ALGOS=$(echo "$ZRAM_ALGO" | sed 's/\[//g; s/\]//g')
    info "可用算法: $ZRAM_ALGOS"
    for algo in lz4 zstd lzo; do
        if echo "$ZRAM_ALGOS" | grep -qw "$algo"; then
            ok "ZRAM 支持 $algo"
        fi
    done
else
    no "ZRAM 设备不存在"
fi

echo ""

# ============================================================================
# E. Root / SuSFS (规格 §6.2)
# ============================================================================
echo "=== E. Root / SuSFS 验收 ==="

# ReSukiSU
if su -c id 2>/dev/null | grep -q "uid=0"; then
    ok "ReSukiSU root 可用 (su -c id)"
else
    no "ReSukiSU root 不可用"
fi

# KALLSYMS
if [ -f /proc/kallsyms ]; then
    SYM_COUNT=$(wc -l < /proc/kallsyms 2>/dev/null)
    info "/proc/kallsyms 符号数: $SYM_COUNT"
    if [ "$SYM_COUNT" -gt 1000 ]; then
        ok "KALLSYMS 已启用 (符号数 > 1000)"
    else
        wn "KALLSYMS 符号数较少 ($SYM_COUNT)"
    fi
else
    no "/proc/kallsyms 不存在"
fi

# SuSFS 版本检查
SUSFS_VER=$(su -c 'cat /sys/fs/susfs/version 2>/dev/null' 2>/dev/null || echo "")
if [ -n "$SUSFS_VER" ]; then
    info "SuSFS 版本: $SUSFS_VER"
    if echo "$SUSFS_VER" | grep -q "2.2.0"; then
        ok "SuSFS v2.2.0 (规格要求)"
    else
        wn "SuSFS 版本非 2.2.0 (当前: $SUSFS_VER)"
    fi
else
    wn "无法读取 SuSFS 版本 (路径可能不同)"
fi

echo ""

# ============================================================================
# F. hy / Mountify (规格 §6.2)
# ============================================================================
echo "=== F. hy / Mountify 验收 ==="

# OverlayFS
if [ -f /proc/filesystems ] && grep -q overlay /proc/filesystems; then
    ok "OverlayFS 已启用"
else
    no "OverlayFS 未启用"
fi

# TMPFS XATTR
if [ -f /proc/filesystems ] && grep -q tmpfs /proc/filesystems; then
    ok "TMPFS 已启用"
    # 尝试测试 xattr
    mkdir -p /tmp/xattr_test 2>/dev/null
    mount -t tmpfs tmpfs /tmp/xattr_test 2>/dev/null
    if echo test > /tmp/xattr_test/file 2>/dev/null; then
        if setfattr -n user.test -v value /tmp/xattr_test/file 2>/dev/null; then
            ok "TMPFS XATTR 可用"
        else
            wn "TMPFS XATTR 不可用 (setfattr 失败)"
        fi
    fi
    umount /tmp/xattr_test 2>/dev/null
    rmdir /tmp/xattr_test 2>/dev/null
fi

echo ""

# ============================================================================
# G. NTSYNC (规格 §6.2)
# ============================================================================
echo "=== G. NTSYNC 验收 ==="

if [ -c /dev/ntsync ]; then
    ok "/dev/ntsync 存在"
else
    no "/dev/ntsync 不存在"
fi

echo ""

# ============================================================================
# H. Droidspaces (规格 §6.2)
# ============================================================================
echo "=== H. Droidspaces 验收 ==="

# unshare -p 测试
if su -c 'unshare -p echo "unshare test ok"' 2>/dev/null | grep -q "ok"; then
    ok "unshare -p (PID_NS) 可用"
else
    no "unshare -p 失败 (PID_NS 不可用)"
fi

# unshare -i 测试 (IPC_NS)
if su -c 'unshare -i echo "ipc test ok"' 2>/dev/null | grep -q "ok"; then
    ok "unshare -i (IPC_NS) 可用"
else
    wn "unshare -i 失败 (IPC_NS)"
fi

echo ""

# ============================================================================
# I. Baseband Guard (规格 §6.2)
# ============================================================================
echo "=== I. Baseband Guard 验收 ==="

BBG_PARAM="/sys/module/baseband_guard/parameters/enabled"
if [ -f "$BBG_PARAM" ]; then
    BBG_STATE=$(cat "$BBG_PARAM" 2>/dev/null)
    info "BBG 状态: $BBG_STATE"
    if [ "$BBG_STATE" = "Y" ] || [ "$BBG_STATE" = "1" ]; then
        ok "BBG 默认开启 (规格要求)"
    else
        wn "BBG 当前未开启 (状态: $BBG_STATE)"
    fi

    # 测试可关闭
    info "测试 BBG 关闭..."
    su -c "echo 0 > $BBG_PARAM" 2>/dev/null
    if [ "$(cat $BBG_PARAM 2>/dev/null)" = "N" ] || [ "$(cat $BBG_PARAM 2>/dev/null)" = "0" ]; then
        ok "BBG 可关闭 (规格要求)"
        # 恢复
        su -c "echo 1 > $BBG_PARAM" 2>/dev/null
    else
        no "BBG 无法关闭"
    fi
else
    wn "BBG 参数节点不存在 (可能未编译或路径不同)"
fi

echo ""

# ============================================================================
# J. 官方行为抽检 (规格 §6.2)
# ============================================================================
echo "=== J. 官方行为抽检 ==="

# 充电
BATT_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
if [ -n "$BATT_STATUS" ]; then
    info "电池状态: $BATT_STATUS"
    ok "充电节点可读"
else
    wn "电池状态节点不可读"
fi

# 信号
SIGNAL=$(getprop gsm.signalstrength 2>/dev/null || cat /proc/net/wireless 2>/dev/null | tail -1)
if [ -n "$SIGNAL" ]; then
    ok "信号状态可读"
else
    wn "信号状态不可读"
fi

# 指纹 (检查指纹服务)
FP_SERVICE=$(getprop init.svc.fingerprintd 2>/dev/null)
if [ -n "$FP_SERVICE" ]; then
    info "指纹服务: $FP_SERVICE"
    ok "指纹服务存在"
else
    wn "指纹服务状态未知"
fi

echo ""

# ============================================================================
# 汇总
# ============================================================================
echo "========================================"
echo " 验收汇总"
echo "========================================"
echo " PASS: $PASS"
echo " FAIL: $FAIL"
echo " WARN: $WARN"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "存在 FAIL 项, 请检查上方详情"
    exit 1
fi
exit 0
