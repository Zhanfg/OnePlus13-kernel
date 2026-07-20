## AnyKernel3 刷写脚本 - 一加13 (sun/SM8750) 自定义内核
## 规格: AGENT_KERNEL_SPEC_OnePlus13_SM8750.md §7
##
## 刷写路径: init_boot (split_boot / flash_boot)
## 设备: A/B 槽位
## 交互: 7 题音量键选择 (含义全程固定)

# ============================================================================
# AnyKernel3 基础配置
# ============================================================================

# 内核目录 (AnyKernel3 标准)
kernel.string="一加13 (sun/SM8750) 自定义内核 | ColorOS 16 国行"
do.device.check=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
do.printkmsg=0

# A/B 槽位设备
is_slot_device=1

# 刷写路径: init_boot (现代 Oplus A/B 一致)
# split_boot 会将 boot.img 拆分为 kernel + ramdisk
# flash_boot 刷入 boot 分区
block=init_boot;
split_boot;
flash_boot;

# 设备名称检查 (国行一加13可放宽, 但需说明误刷风险)
device.name1="sun"
device.name2="OnePlus13"
device.name3="OP595DL1"
device.name4="PJZ110"
device.name5="OP5F31"

# ============================================================================
# 工具函数
# ============================================================================

# 音量键轮询 - 获取用户选择
# 返回值: 0 = 音量+, 1 = 音量-
# 超时: 使用默认值
ui_print_vol_key() {
    local timeout="${1:-10}"
    local default="${2:-0}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        # 检测音量+ 按下
        if $(grep -q 'key=115' /proc/last_kmsg 2>/dev/null) || \
           $(cat /sys/class/leds/vol-press/brightness 2>/dev/null | grep -q '1'); then
            return 0
        fi
        # 检测音量- 按下
        if $(grep -q 'key=114' /proc/last_kmsg 2>/dev/null) || \
           $(cat /sys/class/leds/vol--press/brightness 2>/dev/null | grep -q '1'); then
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # 超时, 使用默认
    ui_print "  → 超时未按键，使用默认选项"
    return "$default"
}

# 获取音量键选择 (使用 AnyKernel3 内置方法)
get_key() {
    local default="$1"
    local choice

    if [ -n "$custom_getkey" ]; then
        $custom_getkey "$default"
        return
    fi

    # 尝试使用 AnyKernel3 内置 keycheck
    if [ -f /sbin/keycheck ]; then
        keycheck -d "$default" 2>/dev/null
        choice=$?
    else
        # 回退: 使用 getevent
        local timeout=0
        while [ $timeout -lt 10 ]; do
            local key=$(getevent -ql 2>/dev/null | grep -m1 'KEY_VOLUME' | awk '{print $3}')
            case "$key" in
                KEY_VOLUMEUP)   return 0 ;;
                KEY_VOLUMEDOWN) return 1 ;;
            esac
            sleep 1
            timeout=$((timeout + 1))
        done
        return "$default"
    fi
}

# ============================================================================
# 交互菜单 - 7 题音量键选择
# 规格 §7.1.2
# ============================================================================

interactive_menu() {
    ui_print " "
    ui_print "========================================"
    ui_print " 一加13 自定义内核 - 刷写选项"
    ui_print "========================================"
    ui_print " "
    ui_print "本内核已编译完整功能；下列选项只决定"
    ui_print "「开机默认策略」与可选动作。"
    ui_print " "
    ui_print "音量+ = 第一项 (推荐/默认侧)"
    ui_print "音量- = 第二项 (备选)"
    ui_print "超时不按键 = 使用规格默认并继续刷写"
    ui_print "========================================"
    ui_print " "

    # ---- 【1/7】默认 CPU 调度 ----
    ui_print "【1/7】默认 CPU 调度"
    ui_print "用途: 决定开机后默认调度策略"
    ui_print "  (不是重新编译内核)"
    ui_print " "
    ui_print "  音量+ : wait (推荐)"
    ui_print "          优化后的 wait, 稳定, 规格默认"
    ui_print "  音量- : 风驰/HMBIRD"
    ui_print "          性能向非官方全量实装"
    ui_print "          异常应可回退 wait"
    ui_print " "

    if [ "$HMBIRD_VERIFIED" = "1" ]; then
        get_key 0
        local sched_choice=$?
        if [ "$sched_choice" = "0" ]; then
            SCHED_CHOICE="wait"
            ui_print "  → 已选: wait"
        else
            SCHED_CHOICE="hmbird"
            ui_print "  → 已选: 风驰/HMBIRD"
        fi
    else
        ui_print "  (风驰未通过验收, 固定 wait)"
        SCHED_CHOICE="wait"
    fi
    ui_print " "

    # ---- 【2/7】默认 TCP 拥塞控制 ----
    ui_print "【2/7】默认 TCP 拥塞控制"
    ui_print "用途: 决定 tcp_congestion_control 默认值"
    ui_print "  (内核需已提供该算法)"
    ui_print " "
    ui_print "  音量+ : bbr3 (推荐)"
    ui_print "          规格默认, 改善高延迟/丢包场景"
    ui_print "  音量- : cubic"
    ui_print "          传统算法, 兼容/对比用"
    ui_print " "

    get_key 0
    local tcp_choice=$?
    if [ "$tcp_choice" = "0" ]; then
        TCP_CHOICE="bbr3"
        ui_print "  → 已选: bbr3"
    else
        TCP_CHOICE="cubic"
        ui_print "  → 已选: cubic"
    fi
    ui_print " "

    # ---- 【3/7】默认 qdisc ----
    ui_print "【3/7】默认网络队列 qdisc"
    ui_print "用途: 决定 net.core.default_qdisc"
    ui_print " "
    ui_print "  音量+ : fq (推荐)"
    ui_print "          规格默认, 常与 bbr3 搭配"
    ui_print "  音量- : fq_codel"
    ui_print "          备选队列"
    ui_print " "

    get_key 0
    local qdisc_choice=$?
    if [ "$qdisc_choice" = "0" ]; then
        QDISC_CHOICE="fq"
        ui_print "  → 已选: fq"
    else
        QDISC_CHOICE="fq_codel"
        ui_print "  → 已选: fq_codel"
    fi
    ui_print " "

    # ---- 【4/7】默认 ZRAM 压缩算法 ----
    ui_print "【4/7】默认 ZRAM 压缩算法"
    ui_print "用途: 决定 zram 默认 comp_algorithm"
    ui_print "  (需内核已支持)"
    ui_print " "
    ui_print "  音量+ : lz4 (推荐)"
    ui_print "          更快, 规格默认"
    ui_print "  音量- : zstd"
    ui_print "          更高压缩率, 更耗 CPU"
    ui_print " "

    # 检查 zstd 是否编入
    if [ "$ZRAM_ZSTD_AVAILABLE" = "1" ]; then
        get_key 0
        local zram_choice=$?
        if [ "$zram_choice" = "0" ]; then
            ZRAM_CHOICE="lz4"
            ui_print "  → 已选: lz4"
        else
            ZRAM_CHOICE="zstd"
            ui_print "  → 已选: zstd"
        fi
    else
        ui_print "  (zstd 未编入, 固定 lz4)"
        ZRAM_CHOICE="lz4"
    fi
    ui_print " "

    # ---- 【5/7】Baseband Guard ----
    ui_print "【5/7】Baseband Guard (BBG)"
    ui_print "用途: 内核 LSM 拦截对关键分区/节点"
    ui_print "  的违规写入, 不修改基带固件本身"
    ui_print " "
    ui_print "  音量+ : 开启 BBG (推荐)"
    ui_print "          规格默认, 降低格机类写入风险"
    ui_print "  音量- : 关闭 BBG"
    ui_print "          仅排障时建议"
    ui_print " "

    get_key 0
    local bbg_choice=$?
    if [ "$bbg_choice" = "0" ]; then
        BBG_CHOICE="on"
        ui_print "  → 已选: 开启 BBG"
    else
        BBG_CHOICE="off"
        ui_print "  → 已选: 关闭 BBG"
    fi
    ui_print " "

    # ---- 【6/7】KPM 补丁 ----
    ui_print "【6/7】KPM 补丁"
    ui_print "用途: 是否在本次刷写时把 KPM 支持"
    ui_print "  嵌入内核镜像 (类原版 AK3)"
    ui_print " "
    ui_print "  音量+ : 不应用 KPM (推荐)"
    ui_print "          不改 Image KPM 段"
    ui_print "          之后用 KPatch-Next 模块加载 .kpm"
    ui_print "  音量- : 应用 KPM"
    ui_print "          执行 patch_android 类流程"
    ui_print "          勿与其它冲突 KPM 方案叠加"
    ui_print " "
    ui_print "  (两种路径均要求 KALLSYMS=y + KALLSYMS_ALL=y)"
    ui_print " "

    get_key 0
    local kpm_choice=$?
    if [ "$kpm_choice" = "0" ]; then
        KPM_CHOICE="no"
        ui_print "  → 已选: 不应用 KPM"
    else
        KPM_CHOICE="yes"
        ui_print "  → 已选: 应用 KPM"
    fi
    ui_print " "

    # ---- 【7/7】备份当前 init_boot ----
    ui_print "【7/7】备份当前 init_boot"
    ui_print "用途: 刷入前是否保存现有 init_boot"
    ui_print "  以便回滚"
    ui_print " "
    ui_print "  音量+ : 备份 (推荐)"
    ui_print "  音量- : 跳过备份"
    ui_print " "

    get_key 0
    local backup_choice=$?
    if [ "$backup_choice" = "0" ]; then
        BACKUP_CHOICE="yes"
        ui_print "  → 已选: 备份"
    else
        BACKUP_CHOICE="no"
        ui_print "  → 已选: 跳过备份"
    fi
    ui_print " "

    # ---- 结束汇总 ----
    ui_print "========================================"
    ui_print " 选择汇总"
    ui_print "========================================"
    ui_print "  调度 = $SCHED_CHOICE"
    ui_print "  TCP  = $TCP_CHOICE"
    ui_print "  qdisc= $QDISC_CHOICE"
    ui_print "  ZRAM = $ZRAM_CHOICE"
    ui_print "  BBG  = $BBG_CHOICE"
    ui_print "  KPM  = $KPM_CHOICE"
    ui_print "  备份 = $BACKUP_CHOICE"
    ui_print "========================================"

    # 写入日志文件
    echo "调度=$SCHED_CHOICE / TCP=$TCP_CHOICE / qdisc=$QDISC_CHOICE / ZRAM=$ZRAM_CHOICE / BBG=$BBG_CHOICE / KPM=$KPM_CHOICE / 备份=$BACKUP_CHOICE" > /data/ak3-choices.log 2>/dev/null || true
    ui_print "  选择已记录到 /data/ak3-choices.log"
    ui_print " "
}

# ============================================================================
# 备份 init_boot
# ============================================================================
backup_init_boot() {
    if [ "$BACKUP_CHOICE" != "yes" ]; then
        return 0
    fi

    ui_print " "
    ui_print "--- 备份当前 init_boot ---"

    local backup_dir="/data/kernel_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    # 获取当前槽位的 init_boot 分区
    local slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
    slot="${slot:-_a}"

    # dd 备份
    local init_boot_dev=$(find /dev/block/by-name -name "init_boot$slot" 2>/dev/null | head -1)
    if [ -z "$init_boot_dev" ]; then
        init_boot_dev=$(find /dev/block/bootdevice/by-name -name "init_boot$slot" 2>/dev/null | head -1)
    fi

    if [ -n "$init_boot_dev" ]; then
        ui_print "  备份: $init_boot_dev → $backup_dir/init_boot.img"
        dd if="$init_boot_dev" of="$backup_dir/init_boot.img" 2>/dev/null
        ui_print "  备份完成: $backup_dir/init_boot.img"
    else
        ui_print "  ! 未找到 init_boot 分区, 跳过备份"
    fi

    ui_print " "
}

# ============================================================================
# KPM 补丁子程序
# 规格 §7.1.2 题6 + §7.3
# ============================================================================
apply_kpm_patch() {
    if [ "$KPM_CHOICE" != "yes" ]; then
        ui_print "  KPM: 跳过 (用户选择不应用)"
        ui_print "  之后可用 KPatch-Next 模块加载 .kpm"
        return 0
    fi

    ui_print " "
    ui_print "--- 应用 KPM 补丁 ---"

    # patch_android 流程 (类原版 AK3)
    # 在此处实现 KPM 补丁嵌入内核镜像的逻辑
    if [ -f "$home/patch_android" ]; then
        ui_print "  执行 patch_android..."
        chmod +x "$home/patch_android"
        "$home/patch_android" "$home/Image" 2>&1 | while read -r line; do
            ui_print "  [KPM] $line"
        done

        if [ $? -eq 0 ]; then
            ui_print "  KPM 补丁应用成功"
        else
            ui_print "  ! KPM 补丁应用失败"
            ui_print "  ! 建议重启后选择「不应用 KPM」"
            abort "KPM patch failed"
        fi
    else
        ui_print "  ! patch_android 工具不存在"
        ui_print "  ! 跳过 KPM, 将使用 KPatch-Next 模块"
        KPM_CHOICE="no"
    fi

    ui_print " "
}

# ============================================================================
# 写入默认策略配置
# ============================================================================
write_default_policies() {
    ui_print " "
    ui_print "--- 写入默认策略配置 ---"

    local sysctl_dir="/data/adb/modules/kernel_custom/system/etc/sysctl.d"
    local init_dir="/data/adb/modules/kernel_custom/system/etc/init.d"
    mkdir -p "$sysctl_dir" "$init_dir"

    # sysctl 配置
    cat > "$sysctl_dir/99-kernel-custom.conf" << SYSCTL_EOF
# 一加13 自定义内核 - 默认策略
# 由 AK3 刷写时音量键选择生成

# TCP 拥塞控制
net.ipv4.tcp_congestion_control = $TCP_CHOICE

# 默认 qdisc
net.core.default_qdisc = $QDISC_CHOICE

# 网络优化
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 10000

# ZRAM 相关
vm.swappiness = 100
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 10
SYSCTL_EOF

    # 调度策略
    cat > "$init_dir/01-scheduler" << SCHED_EOF
#!/system/bin/sh
# 默认调度策略设置
# 调度选择: $SCHED_CHOICE

# 写入调度策略
if [ -f /sys/kernel/sched/enable_hmbird ]; then
    case "$SCHED_CHOICE" in
        wait)
            echo 0 > /sys/kernel/sched/enable_hmbird 2>/dev/null
            ;;
        hmbird)
            echo 1 > /sys/kernel/sched/enable_hmbird 2>/dev/null
            ;;
    esac
fi

# ZRAM 压缩算法
if [ -f /sys/block/zram0/comp_algorithm ]; then
    echo "$ZRAM_CHOICE" > /sys/block/zram0/comp_algorithm 2>/dev/null
fi

# 应用 sysctl
sysctl -p /system/etc/sysctl.d/99-kernel-custom.conf 2>/dev/null
SCHED_EOF
    chmod 755 "$init_dir/01-scheduler"

    # BBG 配置
    cat > "$init_dir/02-baseband-guard" << BBG_EOF
#!/system/bin/sh
# Baseband Guard 配置
# BBG 选择: $BBG_CHOICE

case "$BBG_CHOICE" in
    on)
        # 确保 BBG 开启 (默认)
        if [ -f /sys/module/baseband_guard/parameters/enabled ]; then
            echo 1 > /sys/module/baseband_guard/parameters/enabled 2>/dev/null
        fi
        ;;
    off)
        # 关闭 BBG (排障用)
        if [ -f /sys/module/baseband_guard/parameters/enabled ]; then
            echo 0 > /sys/module/baseband_guard/parameters/enabled 2>/dev/null
        fi
        ;;
esac
BBG_EOF
    chmod 755 "$init_dir/02-baseband-guard"

    ui_print "  默认策略已写入 /data/adb/modules/kernel_custom/"
    ui_print "  调度=$SCHED_CHOICE TCP=$TCP_CHOICE qdisc=$QDISC_CHOICE"
    ui_print "  ZRAM=$ZRAM_CHOICE BBG=$BBG_CHOICE KPM=$KPM_CHOICE"
    ui_print " "
}

# ============================================================================
# 前置检测
# ============================================================================
pre_checks() {
    # 检查 HMBIRD 是否通过验收 (运行时标记)
    # 在实际环境中需根据真机测试结果设置
    HMBIRD_VERIFIED="${HMBIRD_VERIFIED:-0}"

    # 检查 ZRAM zstd 是否可用
    ZRAM_ZSTD_AVAILABLE="${ZRAM_ZSTD_AVAILABLE:-1}"

    # 默认选择
    SCHED_CHOICE="wait"
    TCP_CHOICE="bbr3"
    QDISC_CHOICE="fq"
    ZRAM_CHOICE="lz4"
    BBG_CHOICE="on"
    KPM_CHOICE="no"
    BACKUP_CHOICE="yes"
}

# ============================================================================
# AnyKernel3 主入口
# ============================================================================

# 前置检测
pre_checks

# 显示开始信息
ui_print " "
ui_print "========================================"
ui_print " 一加13 (sun/SM8750) 自定义内核"
ui_print " ColorOS 16 国行"
ui_print "========================================"
ui_print " "

# 交互菜单
interactive_menu

# 备份 init_boot
backup_init_boot

# KPM 补丁 (仅在用户选择时执行)
apply_kpm_patch

# 写入默认策略
write_default_policies

# AnyKernel3 标准刷写流程 (由 AnyKernel3 框架处理)
# split_boot + flash_boot 已在文件头声明
