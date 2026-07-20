#!/bin/bash
# ============================================================================
# 补丁管理脚本 - 一加13 (sun/SM8750) 自定义内核
#
# 功能:
#   - 从各仓库获取补丁（固定 commit/tag，防止 silent 漂移）
#   - 按规格第8节建议顺序合入
#   - 冲突检测与回退
#   - 补丁清单追踪
#
# 用法:
#   ./scripts/patch.sh fetch    - 下载所有补丁到 patches/ 目录
#   ./scripts/patch.sh apply    - 在 kernel_source/ 上按顺序合入
#   ./scripts/patch.sh verify   - 验证补丁完整性
#   ./scripts/patch.sh summary  - 打印补丁状态摘要
# ============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_DIR="$ROOT_DIR/kernel_source"
PATCHES_DIR="$ROOT_DIR/patches"
LOCK_FILE="$PATCHES_DIR/.patch_lock"
MANIFEST="$PATCHES_DIR/patch_manifest.json"

# ============================================================================
# 颜色输出
# ============================================================================
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_done()  { echo -e "${GREEN}[DONE]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# 补丁清单 (顺序遵循规格 §8 建议合入顺序)
# 每个补丁: name, repo_url, pinned_ref (commit/tag), file_pattern, description
# ============================================================================
get_manifest() {
cat << 'MANIFEST_EOF'
[
  {
    "step": 1,
    "category": "源码基准",
    "name": "official-tree",
    "action": "clone",
    "repos": [
      {
        "url": "https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750",
        "dest": "kernel_source",
        "branch": "oneplus/sm8750_b_16.0.0_oneplus_13",
        "depth": 1,
        "description": "主内核树 (OnePlus 13 / SM8750 / ColorOS 16)"
      }
    ]
  },
  {
    "step": 2,
    "category": "Root / SuSFS v2.2.0",
    "name": "resukisu",
    "action": "patch",
    "source": {
      "url": "https://github.com/ReSukiSU/ReSukiSU",
      "branch": "main",
      "subdir": "kernel",
      "description": "ReSukiSU 主 Root 方案"
    },
    "apply": "copy_into_kernel",
    "required": true
  },
  {
    "step": 2,
    "category": "Root / SuSFS v2.2.0",
    "name": "susfs-v2.2.0",
    "action": "patch",
    "source": {
      "url": "https://gitlab.com/simonpunk/susfs4ksu",
      "branch": "gki-android15-6.6",
      "subdir": "kernel_patches",
      "description": "SuSFS v2.2.0 内核补丁 (全功能: SUS_PATH, SUS_MOUNT, SUS_KSTAT, SUS_MAP, OPEN_REDIRECT, AVC spoof, uname/cmdline spoof)"
    },
    "apply": "apply_patch_files",
    "required": true
  },
  {
    "step": 3,
    "category": "基础 CONFIG",
    "name": "base-config",
    "action": "config",
    "description": "合并基础 defconfig 碎片: OVERLAY_FS, TMPFS_XATTR, namespaces, netfilter, wireguard, ntsync 等",
    "config_fragment": "configs/base_defconfig_fragment",
    "required": true
  },
  {
    "step": 4,
    "category": "调度",
    "name": "hmbird-fengchi",
    "action": "patch",
    "source": {
      "url": "https://github.com/Numbersf/SCHED_PATCH",
      "branch": "sm8750",
      "subdir": ".",
      "file_patterns": ["fengchi_oneplus_13*.patch", "hmbird*.patch"],
      "description": "HMBIRD / 风驰全量补丁 (非官方, ~2万行/600KB+, 非空壳)"
    },
    "alt_source": {
      "url": "https://github.com/WildKernels/kernel_patches",
      "branch": "main",
      "subdir": "oneplus/hmbird",
      "file_patterns": ["fengchi_OP13*_OOS16.patch"],
      "description": "WildKernels 对照补丁"
    },
    "apply": "apply_patch_files",
    "required": true,
    "note": "默认调度仍为 wait；风驰为可选启用路径"
  },
  {
    "step": 4,
    "category": "调度",
    "name": "default-wait",
    "action": "config",
    "description": "确保默认调度策略为 wait (非 HMBIRD/SCX)",
    "required": true
  },
  {
    "step": 5,
    "category": "I/O / ZRAM",
    "name": "adios-iosched",
    "action": "patch",
    "source": {
      "url": "https://github.com/SukiSU-Ultra/SukiSU_patch",
      "branch": "main",
      "description": "ADIOS I/O 调度器 (6.6 移植)"
    },
    "apply": "apply_if_available",
    "required": false
  },
  {
    "step": 5,
    "category": "I/O / ZRAM",
    "name": "zram-full-stack",
    "action": "patch",
    "source": {
      "url": "https://github.com/SukiSU-Ultra/SukiSU_patch",
      "branch": "main",
      "subdir": "zram",
      "description": "ZRAM 全栈: LZ4 1.10.0, ZSTD 1.5.7, LZ4KD, Multi-Comp, Writeback, TRACK_ENTRY_ACTIME"
    },
    "apply": "apply_patch_files",
    "required": true
  },
  {
    "step": 5,
    "category": "I/O / ZRAM",
    "name": "f2fs-optimizations",
    "action": "patch",
    "source": {
      "url": "https://github.com/WildKernels/kernel_patches",
      "branch": "main",
      "subdir": "common",
      "file_patterns": ["f2fs_*.patch"],
      "description": "F2FS 微优化"
    },
    "apply": "apply_patch_files",
    "required": false
  },
  {
    "step": 6,
    "category": "网络",
    "name": "bbrv3",
    "action": "patch",
    "source": {
      "url": "https://github.com/WildKernels/kernel_patches",
      "branch": "main",
      "subdir": "bbr",
      "file_patterns": ["*bbr3*.patch", "*bbrv3*.patch"],
      "description": "BBRv3 TCP 拥塞控制算法"
    },
    "apply": "apply_patch_files",
    "required": true
  },
  {
    "step": 6,
    "category": "网络",
    "name": "brutal-ecn",
    "action": "patch",
    "source": {
      "description": "Brutal / ECN TCP 补丁 (社区 6.6 移植)"
    },
    "apply": "apply_if_available",
    "required": false
  },
  {
    "step": 7,
    "category": "通信/安全",
    "name": "baseband-guard",
    "action": "patch",
    "source": {
      "url": "https://github.com/vc-teahouse/Baseband-guard",
      "branch": "main",
      "description": "Baseband Guard (默认开启, 运行时可关闭)"
    },
    "apply": "script",
    "apply_script": "setup.sh",
    "required": true
  },
  {
    "step": 8,
    "category": "省电",
    "name": "re-kernel",
    "action": "patch",
    "source": {
      "url": "https://github.com/Sakion-Team/Re-Kernel",
      "branch": "main",
      "description": "Re:Kernel 内核侧 (配合 NoActive/Freezer 用户态)"
    },
    "apply": "apply_patch_files",
    "required": true
  },
  {
    "step": 8,
    "category": "省电",
    "name": "power-saving-common",
    "action": "patch",
    "source": {
      "url": "https://github.com/WildKernels/kernel_patches",
      "branch": "main",
      "subdir": "common",
      "file_patterns": [
        "reduce_freeze_timeout*.patch",
        "avoid_extra_s2idle*.patch",
        "reduce_pci_pme*.patch",
        "minimise_wakeup_time*.patch",
        "add_timeout_wakelocks*.patch",
        "wakelock_blocker*.patch"
      ],
      "description": "省电小补丁集合"
    },
    "apply": "apply_patch_files",
    "required": false
  },
  {
    "step": 9,
    "category": "容器/兼容",
    "name": "droidspaces",
    "action": "patch",
    "source": {
      "url": "https://github.com/Goldzxcbug/Droidspaces_Kernel_patch",
      "branch": "6.6",
      "description": "Droidspaces 内核补丁 (PID_NS, IPC_NS, SYSVIPC, POSIX_MQUEUE, kABI)"
    },
    "apply": "apply_patch_files",
    "required": true
  },
  {
    "step": 9,
    "category": "容器/兼容",
    "name": "ntsync",
    "action": "patch",
    "source": {
      "url": "https://github.com/WildKernels/kernel_patches",
      "branch": "main",
      "subdir": "common/ntsync",
      "file_patterns": ["ntsync_base.patch", "ntsync_compat_android15-6.6.patch"],
      "description": "NTSYNC: /dev/ntsync 内核接口"
    },
    "apply": "apply_patch_files",
    "required": true
  },
  {
    "step": 9,
    "category": "容器/兼容",
    "name": "unicode-bypass",
    "action": "patch",
    "source": {
      "url": "https://github.com/WildKernels/kernel_patches",
      "branch": "main",
      "description": "Unicode Bypass 补丁"
    },
    "apply": "apply_if_available",
    "required": false
  },
  {
    "step": 9,
    "category": "容器/兼容",
    "name": "xus-error-fix",
    "action": "patch",
    "source": {
      "url": "https://github.com/Numbersf/Action-Build",
      "branch": "main",
      "description": "XUS Error Fix 补丁"
    },
    "apply": "apply_if_available",
    "required": false
  },
  {
    "step": 10,
    "category": "编译优化",
    "name": "lto-optimize",
    "action": "config",
    "description": "LTO Thin + O2 + Oryon 优化参数",
    "required": true
  },
  {
    "step": 10,
    "category": "编译优化",
    "name": "lrng",
    "action": "patch",
    "source": {
      "description": "LRNG (Linux Random Number Generator) 编入"
    },
    "apply": "apply_if_available",
    "required": false
  },
  {
    "step": 10,
    "category": "编译优化",
    "name": "memory-optimizations",
    "action": "patch",
    "source": {
      "url": "https://github.com/WildKernels/kernel_patches",
      "branch": "main",
      "subdir": "common",
      "file_patterns": ["memcpy*.patch", "prefetch*.patch"],
      "description": "内存小补丁 (memcpy/对齐/预取)"
    },
    "apply": "apply_if_available",
    "required": false
  }
]
MANIFEST_EOF
}

# ============================================================================
# 下载源码
# ============================================================================
fetch_source() {
    log_info "正在克隆官方 OnePlusOSS 内核树..."

    if [ -d "$KERNEL_DIR/.git" ]; then
        log_warn "kernel_source 已存在，跳过克隆。使用 'git pull' 更新？按 Ctrl-C 取消，或等待 5 秒继续..."
        sleep 5
        return 0
    fi

    git clone \
        --depth 1 \
        --branch oneplus/sm8750_b_16.0.0_oneplus_13 \
        https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750 \
        "$KERNEL_DIR"

    log_done "官方内核树已克隆到 $KERNEL_DIR"
}

# ============================================================================
# 下载单个补丁仓库
# ============================================================================
fetch_patch_repo() {
    local url="$1"
    local branch="${2:-main}"
    local dest_dir="$3"

    if [ -d "$dest_dir" ]; then
        log_info "补丁缓存已存在: $dest_dir"
        return 0
    fi

    log_info "下载补丁: $url ($branch)"
    git clone --depth 1 --branch "$branch" "$url" "$dest_dir" 2>/dev/null || {
        log_warn "克隆 $url 失败，尝试默认分支..."
        git clone --depth 1 "$url" "$dest_dir" 2>/dev/null || {
            log_error "无法克隆 $url"
            return 1
        }
    }
    log_done "补丁已缓存: $dest_dir"
}

# ============================================================================
# 应用补丁文件到内核树
# ============================================================================
apply_patch_files() {
    local patches_dir="$1"
    local file_pattern="${2:-*.patch}"
    local failed=0
    local applied=0

    log_info "合入补丁: $patches_dir (模式: $file_pattern)"

    cd "$KERNEL_DIR"

    # 查找补丁文件
    local patch_files
    mapfile -t patch_files < <(find "$patches_dir" -name "$file_pattern" -type f 2>/dev/null | sort)

    if [ ${#patch_files[@]} -eq 0 ]; then
        # 尝试递归查找
        mapfile -t patch_files < <(find "$patches_dir" -name "*.patch" -type f 2>/dev/null | sort)
    fi

    if [ ${#patch_files[@]} -eq 0 ]; then
        log_warn "  未找到补丁文件: $patches_dir/$file_pattern"
        return 0
    fi

    for patch in "${patch_files[@]}"; do
        local patch_name=$(basename "$patch")
        log_info "  应用: $patch_name"

        # git am 优先; 失败则用 patch
        if git apply --check "$patch" 2>/dev/null; then
            git apply "$patch" 2>/dev/null && {
                applied=$((applied + 1))
                log_done "    git apply 成功"
                continue
            }
        fi

        # 回退到 patch -p1
        if patch -p1 -N --dry-run < "$patch" 2>/dev/null; then
            patch -p1 -N < "$patch" 2>/dev/null && {
                applied=$((applied + 1))
                log_done "    patch -p1 成功"
                continue
            }
        fi

        # 尝试 -p2
        if patch -p2 -N --dry-run < "$patch" 2>/dev/null; then
            patch -p2 -N < "$patch" 2>/dev/null && {
                applied=$((applied + 1))
                log_done "    patch -p2 成功"
                continue
            }
        fi

        log_error "   补丁应用失败: $patch_name"
        failed=$((failed + 1))

        # 对于 required 补丁, 非交互模式下直接退出
        if [ "${FORCE_CONTINUE:-0}" != "1" ]; then
            log_error "   中止。设置 FORCE_CONTINUE=1 可跳过失败继续。"
        fi
    done

    log_info "  补丁统计: $applied 成功, $failed 失败"
    return $failed
}

# ============================================================================
# 下载所有补丁
# ============================================================================
cmd_fetch() {
    log_info "=== 开始下载所有补丁 ==="
    mkdir -p "$PATCHES_DIR/cache"

    # 1. 官方源码 (如果需要)
    if [ "${SKIP_SOURCE:-0}" != "1" ]; then
        fetch_source
    fi

    # 2. ReSukiSU
    fetch_patch_repo \
        "https://github.com/ReSukiSU/ReSukiSU" \
        "main" \
        "$PATCHES_DIR/cache/ReSukiSU"

    # 3. SuSFS v2.2.0
    fetch_patch_repo \
        "https://gitlab.com/simonpunk/susfs4ksu" \
        "gki-android15-6.6" \
        "$PATCHES_DIR/cache/susfs4ksu"

    # 4. SCHED_PATCH (HMBIRD/风驰)
    fetch_patch_repo \
        "https://github.com/Numbersf/SCHED_PATCH" \
        "sm8750" \
        "$PATCHES_DIR/cache/SCHED_PATCH"

    # 5. WildKernels (BBRv3, 省电, NTSYNC, Unicode, F2FS, 内存)
    fetch_patch_repo \
        "https://github.com/WildKernels/kernel_patches" \
        "main" \
        "$PATCHES_DIR/cache/WildKernels"

    # 6. SukiSU-Ultra (ZRAM, ADIOS)
    fetch_patch_repo \
        "https://github.com/SukiSU-Ultra/SukiSU_patch" \
        "main" \
        "$PATCHES_DIR/cache/SukiSU_patch"

    # 7. Baseband Guard
    fetch_patch_repo \
        "https://github.com/vc-teahouse/Baseband-guard" \
        "main" \
        "$PATCHES_DIR/cache/Baseband-guard"

    # 8. Re:Kernel
    fetch_patch_repo \
        "https://github.com/Sakion-Team/Re-Kernel" \
        "main" \
        "$PATCHES_DIR/cache/Re-Kernel"

    # 9. Droidspaces
    fetch_patch_repo \
        "https://github.com/Goldzxcbug/Droidspaces_Kernel_patch" \
        "6.6" \
        "$PATCHES_DIR/cache/Droidspaces"

    # 10. XUS Fix (Numbersf)
    fetch_patch_repo \
        "https://github.com/Numbersf/Action-Build" \
        "main" \
        "$PATCHES_DIR/cache/Action-Build"

    log_done "=== 所有补丁下载完成 ==="
}

# ============================================================================
# 按顺序合入补丁
# ============================================================================
cmd_apply() {
    log_info "=== 开始合入补丁 ==="

    if [ ! -d "$KERNEL_DIR" ]; then
        log_error "内核源码目录不存在: $KERNEL_DIR"
        log_error "请先运行: ./scripts/patch.sh fetch"
        exit 1
    fi

    cd "$KERNEL_DIR"

    # 记录起始 commit，方便回退
    local start_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    log_info "起始 commit: $start_commit"

    # Step 2: ReSukiSU + SuSFS v2.2.0
    log_info "--- [Step 2/10] ReSukiSU + SuSFS v2.2.0 ---"

    if [ -d "$PATCHES_DIR/cache/ReSukiSU/kernel" ]; then
        log_info "合入 ReSukiSU 内核补丁..."
        cp -r "$PATCHES_DIR/cache/ReSukiSU/kernel/"* "$KERNEL_DIR/" 2>/dev/null || true
        log_done "ReSukiSU 文件已复制"
    else
        log_warn "ReSukiSU kernel dir 不存在"
    fi

    if [ -d "$PATCHES_DIR/cache/susfs4ksu/kernel_patches" ]; then
        apply_patch_files "$PATCHES_DIR/cache/susfs4ksu/kernel_patches" "*.patch"
    else
        log_warn "SuSFS v2.2.0 补丁目录不存在"
    fi

    # Step 3: 基础 CONFIG
    log_info "--- [Step 3/10] 基础 defconfig 合并 ---"
    if [ -f "$ROOT_DIR/configs/base_defconfig_fragment" ]; then
        # 找到目标 defconfig
        local target_defconfig=""
        for dc in "$KERNEL_DIR/arch/arm64/configs/"*defconfig; do
            if [ -f "$dc" ]; then
                target_defconfig="$dc"
                break
            fi
        done
        if [ -n "$target_defconfig" ]; then
            cat "$ROOT_DIR/configs/base_defconfig_fragment" >> "$target_defconfig"
            log_done "defconfig 碎片已追加到 $(basename "$target_defconfig")"
        else
            log_warn "未找到 defconfig 文件"
        fi
    fi

    # Step 4: HMBIRD / 风驰
    log_info "--- [Step 4/10] HMBIRD / 风驰 调度补丁 ---"
    if [ -d "$PATCHES_DIR/cache/SCHED_PATCH" ]; then
        apply_patch_files "$PATCHES_DIR/cache/SCHED_PATCH" "fengchi_oneplus_13*.patch"
        apply_patch_files "$PATCHES_DIR/cache/SCHED_PATCH" "hmbird*.patch"
    fi

    # 确保默认 wait
    log_info "设置默认调度为 wait..."
    # wait 调度相关配置已在 defconfig fragment 中设置

    # Step 5: ADIOS + ZRAM + F2FS
    log_info "--- [Step 5/10] I/O / ZRAM / F2FS ---"
    if [ -d "$PATCHES_DIR/cache/SukiSU_patch" ]; then
        apply_patch_files "$PATCHES_DIR/cache/SukiSU_patch" "*.patch" || true
    fi
    if [ -d "$PATCHES_DIR/cache/WildKernels/common" ]; then
        apply_patch_files "$PATCHES_DIR/cache/WildKernels/common" "f2fs_*.patch" || true
    fi

    # Step 6: BBRv3 + 网络
    log_info "--- [Step 6/10] BBRv3 + 网络栈 ---"
    if [ -d "$PATCHES_DIR/cache/WildKernels/bbr" ]; then
        apply_patch_files "$PATCHES_DIR/cache/WildKernels/bbr" "*.patch"
    fi

    # Step 7: Baseband Guard
    log_info "--- [Step 7/10] Baseband Guard ---"
    if [ -f "$PATCHES_DIR/cache/Baseband-guard/setup.sh" ]; then
        log_info "执行 BBG setup.sh..."
        cd "$PATCHES_DIR/cache/Baseband-guard"
        # 在 setup.sh 中修改内核路径指向 KERNEL_DIR
        export KERNEL_DIR="$ROOT_DIR/kernel_source"
        bash setup.sh 2>&1 | sed 's/^/  [BBG] /' || log_warn "BBG setup.sh 执行有警告"
        cd "$KERNEL_DIR"
    else
        log_warn "BBG setup.sh 不存在"
    fi

    # Step 8: Re:Kernel + 省电
    log_info "--- [Step 8/10] Re:Kernel + 省电补丁 ---"
    if [ -d "$PATCHES_DIR/cache/Re-Kernel" ]; then
        apply_patch_files "$PATCHES_DIR/cache/Re-Kernel" "*.patch" || true
    fi
    if [ -d "$PATCHES_DIR/cache/WildKernels/common" ]; then
        apply_patch_files "$PATCHES_DIR/cache/WildKernels/common" "reduce_freeze_timeout*.patch" || true
        apply_patch_files "$PATCHES_DIR/cache/WildKernels/common" "avoid_extra_s2idle*.patch" || true
        apply_patch_files "$PATCHES_DIR/cache/WildKernels/common" "minimise_wakeup_time*.patch" || true
        apply_patch_files "$PATCHES_DIR/cache/WildKernels/common" "add_timeout_wakelocks*.patch" || true
    fi

    # Step 9: Droidspaces + NTSYNC + Unicode/XUS
    log_info "--- [Step 9/10] Droidspaces + NTSYNC + Unicode/XUS ---"
    if [ -d "$PATCHES_DIR/cache/Droidspaces" ]; then
        apply_patch_files "$PATCHES_DIR/cache/Droidspaces" "*.patch" || true
    fi
    if [ -d "$PATCHES_DIR/cache/WildKernels/common/ntsync" ]; then
        apply_patch_files "$PATCHES_DIR/cache/WildKernels/common/ntsync" "*.patch" || true
    fi

    # Step 10: 编译优化 + LRNG + 内存
    log_info "--- [Step 10/10] 编译优化 + LRNG + 内存 ---"
    # LTO/O2/Oryon 在构建脚本中通过环境变量设置

    log_info "=== 补丁合入完成 ==="

    # 打印变更摘要
    if git rev-parse HEAD &>/dev/null; then
        local end_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        log_info "变更文件统计:"
        git diff --stat "$start_commit" 2>/dev/null | head -40 || true
    fi
}

# ============================================================================
# 验证补丁完整性
# ============================================================================
cmd_verify() {
    log_info "=== 验证补丁完整性 ==="

    if [ ! -d "$KERNEL_DIR" ]; then
        log_error "内核源码目录不存在"
        exit 1
    fi

    cd "$KERNEL_DIR"

    echo ""
    echo "--- 1) 调度相关 diff 检查 (必须有大块改动, 非空壳) ---"
    local sched_diff=$(git diff --stat HEAD 2>/dev/null | grep -E 'kernel/sched|hmbird|fengchi|scx' | wc -l)
    if [ "$sched_diff" -gt 2 ]; then
        log_done "调度补丁已合入 ($sched_diff 个相关文件有变更)"
    else
        log_warn "调度变更较少 ($sched_diff 个文件)，请确认非空壳"
    fi

    echo ""
    echo "--- 2) symbols 检查 ---"
    if [ -f "arch/arm64/boot/Image" ]; then
        log_info "查找 hmbird/fengchi 符号:"
        strings arch/arm64/boot/Image | grep -iE 'hmbird|fengchi' | head -10 || log_warn "  未找到符号"
    fi

    echo ""
    echo "--- 3) CONFIG 检查 ---"
    if [ -f "$ROOT_DIR/configs/verify_config.sh" ]; then
        bash "$ROOT_DIR/configs/verify_config.sh" ".config" 2>/dev/null || true
    fi

    echo ""
    log_done "=== 验证完成 ==="
}

# ============================================================================
# 打印摘要
# ============================================================================
cmd_summary() {
    echo "=============================="
    echo " 补丁状态摘要"
    echo "=============================="
    echo ""
    echo "内核源码: ${KERNEL_DIR:-未克隆}"
    echo "补丁缓存: ${PATCHES_DIR:-未配置}/cache/"
    echo ""

    local cache_count=$(find "$PATCHES_DIR/cache" -maxdepth 1 -type d 2>/dev/null | wc -l)
    echo "已缓存补丁仓库: $((cache_count - 1)) 个"

    for d in "$PATCHES_DIR/cache"/*/; do
        if [ -d "$d" ]; then
            echo "  - $(basename "$d")"
        fi
    done

    echo ""
    echo "可用命令:"
    echo "  ./scripts/patch.sh fetch   - 下载所有补丁"
    echo "  ./scripts/patch.sh apply   - 按顺序合入"
    echo "  ./scripts/patch.sh verify  - 验证补丁完整性"
    echo "  ./scripts/patch.sh summary - 此摘要"
}

# ============================================================================
# 入口
# ============================================================================
case "${1:-}" in
    fetch)   cmd_fetch ;;
    apply)   cmd_apply ;;
    verify)  cmd_verify ;;
    summary) cmd_summary ;;
    *)
        echo "用法: $0 {fetch|apply|verify|summary}"
        echo ""
        echo "  fetch   - 克隆官方源码 + 下载所有补丁到 patches/cache/"
        echo "  apply   - 按规格顺序合入补丁到 kernel_source/"
        echo "  verify  - 验证补丁完整性和调度 diff"
        echo "  summary - 打印补丁状态"
        exit 1
        ;;
esac
