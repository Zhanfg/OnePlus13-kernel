#!/bin/bash
# ============================================================================
# 内核构建主脚本 - 一加13 (sun/SM8750) 自定义内核
#
# 功能:
#   - 配置工具链 (Clang + GCC 交叉编译)
#   - 应用 defconfig + 碎片
#   - 编译内核 Image + DTB
#   - 生成 DTC (Device Tree Compiler)
#   - 打包 AnyKernel3 zip
#   - 生成 sha256 校验
#
# 用法:
#   ./build.sh                - 完整构建
#   ./build.sh config         - 仅配置
#   ./build.sh compile        - 仅编译
#   ./build.sh package        - 仅打包 AK3
#   ./build.sh clean          - 清理输出
#   ./build.sh all            - 完整构建 (默认)
#
# 环境变量:
#   KERNEL_DIR     - 内核源码目录 (默认: ./kernel_source)
#   OUT_DIR        - 输出目录 (默认: ./out)
#   ARCH           - 架构 (默认: arm64)
#   CC             - Clang 路径
#   CLANG_VERSION  - Clang 版本 (默认: clang)
#   JOBS           - 编译线程数 (默认: $(nproc))
#   AK3_DIR        - AnyKernel3 目录 (默认: ./anykernel)
# ============================================================================

set -euo pipefail

# ============================================================================
# 颜色输出
# ============================================================================
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_done()    { echo -e "${GREEN}[DONE]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; \
                echo -e "${BLUE} $1${NC}"; \
                echo -e "${BLUE}========================================${NC}\n"; }

# ============================================================================
# 路径与变量
# ============================================================================
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/kernel_source}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"
ARCH="${ARCH:-arm64}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"
AK3_DIR="${AK3_DIR:-$ROOT_DIR/anykernel}"

# 编译工具链
# GitHub Actions 环境使用 Android Clang
CC="${CC:-clang}"
CXX="${CXX:-clang++}"
# 交叉编译器
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CROSS_COMPILE_COMPAT="${CROSS_COMPILE_COMPAT:-arm-linux-gnueabi-}"

# 编译优化参数 (规格 §4.8)
# LTO thin + O2 + Oryon 优化
EXTRA_CFLAGS=""
EXTRA_LDFLAGS=""

# Oryon CPU 优化 (如果工具链支持)
ORYON_CPU="${ORYON_CPU:-}"
if [ -n "$ORYON_CPU" ]; then
    EXTRA_CFLAGS="$EXTRA_CFLAGS -mcpu=$ORYON_CPU"
fi

# 构建 ID
BUILD_ID="sun-custom-$(date +%Y%m%d-%H%M)"
KERNEL_VERSION="sun-custom"

# ============================================================================
# 工具链检测
# ============================================================================
detect_toolchain() {
    log_section "检测编译工具链"

    # 检查 Clang
    if command -v clang &>/dev/null; then
        CLANG_VER=$(clang --version 2>/dev/null | head -1)
        log_done "Clang: $CLANG_VER"
    elif [ -n "${CLANG_PATH:-}" ] && [ -x "$CLANG_PATH" ]; then
        CC="$CLANG_PATH"
        CXX="${CLANG_PATH}++"
        log_done "Clang (自定义路径): $($CC --version 2>/dev/null | head -1)"
    else
        log_error "未找到 Clang 编译器"
        log_error "请安装 Android Clang 或设置 CLANG_PATH 环境变量"
        exit 1
    fi

    # 检查 GCC 交叉编译器
    if command -v aarch64-linux-gnu-gcc &>/dev/null; then
        GCC_VER=$(aarch64-linux-gnu-gcc --version 2>/dev/null | head -1)
        log_done "GCC 交叉编译器: $GCC_VER"
    elif [ -n "${GCC_PATH:-}" ] && [ -x "$GCC_PATH" ]; then
        CROSS_COMPILE="${GCC_PATH%/gcc}"
        log_done "GCC (自定义路径): $GCC_PATH"
    else
        log_warn "未找到 aarch64-linux-gnu-gcc，将尝试使用 Clang 内置"
        CROSS_COMPILE=""
    fi

    # 检查 dtc
    if command -v dtc &>/dev/null; then
        log_done "DTC: $(dtc --version 2>/dev/null | head -1)"
    fi
}

# ============================================================================
# 内核配置
# ============================================================================
configure_kernel() {
    log_section "配置内核"

    if [ ! -d "$KERNEL_DIR" ]; then
        log_error "内核源码目录不存在: $KERNEL_DIR"
        log_error "请先运行: ./scripts/patch.sh fetch && ./scripts/patch.sh apply"
        exit 1
    fi

    cd "$KERNEL_DIR"

    # 查找目标 defconfig
    local target_defconfig=""
    for dc in arch/arm64/configs/*sun*defconfig \
              arch/arm64/configs/*sm8750*defconfig \
              arch/arm64/configs/vendor*_defconfig \
              arch/arm64/configs/*defconfig; do
        if [ -f "$dc" ]; then
            target_defconfig="$dc"
            break
        fi
    done

    if [ -z "$target_defconfig" ]; then
        log_error "未找到 arm64 defconfig 文件"
        exit 1
    fi

    local defconfig_name=$(basename "$target_defconfig" | sed 's/defconfig$//' | sed 's/_$//')
    log_info "使用 defconfig: $defconfig_name"

    # 设置编译环境
    export ARCH
    export CC CXX
    export CROSS_COMPILE CROSS_COMPILE_COMPAT

    # 生成 .config
    log_info "运行 make ${defconfig_name}_defconfig..."
    make O="$OUT_DIR" "$defconfig_name"_defconfig 2>&1 | tail -5

    # 合并自定义碎片
    local fragment="$ROOT_DIR/configs/base_defconfig_fragment"
    if [ -f "$fragment" ]; then
        log_info "合并自定义配置碎片..."
        cp "$fragment" "$OUT_DIR/merge_fragment.config"

        # 使用 scripts/kconfig/merge_config.sh 合并
        if [ -f "$KERNEL_DIR/scripts/kconfig/merge_config.sh" ]; then
            (cd "$OUT_DIR" && bash "$KERNEL_DIR/scripts/kconfig/merge_config.sh" \
                -m -O "$OUT_DIR" \
                .config merge_fragment.config 2>&1) | tail -20
        else
            # 手动合并: 追加并 olddefconfig
            cat "$fragment" >> "$OUT_DIR/.config"
        fi

        log_info "运行 olddefconfig..."
        make O="$OUT_DIR" olddefconfig 2>&1 | tail -5
    fi

    # 确保关键配置项
    log_info "强制设置关键 CONFIG..."
    local force_configs=(
        "CONFIG_KALLSYMS=y"
        "CONFIG_KALLSYMS_ALL=y"
        "CONFIG_OVERLAY_FS=y"
        "CONFIG_TMPFS_XATTR=y"
        "CONFIG_TMPFS_POSIX_ACL=y"
        "CONFIG_ZRAM=y"
        "CONFIG_NET_SCH_FQ=y"
        "CONFIG_NET_SCH_CAKE=y"
        "CONFIG_NET_SCH_FQ_CODEL=y"
        "CONFIG_WIREGUARD=y"
        "CONFIG_PID_NS=y"
        "CONFIG_IPC_NS=y"
        "CONFIG_USER_NS=y"
        "CONFIG_SYSVIPC=y"
        "CONFIG_POSIX_MQUEUE=y"
    )

    for cfg in "${force_configs[@]}"; do
        local key="${cfg%=*}"
        if grep -q "^${key}=" "$OUT_DIR/.config" 2>/dev/null; then
            sed -i "s|^${key}=.*|${cfg}|" "$OUT_DIR/.config"
        elif grep -q "^# ${key} is not set" "$OUT_DIR/.config" 2>/dev/null; then
            sed -i "s|^# ${key} is not set|${cfg}|" "$OUT_DIR/.config"
        else
            echo "$cfg" >> "$OUT_DIR/.config"
        fi
    done

    make O="$OUT_DIR" olddefconfig 2>&1 | tail -5

    # 验证配置
    log_info "验证配置..."
    if [ -f "$ROOT_DIR/configs/verify_config.sh" ]; then
        bash "$ROOT_DIR/configs/verify_config.sh" "$OUT_DIR/.config" || {
            log_warn "配置验证有缺失项，请检查"
        }
    fi

    log_done "内核配置完成: $OUT_DIR/.config"
}

# ============================================================================
# 编译内核
# ============================================================================
compile_kernel() {
    log_section "编译内核"

    if [ ! -f "$OUT_DIR/.config" ]; then
        log_error "未找到 .config，请先运行: ./build.sh config"
        exit 1
    fi

    cd "$KERNEL_DIR"

    export ARCH
    export CC CXX
    export CROSS_COMPILE CROSS_COMPILE_COMPAT

    # 编译参数
    local make_args=(
        "O=$OUT_DIR"
        "ARCH=$ARCH"
        "CC=$CC"
        "CXX=$CXX"
    )

    if [ -n "$CROSS_COMPILE" ]; then
        make_args+=("CROSS_COMPILE=$CROSS_COMPILE")
    fi
    if [ -n "$CROSS_COMPILE_COMPAT" ]; then
        make_args+=("CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT")
    fi

    # LTO Thin (规格 §4.8)
    make_args+=("LTO=thin")

    # 线程数
    make_args+=("-j$JOBS")

    log_info "编译参数: ${make_args[*]}"
    log_info "开始编译 (使用 $JOBS 线程)..."
    log_info "构建 ID: $BUILD_ID"

    # 编译 Image + DTB + 模块
    make "${make_args[@]}" Image dtbs modules 2>&1 | tee "$OUT_DIR/build.log" | tail -50

    # 检查产物
    if [ ! -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
        log_error "编译失败: 未找到 Image"
        log_error "请查看完整日志: $OUT_DIR/build.log"
        exit 1
    fi

    log_done "内核 Image 编译成功"
    log_info "Image: $OUT_DIR/arch/arm64/boot/Image"
    log_info "大小: $(du -h "$OUT_DIR/arch/arm64/boot/Image" | cut -f1)"

    # DTB
    local dtb_found=0
    for dtb in "$OUT_DIR/arch/arm64/boot/dts/"*/*.dtb; do
        if [ -f "$dtb" ]; then
            log_done "DTB: $(basename "$dtb")"
            dtb_found=1
        fi
    done
    if [ "$dtb_found" -eq 0 ]; then
        log_warn "未找到 DTB 文件"
    fi

    # 模块
    if ls "$OUT_DIR"/*.ko &>/dev/null; then
        log_info "编译的模块:"
        find "$OUT_DIR" -name "*.ko" -type f | head -20
    fi
}

# ============================================================================
# 打包 AnyKernel3
# ============================================================================
package_ak3() {
    log_section "打包 AnyKernel3"

    local image="$OUT_DIR/arch/arm64/boot/Image"
    if [ ! -f "$image" ]; then
        log_error "未找到内核 Image: $image"
        exit 1
    fi

    # 准备 AK3 目录
    local ak3_build="$OUT_DIR/anykernel"
    rm -rf "$ak3_build"
    mkdir -p "$ak3_build"

    # 复制 AK3 模板
    cp -r "$AK3_DIR"/* "$ak3_build/" 2>/dev/null || true

    # 复制内核 Image
    cp "$image" "$ak3_build/Image"

    # 复制 DTB (如果存在)
    for dtb in "$OUT_DIR/arch/arm64/boot/dts/"*/*.dtb; do
        if [ -f "$dtb" ]; then
            cp "$dtb" "$ak3_build/" 2>/dev/null || true
        fi
    done

    # 复制模块 (如果有)
    if ls "$OUT_DIR"/*.ko &>/dev/null; then
        mkdir -p "$ak3_build/modules"
        find "$OUT_DIR" -name "*.ko" -exec cp {} "$ak3_build/modules/" \; 2>/dev/null || true
    fi

    # 写入版本信息
    echo "$BUILD_ID" > "$ak3_build/version"

    # 生成 changelog
    generate_changelog "$ak3_build/changelog.txt"

    # 打包 zip
    local zip_name="OnePlus13-sun-custom-${BUILD_ID}.zip"
    cd "$ak3_build"
    zip -r9 "$ROOT_DIR/$zip_name" . -x "*.git*" 2>/dev/null

    cd "$ROOT_DIR"

    # 生成 sha256
    sha256sum "$zip_name" > "${zip_name}.sha256"

    log_done "AK3 打包完成"
    log_info "ZIP: $ROOT_DIR/$zip_name"
    log_info "SHA256: $ROOT_DIR/${zip_name}.sha256"
    log_info "大小: $(du -h "$zip_name" | cut -f1)"

    # 显示 sha256
    echo ""
    log_info "SHA256 校验值:"
    cat "${zip_name}.sha256"
}

# ============================================================================
# 生成 Changelog
# ============================================================================
generate_changelog() {
    local outfile="$1"
    cat > "$outfile" << CHANGELOG_EOF
一加 13 (sun / SM8750) 自定义内核 - $BUILD_ID
================================================

基准:
  - 官方 OnePlusOSS OOS SM8750 内核树
  - ColorOS 16 国行分支
  - 目标机型: 一加 13 (sun)

默认策略:
  - CPU 调度: wait (优化后的 wait, 开机默认)
  - TCP 拥塞控制: bbr3
  - qdisc: fq
  - ZRAM 压缩: lz4
  - Baseband Guard (BBG): 默认开启, 运行时可关闭

功能清单:
  [Root / 隐藏]
  - ReSukiSU (主 Root)
  - SuSFS v2.2.0 全功能 (SUS_PATH/MOUNT/KSTAT/MAP, OPEN_REDIRECT, AVC spoof, uname spoof)
  - KALLSYMS + KALLSYMS_ALL (始终开启)
  - OVERLAY_FS + TMPFS_XATTR + TMPFS_POSIX_ACL (hy/Mountify 支持)

  [调度]
  - 默认: wait
  - HMBIRD / 风驰: 合入 Numbersf/WildKernels 全量补丁 (非官方, 非空壳)
    * 注意: 非官方风驰补丁, 不等于官方完整风驰 1:1
  - SCX: 编入, 与 HMBIRD 共存, 可回退 wait
  - 失败回退: 启用风驰异常时回到 wait

  [I/O / ZRAM]
  - ADIOS I/O 调度器 (可选)
  - ZRAM 全栈: LZ4 1.10.0, ZSTD 1.5.7, LZ4KD, Multi-Comp, Writeback
  - F2FS 微优化
  - 默认 ZRAM 压缩: lz4

  [网络]
  - BBRv3 (默认拥塞控制, 非 bbr)
  - fq (默认 qdisc)
  - cake / fq_codel 可用
  - IP_SET 完整可用
  - TPROXY / REDIRECT / NAT / IPv6 隐私扩展
  - WireGuard 内核接口

  [通信 / 安全]
  - Baseband Guard: 默认开, 可关, 不改基带镜像
  - WiFi 6GHz 协议栈兼容 (区域解锁由模块处理)

  [省电]
  - Re:Kernel (内核侧, 配合 NoActive/Freezer)
  - Wakelock Blocker
  - 省电小补丁: reduce_freeze_timeout, avoid_extra_s2idle, minimise_wakeup_time 等

  [容器 / 兼容]
  - Droidspaces: PID_NS, IPC_NS, SYSVIPC, POSIX_MQUEUE 真实启用
  - NTSYNC: /dev/ntsync
  - Unicode Bypass
  - XUS Error Fix

  [编译优化]
  - LTO Thin + O2
  - Oryon CPU 优化 (-mcpu=oryon-1, 如工具链支持)
  - LRNG (Linux Random Number Generator)

AK3 刷写菜单 (7 题, 音量键选择):
  [1/7] 默认 CPU 调度: wait (推荐) / 风驰 HMBIRD
  [2/7] 默认 TCP: bbr3 (推荐) / cubic
  [3/7] 默认 qdisc: fq (推荐) / fq_codel
  [4/7] 默认 ZRAM: lz4 (推荐) / zstd
  [5/7] Baseband Guard: 开启 (推荐) / 关闭
  [6/7] KPM 补丁: 不应用 (推荐) / 应用
  [7/7] 备份 init_boot: 备份 (推荐) / 跳过

不包含:
  - 杜比解码器 / 杜比音效 blob (由用户安装 KSU 模块)
  - SuSFS 用户态模块 (不进 AK3)
  - KPatch-Next 模块本体 (不进 AK3)
  - 解容 / 激进充电曲线
  - 强改最高亮度 / Improved Haptics
  - 内核强解 WiFi 国家码
  - 基带固件修改

约束:
  - 刷写路径: init_boot (split_boot / flash_boot)
  - A/B 槽位设备
  - 保留官方: 充电 / 信号 / 指纹 / 相机 / 完整音频通路

CHANGELOG_EOF
    log_done "Changelog 已生成: $outfile"
}

# ============================================================================
# 清理
# ============================================================================
cmd_clean() {
    log_section "清理构建输出"
    rm -rf "$OUT_DIR"
    rm -f "$ROOT_DIR"/*.zip "$ROOT_DIR"/*.sha256
    log_done "清理完成"
}

# ============================================================================
# 入口
# ============================================================================
main() {
    local cmd="${1:-all}"

    log_section "一加13 (sun/SM8750) 自定义内核构建"
    log_info "构建 ID: $BUILD_ID"
    log_info "内核源码: $KERNEL_DIR"
    log_info "输出目录: $OUT_DIR"
    log_info "线程数: $JOBS"

    case "$cmd" in
        config)
            detect_toolchain
            configure_kernel
            ;;
        compile)
            detect_toolchain
            compile_kernel
            ;;
        package)
            package_ak3
            ;;
        clean)
            cmd_clean
            ;;
        all|*)
            detect_toolchain
            configure_kernel
            compile_kernel
            package_ak3
            log_section "构建完成"
            log_done "全部步骤完成！"
            ;;
    esac
}

main "$@"
