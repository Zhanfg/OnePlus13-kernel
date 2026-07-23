#!/bin/bash
# Package AnyKernel3 per ReSukiSU manager source + official install docs.
#
# From ReSukiSU manager KernelFlashState.kt:
#   - Flashes via: sh update-binary 3 1 <zip>
#   - Injects mkbootfs (5_10 or 5_15+) into update-binary (log line only;
#     "内核版本/修补工具" is THIS, not LKM install)
#   - Success iff file anykernel3/done is created
#
# From ReSukiSU docs (zh-Hans/guide/install.html):
#   - LKM: patch boot/init_boot/vendor_boot img, then flash img
#   - AnyKernel3: full AK3 zip with Image; manager needs ROOT first
#   - Manual: unpack stock boot.img, replace kernel with Image, repack
#
# GKI OnePlus 13 (SM8750): kernel lives in **boot**, generic ramdisk in init_boot.
# Writing 30MB Image to init_boot WILL FAIL (partition too small / wrong target).
# Correct AK3: block=boot + split_boot + flash_boot (kernel only, skip ramdisk).
#
set -euo pipefail

IMG=/home/axymorrsen/op13-kernel/src/arch/arm64/boot/Image
WSL=/home/axymorrsen/op13-kernel
WIN=/mnt/d/OnePlus13-kernel
RELEASE=$WIN/releases
REF_ZIP=/mnt/d/kernel/ABK_OnePlus6_ReSukiSU_SuSFS210_FINAL_FIXED.zip
STAGE=$WSL/release-resukisu
STAMP=$(date +%Y%m%d-%H%M)

[ -f "$IMG" ] || { echo "no Image"; exit 1; }
[ -f "$REF_ZIP" ] || { echo "no ref zip"; exit 1; }

VER=$(strings "$IMG" | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
VER=${VER:-6.6.89}
NAME="v${VER}-OnePlus13-sun-AK3-RESUKISU-${STAMP}"

echo "=== $NAME ==="
rm -rf "$STAGE"
mkdir -p "$STAGE/META-INF/com/google/android" "$STAGE/tools" "$RELEASE"

# Tools + update-binary from known-good AK3 (must contain: $bb chmod -R 755 tools bin;)
REF=$WSL/ref_ak3
rm -rf "$REF" && mkdir -p "$REF"
unzip -q "$REF_ZIP" -d "$REF"
cp -a "$REF/tools/." "$STAGE/tools/"
cp -f "$REF/META-INF/com/google/android/update-binary" "$STAGE/META-INF/com/google/android/"
cp -f "$REF/META-INF/com/google/android/updater-script" "$STAGE/META-INF/com/google/android/"
for s in MANIFEST.MF TESTKEY.SF TESTKEY.RSA; do
  [ -f "$REF/META-INF/$s" ] && cp -f "$REF/META-INF/$s" "$STAGE/META-INF/" || true
done

# Verify ReSukiSU sed inject target exists
if ! grep -q 'chmod -R 755 tools bin' "$STAGE/META-INF/com/google/android/update-binary"; then
  echo "FATAL: update-binary missing inject line for ReSukiSU mkbootfs"
  exit 1
fi
echo "ReSukiSU inject line OK"

cp -f "$IMG" "$STAGE/Image"
# NEVER put module.prop in zip root (manager would mis-label as policy module)

# anykernel.sh — old property style (works with file_getprop in update-binary)
# boot + split/flash = kernel only (correct for GKI with separate init_boot ramdisk)
cat > "$STAGE/anykernel.sh" << AK
# AnyKernel3 for OnePlus 13 (sun / SM8750) ColorOS 16
# Aligned with ReSukiSU Manager HorizonKernelWorker (AnyKernel3 path)
# Docs: https://resukisu.github.io/zh-Hans/guide/install.html
#   GKI2/GKI1 / Non-GKI: flash AnyKernel3 zip (requires ROOT in manager)
#   LKM is a DIFFERENT path (patch init_boot/boot img) — do NOT use for this zip
#
# Kernel Image goes to **boot** (GKI). init_boot is ramdisk-only on this device.

kernel.string=v${VER} OnePlus13 sun ReSukiSU+SuSFS built-in
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=sun
device.name2=OnePlus13
device.name3=PJZ110
device.name4=OP595DL1
device.name5=OP5F31
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=

# GKI kernel partition = boot (NOT init_boot)
block=boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

ui_print "============================================";
ui_print "  v${VER} OnePlus13 sun custom kernel";
ui_print "  ReSukiSU + SuSFS (built into Image)";
ui_print "  flash: boot (GKI kernel partition)";
ui_print "  ReSukiSU Manager: use AnyKernel3 install";
ui_print "============================================";
ui_print "";

# Kernel-only write: skip ramdisk unpack/repack (init_boot holds ramdisk separately)
ui_print "- split_boot (boot kernel only)...";
split_boot;

ui_print "- flash_boot (write Image to boot)...";
flash_boot;

ui_print "";
ui_print "============================================";
ui_print "  Done! Reboot required.";
ui_print "  uname -r should be ${VER}-...";
ui_print "============================================";
AK

# line endings + perms
find "$STAGE" -type f \( -name '*.sh' -o -name 'update-binary' -o -name 'updater-script' \) -exec sed -i 's/\r$//' {} \;
chmod 755 "$STAGE/META-INF/com/google/android/update-binary" "$STAGE/tools/"* 2>/dev/null || true

# gates
echo "=== gates ==="
strings "$STAGE/Image" | grep -E 'Linux version' | head -1
strings "$STAGE/Image" | grep -qi kernelsu && echo "KSU strings OK"
test ! -f "$STAGE/module.prop" && echo "no module.prop OK"
grep -q 'block=boot' "$STAGE/anykernel.sh" && echo "block=boot OK"
grep -q 'split_boot' "$STAGE/anykernel.sh" && echo "split_boot OK"
grep -q 'flash_boot' "$STAGE/anykernel.sh" && echo "flash_boot OK"
ls -lh "$STAGE/Image"

ZIP="$RELEASE/${NAME}.zip"
( cd "$STAGE" && zip -r9 "$ZIP" . )
sha256sum "$ZIP" | tee "${ZIP}.sha256"
cp -f "$IMG" "$RELEASE/v${VER}-Image"
sha256sum "$RELEASE/v${VER}-Image" | tee "$RELEASE/v${VER}-Image.sha256"

cat > "$RELEASE/README.txt" << EOF
一加13 自定义内核 — 成品目录 (按 ReSukiSU 官方说明打包)
========================================================

【必读】ReSukiSU 官方文档两种安装方式完全不同:

1) LKM 修补/安装
   - 管理器界面会出现: 内核版本 / 使用修补工具 5_15+
   - 作用: 给 **当前系统的 boot/init_boot 镜像** 打 LKM 补丁
   - 输出: KernelSU_patched_*.img 再刷分区
   - **不能** 用来安装本目录的「整包自定义内核 Image」

2) 刷写 AnyKernel3  (本包用途)
   - 管理器: 安装/刷写 → **刷写 AnyKernel3** (horizon_kernel / GKI_install_methods)
   - 需要管理器已有 ROOT (你已是 Built-in, 满足)
   - 本 zip 内含 Image, 由 update-binary 写到 **boot** 分区

文档:
  https://resukisu.github.io/zh-Hans/guide/install.html
  - LKM 安装
  - GKI2/GKI1 / 非 GKI 内核（AnyKernel3）安装

【本次推荐文件】
  ${NAME}.zip

【为什么以前失败】
  1. 错误地把包刷到 init_boot (ramdisk 分区装不下 30MB 内核 Image)
  2. 管理器若走 LKM, 会显示「6.6.144 + 5_15+」——那是读当前手机内核, 不是本包版本
  3. 正确目标: boot + split_boot/flash_boot, 版本应为 ${VER}

【刷写步骤】
  1. 打开 ReSukiSU 管理器
  2. 选「刷写 AnyKernel3 / Flash AnyKernel3」(不是 LKM 修补)
  3. 选本文件: ${NAME}.zip
  4. 重启后: uname -r  应类似 ${VER}-4k-...

生成时间: $(date -Is)
内核: ${VER}
分区: boot (A/B)
EOF

# keep only recommended zip visible; archive older simple/mgr if any
mkdir -p "$RELEASE/_archive_old"
for f in "$RELEASE"/v*-OnePlus13-sun-AK3-SIMPLE-*.zip \
         "$RELEASE"/v*-OnePlus13-sun-AK3-MGR-*.zip \
         "$RELEASE"/v*-OnePlus13-sun-AK3-release-*.zip; do
  [ -e "$f" ] || continue
  mv -f "$f" "$RELEASE/_archive_old/" 2>/dev/null || true
  mv -f "${f}.sha256" "$RELEASE/_archive_old/" 2>/dev/null || true
done

echo
echo "========================================"
echo " RECOMMENDED:"
echo " $ZIP"
ls -lah "$ZIP"
echo "========================================"
ls -lah "$RELEASE"
