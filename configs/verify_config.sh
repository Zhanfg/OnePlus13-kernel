#!/bin/bash
# ============================================================================
# 内核配置验证脚本
# 检查编译后的 .config 是否满足规格要求
# ============================================================================

set -euo pipefail

DEFCONFIG="${1:-out/.config}"
PASS=0
FAIL=0

log_pass() { echo -e "\033[32m[PASS]\033[0m $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "\033[31m[FAIL]\033[0m $1"; FAIL=$((FAIL + 1)); }
log_warn() { echo -e "\033[33m[WARN]\033[0m $1"; }
check()      { grep -q "^$1=y" "$DEFCONFIG" 2>/dev/null && log_pass "$1=y" || log_fail "$1=y MISSING"; }

echo "=============================="
echo " Config Verification Report"
echo "=============================="
echo ""

# --- Root / SuSFS ---
echo "[Root / SuSFS]"
check "CONFIG_KALLSYMS"
check "CONFIG_KALLSYMS_ALL"
# KSU/SuSFS 需额外运行时验证
echo ""

# --- hy / Mountify ---
echo "[hy / Mountify]"
check "CONFIG_OVERLAY_FS"
check "CONFIG_TMPFS_XATTR"
check "CONFIG_TMPFS_POSIX_ACL"
echo ""

# --- 网络栈 ---
echo "[Network Stack]"
check "CONFIG_TCP_CONG_BBR"
check "CONFIG_NET_SCH_FQ"
check "CONFIG_NET_SCH_FQ_CODEL"
check "CONFIG_NET_SCH_CAKE"
check "CONFIG_NETFILTER"
check "CONFIG_NF_TPROXY"
check "CONFIG_IP_SET"
check "CONFIG_WIREGUARD"
echo ""

# --- ZRAM ---
echo "[ZRAM]"
check "CONFIG_ZRAM"
check "CONFIG_ZRAM_MULTI_COMP"
check "CONFIG_ZRAM_WRITEBACK"
echo ""

# --- 容器/兼容 ---
echo "[Containers]"
check "CONFIG_PID_NS"
check "CONFIG_IPC_NS"
check "CONFIG_USER_NS"
check "CONFIG_SYSVIPC"
check "CONFIG_POSIX_MQUEUE"
echo ""

# --- Droidspaces ---
echo "[Droidspaces]"
check "CONFIG_PID_NS"
check "CONFIG_IPC_NS"
echo ""

# --- NTSYNC ---
echo "[NTSYNC]"
if grep -q "^CONFIG_NTSYNC=y" "$DEFCONFIG" 2>/dev/null; then
    log_pass "CONFIG_NTSYNC=y"
else
    log_warn "CONFIG_NTSYNC not found (check if patch applied)"
fi
echo ""

# ================================
echo "=============================="
echo " TOTAL: $(($PASS + $FAIL)) checks"
echo " PASSED: $PASS"
echo " FAILED: $FAIL"
echo "=============================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
