#!/bin/bash
# ============================================================================
# wsl_build_oki.sh — OnePlus 13 OKI 内核一键构建脚本
# 用途: 从零重建或增量重建 OKI 内核，自动处理 abogki tag、权限等问题
# 用法:
#   bash scripts/wsl_build_oki.sh [clean|full|image]
#     clean  - 清理旧构建产物后完整重建
#     full   - 增量重建（默认）
#     image  - 只打包 AK3（不重建，用现有产物）
#
# 注意: 此脚本必须在 WSL 内执行，因为路径是 WSL 路径。
# ============================================================================

# Safe-mode: don't exit on pipefail for grep commands
set -eo pipefail

OKI=/home/axymorrsen/op13-oki
ACTION="${1:-full}"
STAMP=$(date +%Y%m%d_%H%M)
OUT_WIN=/mnt/d/OnePlus13-kernel/releases

echo "=============================================="
echo "  OnePlus 13 OKI Kernel Builder"
echo "  Action: $ACTION"
echo "  Time:   $(date)"
echo "=============================================="

# --- 0. Check prerequisites ---
if [ ! -d "$OKI" ]; then
    echo "[ERROR] OKI workspace not found at $OKI"
    echo "This script must run inside WSL, not from Windows."
    echo "Run: wsl -d arch-linux-current bash scripts/wsl_build_oki.sh"
    exit 1
fi

# Check essential tools
for tool in strings zip unzip; do
    if ! command -v "$tool" &>/dev/null; then
        echo "[ERROR] Required tool '$tool' not found. Install it first."
        echo "  sudo pacman -S $tool"
        exit 1
    fi
done

echo "  ✅ Tools check passed"

cd "$OKI"

# --- 1. Ensure abogki tag exists ---
echo ""
echo "--- [1] Ensure abogki tag ---"
for repo in common msm-kernel; do
    cd "$OKI/kernel_platform/$repo"
    if ! git tag --points-at HEAD 2>/dev/null | grep -q abogki; then
        echo "  Creating abogki500782043 tag on $repo..."
        git tag -f abogki500782043 HEAD
    else
        echo "  ✅ abogki tag exists on $repo"
    fi
    cd "$OKI"  # Return to OKI root after each repo
done

# Ensure we're in OKI root
cd "$OKI"

# --- 2. WSL optimization ---
echo ""
echo "--- [2] WSL optimization ---"
# Set swappiness low for build performance
if [ -w /proc/sys/vm/swappiness ]; then
    echo 10 > /proc/sys/vm/swappiness 2>/dev/null && echo "  ✅ swappiness=10" || true
fi
# Optimize dirty cache ratios
if [ -w /proc/sys/vm/dirty_ratio ]; then
    echo 20 > /proc/sys/vm/dirty_ratio 2>/dev/null || true
fi
if [ -w /proc/sys/vm/dirty_background_ratio ]; then
    echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null || true
fi
echo "  ✅ VM tuned for build performance"

# --- 3. Fix bazel cache permissions ---
echo ""
echo "--- [3] Fix bazel cache permissions ---"
mkdir -p "$OKI/kernel_platform/out/bazel/output_user_root"
chmod 755 "$OKI/kernel_platform/out/bazel" "$OKI/kernel_platform/out/bazel/output_user_root" 2>/dev/null || true
echo "  ✅ Bazel cache ready"

# --- 4. Ensure output directories exist ---
echo ""
echo "--- [4] Ensure output directories ---"
mkdir -p "$OKI/out/target/product/sun"
mkdir -p "$OKI/kernel_platform/out/msm-kernel-sun-perf/dist"
echo "  ✅ Output dirs ready"

# --- 5. Handle clean build ---
if [ "$ACTION" = "clean" ]; then
    echo ""
    echo "--- [5] Clean build artifacts ---"
    rm -rf "$OKI/kernel_platform/out/msm-kernel-sun-perf"
    rm -rf "$OKI/kernel_platform/out/bazel/output_user_root"
    mkdir -p "$OKI/kernel_platform/out/msm-kernel-sun-perf/dist"
    mkdir -p "$OKI/kernel_platform/out/bazel/output_user_root"
    echo "  ✅ Cleaned, ready for full rebuild"
fi

# --- 6. Run the build ---
if [ "$ACTION" = "image" ]; then
    echo ""
    echo "--- [6] Skip build, package existing ---"
    # Just verify existing artifacts
    if [ -f "$OKI/out/dist/Image" ]; then
        echo "  ✅ Existing Image found: $(ls -lh $OKI/out/dist/Image | awk '{print $5}')"
    else
        echo "  ❌ No existing Image found. Run 'full' first."
        exit 1
    fi
else
    echo ""
    echo "--- [6] Building OKI kernel (sun perf) ---"
    echo "  This will take 30-60 minutes on first build..."
    echo "  Log: $OKI/build_oki_$STAMP.log"
    set +e
    ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf 2>&1 | tee "$OKI/build_oki_$STAMP.log"
    BUILD_RC=${PIPESTATUS[0]}
    set -e
    
    if [ $BUILD_RC -ne 0 ]; then
        echo ""
        echo "  ❌ Build failed (rc=$BUILD_RC)"
        echo "  Last 30 lines of log:"
        tail -30 "$OKI/build_oki_$STAMP.log"
        exit $BUILD_RC
    fi
    echo "  ✅ Build succeeded!"
fi

# --- 7. Verify version string ---
echo ""
echo "--- [6] Verify kernel version ---"
if [ -f "$OKI/out/dist/Image" ]; then
    VER_STR=$(strings "$OKI/out/dist/Image" | grep -E "Linux version 6\\.6" | head -1)
    echo "  Version: $VER_STR"
    if echo "$VER_STR" | grep -q "abogki"; then
        echo "  ✅ abogki tag present!"
    else
        echo "  ⚠️  abogki tag NOT in version string"
    fi
else
    echo "  ❌ Image not found at $OKI/out/dist/Image"
    exit 1
fi

# --- 8. Pack AK3 ---
echo ""
echo "--- [7] Pack AK3 zip ---"
AK3_REF_ZIP="/mnt/d/OnePlus13-kernel/releases/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip"
STAGE="$OKI/ak3-stage-$STAMP"
mkdir -p "$STAGE"

# Use reference AK3 zip as template
if [ -f "$AK3_REF_ZIP" ]; then
    unzip -q -o "$AK3_REF_ZIP" -d "$STAGE" 2>/dev/null
    echo "  ✅ AK3 template extracted from reference"
else
    # Fallback: try the temp dir
    AK3_TEMPLATE="/mnt/d/OnePlus13-kernel/releases/_tmp_ak144_check"
    if [ -d "$AK3_TEMPLATE" ]; then
        cp -r "$AK3_TEMPLATE/"* "$STAGE/"
        echo "  ⚠️  Using temp directory as fallback"
    else
        echo "  ❌ No AK3 template found"
        exit 1
    fi
fi

# Replace Image
cp -f "$OKI/out/dist/Image" "$STAGE/Image"

# Also copy vendor_boot.img if available
if [ -f "$OKI/out/dist/vendor_boot.img" ]; then
    cp -f "$OKI/out/dist/vendor_boot.img" "$STAGE/vendor_boot.img"
    echo "  ✅ vendor_boot.img included"
    # Modify anykernel.sh to flash vendor_boot
    # Insert AFTER split_boot (only in the if branch, NOT in write_boot which already handles it)
    sed -i '/^    split_boot/a\    ui_print " "\n    ui_print "[→] Flashing vendor_boot.img..."\n    ui_print "[→] 正在刷入 vendor_boot 分区..."\n    flash_generic vendor_boot' "$STAGE/anykernel.sh"
fi

# Update kernel.string
VER_SHORT=$(echo "$VER_STR" | grep -oE '6\.[0-9]+\.[0-9]+' | head -1)
sed -i "s/kernel.string=.*/kernel.string=v${VER_SHORT} OKI by Zhanfg/" "$STAGE/anykernel.sh"

# Fix line endings (CRLF -> LF)
find "$STAGE" -name '*.sh' -o -name 'update-binary' | while read f; do
    sed -i 's/\r$//' "$f" 2>/dev/null || true
done

# Set executable permissions
chmod 755 "$STAGE/META-INF/com/google/android/update-binary" "$STAGE/tools/"* 2>/dev/null || true

# Create zip
ZIP_NAME="v${VER_SHORT}-OnePlus13-sun-AK3-OKI-${STAMP}.zip"
ZIP_PATH="$OUT_WIN/$ZIP_NAME"
(cd "$STAGE" && zip -r9 "$ZIP_PATH" .)
if [ $? -eq 0 ]; then
    echo "  ✅ Zip created"
else
    echo "  ❌ Zip creation failed"
    rm -rf "$STAGE"
    exit 1
fi
sha256sum "$ZIP_PATH" > "$ZIP_PATH.sha256"
rm -rf "$STAGE"

echo "  ✅ AK3 created: $ZIP_NAME"
echo "  Size: $(ls -lh $ZIP_PATH | awk '{print $5}')"

echo ""
echo "=============================================="
echo "  ✅ Build complete!"
echo "  File: $ZIP_NAME"
echo "=============================================="
