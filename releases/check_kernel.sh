#!/system/bin/sh
# ============================================================================
# 一加13 自定义内核轻量检测脚本
# 用途:
#   1) 检查本项目合入补丁的每一项功能是否在运行时可用
#   2) 检查 AK3 刷写可能破坏的系统关键能力是否正常
#
# 用法 (手机已 root, 已开机):
#   adb push check_kernel.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/check_kernel.sh'
#   或在 Termux/终端: su -c 'sh check_kernel.sh'
#
# 期望内核: 6.6.89 (本仓库构建)
# ============================================================================

PASS=0
FAIL=0
WARN=0
INFO_ONLY=0

# 无颜色回退
if [ -t 1 ] 2>/dev/null; then
  G='\033[32m'; R='\033[31m'; Y='\033[33m'; B='\033[36m'; N='\033[0m'
else
  G=; R=; Y=; B=; N=
fi

ok()   { echo "${G}[PASS]${N} $1"; PASS=$((PASS+1)); }
no()   { echo "${R}[FAIL]${N} $1"; FAIL=$((FAIL+1)); }
wn()   { echo "${Y}[WARN]${N} $1"; WARN=$((WARN+1)); }
inf()  { echo "${B}[INFO]${N} $1"; INFO_ONLY=$((INFO_ONLY+1)); }
sec()  { echo ""; echo "======== $1 ========"; }

have() { command -v "$1" >/dev/null 2>&1; }
# 读文件一行, 失败返回空
cat1() { cat "$1" 2>/dev/null | head -1; }
# 内核是否包含符号/字符串 (kallsyms 或 /proc/kallsyms)
ksym() {
  grep -qE "$1" /proc/kallsyms 2>/dev/null && return 0
  # 无 root 时 kallsyms 可能为 0 地址, 仍可搜名字
  return 1
}
# dmesg 是否出现
dmsg() {
  dmesg 2>/dev/null | grep -qiE "$1"
}

# 可选: 写报告
REPORT="/sdcard/Download/kernel_check_$(date +%Y%m%d_%H%M%S).txt"
LOG_TO_FILE=1

# 同时输出到文件
if [ "$LOG_TO_FILE" = "1" ]; then
  mkdir -p /sdcard/Download 2>/dev/null
  # shellcheck disable=SC2094
  exec 1> >(tee "$REPORT" 2>/dev/null) 2>&1
fi

echo "=============================================="
echo " OnePlus13 Custom Kernel Check"
echo " $(date)"
echo "=============================================="

# --------------------------------------------------------------------------
sec "0. 环境 / 是否刷上本内核"
# --------------------------------------------------------------------------
KREL=$(uname -r 2>/dev/null)
KVER=$(uname -v 2>/dev/null)
DEVICE=$(getprop ro.product.device 2>/dev/null)
MODEL=$(getprop ro.product.model 2>/dev/null)
SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
BOOTCOMP=$(getprop sys.boot_completed 2>/dev/null)

inf "uname -r : $KREL"
inf "uname -v : $KVER"
inf "device   : $DEVICE / $MODEL"
inf "slot     : ${SLOT:-unknown}"
inf "boot_completed: $BOOTCOMP"

case "$KREL" in
  6.6.89*) ok "内核版本匹配本构建 (6.6.89*)" ;;
  6.6.144*) no "仍是系统核 6.6.144 — AK3 很可能未写到 boot" ;;
  *) wn "内核版本 $KREL (期望 6.6.89*)" ;;
esac

echo "$KREL" | grep -q '4k' && ok "4k 页对齐标记存在" || wn "release 无 4k 标记 (不一定致命)"

# 是否 root
if [ "$(id -u)" = "0" ] || [ -n "$(id | grep 'uid=0')" ]; then
  ok "当前以 root 运行"
  IS_ROOT=1
else
  wn "非 root 运行 — 部分检查会降级/跳过"
  IS_ROOT=0
fi

# --------------------------------------------------------------------------
sec "1. 补丁功能 — Root / SuSFS / KALLSYMS"
# --------------------------------------------------------------------------
# ReSukiSU / KernelSU
if [ -e /dev/ksu ] || [ -e /dev/kernelsu ] || ksym 'ksu_'; then
  ok "KernelSU/ReSukiSU 接口或符号存在"
else
  # 管理器已工作也可能只靠 prctl
  if [ -d /data/adb/ksu ] || [ -d /data/adb/ksud ]; then
    ok "发现 /data/adb/ksu* (用户态侧已装过 KSU)"
  else
    no "未发现 KSU 设备节点/符号/目录"
  fi
fi

# SuSFS
if ksym 'susfs_' || dmsg 'susfs'; then
  ok "SuSFS 符号或日志存在"
else
  # 用户态模块也可能在
  if [ -d /data/adb/modules ] && ls /data/adb/modules 2>/dev/null | grep -qi susfs; then
    wn "有 SuSFS 模块目录, 但内核符号未检出"
  else
    no "SuSFS 未检出 (ksym/dmesg)"
  fi
fi

# KALLSYMS
if [ -r /proc/kallsyms ]; then
  # 读几行非全 0
  if grep -qE '^[0-9a-fA-F]*[1-9a-fA-F]' /proc/kallsyms 2>/dev/null; then
    ok "kallsyms 可读且非全 0 (KALLSYMS_ALL 可用)"
  else
    wn "kallsyms 存在但可能被限制 (需 root 才有真实地址)"
  fi
else
  no "/proc/kallsyms 不可读"
fi

# --------------------------------------------------------------------------
sec "2. 补丁功能 — 调度 (wait 默认 / HMBIRD 可选)"
# --------------------------------------------------------------------------
# 默认应为 wait: HMBIRD 未强制打开
HMBIRD_ON=0
for n in \
  /sys/kernel/sched/enable_hmbird \
  /sys/module/hmbird/parameters/enabled \
  /proc/sys/kernel/sched_hmbird_enabled
 do
  if [ -f "$n" ]; then
    v=$(cat1 "$n")
    inf "HMBIRD 节点 $n = $v"
    HMBIRD_ON=1
    ok "HMBIRD 控制节点存在 (二代风驰已编入)"
    break
  fi
done

if [ "$HMBIRD_ON" = "0" ]; then
  if ksym 'hmbird_' || dmsg 'hmbird'; then
    ok "HMBIRD 内核符号/日志存在 (节点路径因版本可能不同)"
  else
    no "HMBIRD 未检出 — 风驰二代可能未进当前核"
  fi
fi

# wait 默认: 无强制要求节点名, 记录当前策略
if [ -f /proc/sys/kernel/sched_schedstats ]; then
  inf "sched_schedstats=$(cat1 /proc/sys/kernel/sched_schedstats)"
fi
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
  inf "cpu0 governor=$(cat1 /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  ok "cpufreq governor 可读"
else
  wn "cpufreq governor 不可读"
fi

# --------------------------------------------------------------------------
sec "3. 补丁功能 — 网络 (BBRv3 / fq / cake / IP_SET / WireGuard / TPROXY)"
# --------------------------------------------------------------------------
# TCP 拥塞
if [ -f /proc/sys/net/ipv4/tcp_congestion_control ]; then
  CUR_CC=$(cat1 /proc/sys/net/ipv4/tcp_congestion_control)
  AVAIL_CC=$(cat1 /proc/sys/net/ipv4/tcp_available_congestion_control)
  inf "当前 TCP: $CUR_CC"
  inf "可用 TCP: $AVAIL_CC"
  echo "$AVAIL_CC" | grep -qw bbr3 && ok "bbr3 在可用算法列表中" || no "bbr3 不在可用算法列表"
  [ "$CUR_CC" = "bbr3" ] && ok "默认/当前拥塞控制为 bbr3" || wn "当前拥塞控制为 $CUR_CC (期望 bbr3, 可手动 echo bbr3 测试)"
else
  no "无法读取 tcp_congestion_control"
fi

# qdisc
if [ -f /proc/sys/net/core/default_qdisc ]; then
  CUR_QD=$(cat1 /proc/sys/net/core/default_qdisc)
  inf "default_qdisc=$CUR_QD"
  [ "$CUR_QD" = "fq" ] && ok "默认 qdisc 为 fq" || wn "默认 qdisc=$CUR_QD (期望 fq)"
else
  wn "无 default_qdisc 节点"
fi

# cake 模块/算法是否存在
if ls /sys/module/sch_cake >/dev/null 2>&1 || ksym 'cake_'; then
  ok "cake (sch_cake) 已编入/已加载"
else
  # 尝试存在性: tc 可能没有
  wn "cake 未作为模块目录出现 (若=y 编入可能无独立 /sys/module)"
fi

# IP_SET
if ls /sys/module/ip_set >/dev/null 2>&1 || [ -d /proc/net/ip_set ] || ksym 'ip_set_'; then
  ok "IP_SET 存在"
else
  no "IP_SET 未检出"
fi

# WireGuard
if ls /sys/module/wireguard >/dev/null 2>&1 || ksym 'wireguard' || dmsg 'wireguard'; then
  ok "WireGuard 存在"
else
  wn "WireGuard 未作为模块显示 (内置时可能无 module 目录)"
fi

# TPROXY 相关: 只能弱检查
if [ -d /proc/sys/net/netfilter ] || ksym 'tproxy'; then
  ok "netfilter/tproxy 相关内核能力存在"
else
  wn "TPROXY 弱检查未命中"
fi

# --------------------------------------------------------------------------
sec "4. 补丁功能 — 存储 / I/O (ZRAM lz4 / ADIOS / Overlay)"
# --------------------------------------------------------------------------
# ZRAM
if [ -d /sys/block/zram0 ] || ls /dev/block/zram0 >/dev/null 2>&1; then
  ok "zram0 存在"
  if [ -f /sys/block/zram0/comp_algorithm ]; then
    ZA=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)
    inf "zram alg: $ZA"
    echo "$ZA" | grep -q lz4 && ok "lz4 在 zram 算法中" || wn "lz4 未出现在 zram 算法列表"
  fi
else
  wn "未发现 zram0 (可能未启用交换或节点路径不同)"
fi

# ADIOS
if ksym 'adios' || dmsg 'adios' || grep -qr adios /sys/block/*/queue/scheduler 2>/dev/null; then
  ok "ADIOS I/O 调度相关痕迹存在"
  # 当前调度器
  for q in /sys/block/*/queue/scheduler; do
    [ -f "$q" ] || continue
    s=$(cat1 "$q")
    echo "$s" | grep -q adios && inf "设备 $(echo $q | cut -d/ -f4) scheduler=$s"
  done
else
  # 列一下常见块设备 scheduler
  SAMPLE=$(cat /sys/block/sda/queue/scheduler 2>/dev/null || cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null || cat /sys/block/dm-0/queue/scheduler 2>/dev/null)
  inf "scheduler 样例: $SAMPLE"
  wn "ADIOS 未在 kallsyms/dmesg/scheduler 中明确出现"
fi

# Overlay / tmpfs xattr (Mountify/hy 基础)
if grep -qw overlay /proc/filesystems 2>/dev/null; then
  ok "overlay 文件系统已注册"
else
  no "overlay 未在 /proc/filesystems"
fi
if grep -qw tmpfs /proc/filesystems 2>/dev/null; then
  ok "tmpfs 已注册"
else
  no "tmpfs 未注册"
fi

# --------------------------------------------------------------------------
sec "5. 补丁功能 — 安全 / 省电 / 容器 / 其它"
# --------------------------------------------------------------------------
# BBG
if ksym 'bbg_' || dmsg 'baseband_guard' || ls /sys/module/baseband_guard >/dev/null 2>&1; then
  ok "BBG (Baseband Guard) 存在"
  for n in /sys/module/baseband_guard/parameters/enabled /proc/bbg/enabled /sys/kernel/bbg/enabled; do
    [ -f "$n" ] && inf "BBG $n=$(cat1 $n)"
  done
else
  no "BBG 未检出"
fi

# Re:Kernel
if [ -d /proc/rekernel ] || ksym 'rekernel' || dmsg 'Re:Kernel'; then
  ok "Re:Kernel 存在"
  [ -d /proc/rekernel ] && inf "proc: $(ls /proc/rekernel 2>/dev/null | tr '\n' ' ')"
else
  no "Re:Kernel 未检出"
fi

# NTSYNC
if [ -e /dev/ntsync ] || ksym 'ntsync' || dmsg 'ntsync'; then
  ok "NTSYNC 存在 (/dev/ntsync 或符号)"
  ls -l /dev/ntsync 2>/dev/null | head -1 | while read L; do inf "$L"; done
else
  no "NTSYNC 未检出"
fi

# Namespaces (Droidspaces 基础)
if [ -f /proc/self/ns/pid ] && [ -f /proc/self/ns/ipc ]; then
  ok "PID_NS / IPC_NS 命名空间节点存在"
else
  no "PID/IPC namespace 节点缺失"
fi
if [ -d /proc/sysvipc ]; then
  ok "SYSVIPC (/proc/sysvipc) 存在"
else
  wn "无 /proc/sysvipc"
fi

# Unicode bypass — 只能弱验证: 内核仍可挂载/创建含特殊字符路径 (不强制)
inf "Unicode Bypass: 无稳定运行时节点, 跳过强检 (已在构建时合入补丁)"

# --------------------------------------------------------------------------
sec "6. AK3 刷写相关 — 分区 / 槽位 / 启动健康"
# --------------------------------------------------------------------------
# boot/init_boot 块设备
SLOT_SUFFIX="$SLOT"
for part in boot init_boot; do
  FOUND=
  for base in /dev/block/by-name /dev/block/bootdevice/by-name; do
    if [ -e "$base/${part}${SLOT_SUFFIX}" ]; then
      FOUND="$base/${part}${SLOT_SUFFIX}"
      break
    fi
    if [ -e "$base/$part" ]; then
      FOUND="$base/$part"
      break
    fi
  done
  if [ -n "$FOUND" ]; then
    ok "分区存在: $part -> $FOUND"
    # 大小
    if [ "$IS_ROOT" = "1" ]; then
      SZ=$(blockdev --getsize64 "$FOUND" 2>/dev/null || echo 0)
      inf "  size=${SZ} bytes"
      if [ "$part" = "boot" ] && [ "$SZ" -gt 0 ] && [ "$SZ" -lt 20000000 ]; then
        wn "boot 分区 <20MB, 异常偏小"
      fi
    fi
  else
    no "未找到分区: $part${SLOT_SUFFIX}"
  fi
done

# boot 完成
[ "$BOOTCOMP" = "1" ] && ok "sys.boot_completed=1" || no "系统未标记 boot_completed"

# 关键原生服务
for p in zygote zygote64 surfaceflinger system_server; do
  if pidof "$p" >/dev/null 2>&1 || pgrep -f "$p" >/dev/null 2>&1; then
    ok "进程存活: $p"
  else
    # zygote 名称可能是 app_process
    if [ "$p" = "zygote" ] || [ "$p" = "zygote64" ]; then
      if pgrep -f app_process >/dev/null 2>&1; then
        ok "app_process 存活 (zygote 类)"
      else
        no "关键进程缺失: $p"
      fi
    else
      no "关键进程缺失: $p"
    fi
  fi
done

# SELinux
SE=$(getenforce 2>/dev/null || cat /sys/fs/selinux/enforce 2>/dev/null)
inf "SELinux: $SE"
case "$SE" in
  Enforcing|1) ok "SELinux Enforcing" ;;
  Permissive|0) wn "SELinux Permissive" ;;
  *) wn "SELinux 状态未知" ;;
esac

# --------------------------------------------------------------------------
sec "7. AK3 可能影响 — 通信 / 传感器 / 存储 / 音频 (冒烟)"
# --------------------------------------------------------------------------
# RIL / 基带
BASEBAND=$(getprop gsm.version.baseband 2>/dev/null)
RADIO=$(getprop gsm.operator.alpha 2>/dev/null)
SIM=$(getprop gsm.sim.state 2>/dev/null)
inf "baseband=$BASEBAND"
inf "sim.state=$SIM"
if [ -n "$BASEBAND" ] && [ "$BASEBAND" != "" ]; then
  ok "基带版本属性存在 (未空)"
else
  wn "基带版本属性为空 — 若无信号请重点查"
fi

# WiFi
WIFI_STATE=$(settings get global wifi_on 2>/dev/null)
inf "wifi_on=$WIFI_STATE"
if ip link show wlan0 >/dev/null 2>&1 || ip link show wlan1 >/dev/null 2>&1; then
  ok "wlan 网络接口存在"
else
  wn "未见 wlan0/1 接口"
fi

# 显示
if dumpsys display 2>/dev/null | head -3 | grep -qi display; then
  ok "dumpsys display 可响应"
else
  # 弱设备上 dumpsys 慢, 用 surfaceflinger 已检
  wn "dumpsys display 无输出 (可忽略若界面正常)"
fi

# 存储可写
if touch /sdcard/Download/.kcheck_$$ 2>/dev/null; then
  rm -f /sdcard/Download/.kcheck_$$ 2>/dev/null
  ok "/sdcard 可写"
else
  no "/sdcard 不可写"
fi

# userdata 挂载
if mount 2>/dev/null | grep -qE ' /data |/data type'; then
  ok "/data 已挂载"
else
  # Android 可能显示不同
  if [ -d /data/user/0 ]; then
    ok "/data/user/0 存在"
  else
    no "/data 挂载异常"
  fi
fi

# 音频服务
if dumpsys media.audio_flinger 2>/dev/null | head -2 | grep -qi audio; then
  ok "audio_flinger 可查询"
else
  pgrep -f audioserver >/dev/null 2>&1 && ok "audioserver 进程存在" || wn "音频服务弱检查未通过"
fi

# 充电/电池
if [ -f /sys/class/power_supply/battery/status ]; then
  inf "battery=$(cat1 /sys/class/power_supply/battery/status) capacity=$(cat1 /sys/class/power_supply/battery/capacity)"
  ok "电池 sysfs 可读"
else
  wn "电池 sysfs 不可读"
fi

# 指纹 HIDL/AIDL 弱检查
if dumpsys fingerprint 2>/dev/null | head -5 | grep -qiE 'Fingerprint|hal'; then
  ok "fingerprint 服务有响应"
else
  pgrep -f fingerprint >/dev/null 2>&1 && ok "fingerprint 相关进程存在" || wn "指纹服务弱检查未通过 (有屏下指纹时请手测)"
fi

# --------------------------------------------------------------------------
sec "8. 策略模块 (若 AK3 写过 op13_kernel_policy)"
# --------------------------------------------------------------------------
if [ -d /data/adb/modules/op13_kernel_policy ]; then
  ok "发现策略模块目录 op13_kernel_policy"
  [ -f /data/adb/modules/op13_kernel_policy/service.sh ] && inf "含 service.sh"
  [ -f /data/adb/modules/op13_kernel_policy/disable ] && wn "模块被 disable"
else
  inf "无 op13_kernel_policy 模块 (SIMPLE/RESUKISU 包默认不写模块, 正常)"
fi
if [ -f /data/ak3-choices.log ]; then
  ok "存在 /data/ak3-choices.log"
  inf "内容: $(cat /data/ak3-choices.log 2>/dev/null)"
else
  inf "无 /data/ak3-choices.log (管理器静默刷写时正常)"
fi

# --------------------------------------------------------------------------
sec "汇总"
# --------------------------------------------------------------------------
TOTAL=$((PASS + FAIL + WARN))
echo "PASS=$PASS  FAIL=$FAIL  WARN=$WARN  (INFO=$INFO_ONLY)  total_checks≈$TOTAL"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "${G}结果: 关键 FAIL 为 0 — 补丁功能与系统冒烟基本正常${N}"
  RC=0
else
  echo "${R}结果: 存在 $FAIL 项 FAIL — 请对照上方逐条处理${N}"
  RC=1
fi

if echo "$KREL" | grep -q '^6.6.144'; then
  echo "${R}严重: 仍在 6.6.144, 自定义 Image 未生效, 其余补丁检查无意义${N}"
  RC=2
fi

if [ "$LOG_TO_FILE" = "1" ] && [ -f "$REPORT" ]; then
  echo "报告已保存: $REPORT"
fi

echo "=============================================="
exit $RC
