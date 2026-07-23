#!/bin/bash
# Build a ReSukiSU-manager-compatible AK3 zip in the EXACT style of
# working ABK packages (old anykernel property syntax, signed META-INF,
# no module.prop, no interactive menu, no KPM).
set -euo pipefail

IMG=/home/axymorrsen/op13-kernel/src/arch/arm64/boot/Image
WSL=/home/axymorrsen/op13-kernel
WIN=/mnt/d/OnePlus13-kernel
REF_ZIP=/mnt/d/kernel/ABK_OnePlus6_ReSukiSU_SuSFS210_FINAL_FIXED.zip
STAGE=$WSL/release-simple
RELEASE_DIR=$WIN/releases
STAMP=$(date +%Y%m%d-%H%M)

[ -f "$IMG" ] || { echo "FAIL: no Image at $IMG"; exit 1; }
[ -f "$REF_ZIP" ] || { echo "FAIL: no reference zip $REF_ZIP"; exit 1; }

VER=$(strings "$IMG" | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
VER=${VER:-6.6.89}
NAME="v${VER}-OnePlus13-sun-AK3-SIMPLE-${STAMP}"

echo "=== Building $NAME ==="
rm -rf "$STAGE"
mkdir -p "$STAGE/META-INF/com/google/android" "$STAGE/tools" "$RELEASE_DIR"

# 1) Tools + update-binary from a known-good ReSukiSU AK3 zip
REF=$WSL/ref_ak3_extract
rm -rf "$REF"
mkdir -p "$REF"
unzip -q "$REF_ZIP" -d "$REF"
cp -a "$REF/tools/." "$STAGE/tools/"
cp -f "$REF/META-INF/com/google/android/update-binary" "$STAGE/META-INF/com/google/android/"
cp -f "$REF/META-INF/com/google/android/updater-script" "$STAGE/META-INF/com/google/android/"
# Keep jar signing if present (some managers prefer signed zips)
for s in MANIFEST.MF CERT.SF CERT.RSA TESTKEY.SF TESTKEY.RSA; do
  [ -f "$REF/META-INF/$s" ] && cp -f "$REF/META-INF/$s" "$STAGE/META-INF/" || true
done

# 2) Our compiled Image only (never ship module.prop — avoids manager treating as "policy module")
cp -f "$IMG" "$STAGE/Image"
# NO module.prop, NO service.sh in zip root

# 3) Minimal anykernel.sh — same style as working ABK (old property syntax)
#    OnePlus 13 ColorOS: flash init_boot A/B
cat > "$STAGE/anykernel.sh" << 'AK'
# AnyKernel3 Flash Script - OnePlus 13 (sun / SM8750) ColorOS 16
# Compatible with ReSukiSU Manager AnyKernel3 install path
# Style matches working ABK packages (simple, no interactive menu)

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
block=init_boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

ui_print "============================================";
ui_print "  vKERNELVER OnePlus13 sun custom kernel";
ui_print "  ReSukiSU + SuSFS (built-in, no LKM patch)";
ui_print "  target: init_boot (A/B)";
ui_print "============================================";
ui_print "";

# Standard GKI path used by modern AK3
ui_print "- split_boot (init_boot)...";
split_boot;

ui_print "- flash_boot (write Image)...";
flash_boot;

ui_print "";
ui_print "============================================";
ui_print "  Done. Reboot, then check:";
ui_print "  uname -r  -> expect KERNELVER";
ui_print "  If still 6.6.144, Image was NOT written";
ui_print "============================================";
AK

# inject real version strings
sed -i "s/KERNELVER/${VER}/g" "$STAGE/anykernel.sh"
sed -i "s/vKERNELVER/v${VER}/g" "$STAGE/anykernel.sh"

# Unix line endings + exec bits
find "$STAGE" -type f \( -name '*.sh' -o -name 'update-binary' -o -name 'updater-script' \) -exec sed -i 's/\r$//' {} \;
chmod 755 "$STAGE/META-INF/com/google/android/update-binary"
chmod 755 "$STAGE/tools/"* 2>/dev/null || true
chmod 644 "$STAGE/Image"
chmod 644 "$STAGE/anykernel.sh"

# Gates
echo "=== gates ==="
strings "$STAGE/Image" | grep -E 'Linux version' | head -1
strings "$STAGE/Image" | grep -qiE 'kernelsu|susfs' && echo "KSU/SuSFS OK" || echo "WARN: no ksu/susfs strings"
test ! -f "$STAGE/module.prop" && echo "no module.prop OK"
test -f "$STAGE/tools/ak3-core.sh" && echo "ak3-core OK"
test -f "$STAGE/tools/magiskboot" && echo "magiskboot OK"
head -20 "$STAGE/anykernel.sh"

# Zip
ZIP="$RELEASE_DIR/${NAME}.zip"
( cd "$STAGE" && zip -r9 "$ZIP" . )
sha256sum "$ZIP" | tee "${ZIP}.sha256"

# Also ship Image alone
cp -f "$IMG" "$RELEASE_DIR/v${VER}-Image"
sha256sum "$RELEASE_DIR/v${VER}-Image" | tee "$RELEASE_DIR/v${VER}-Image.sha256"

# README for the folder
cat > "$RELEASE_DIR/README.txt" << EOF
一加13 (sun) 自定义内核成品目录
================================

推荐刷写 (ReSukiSU 管理器 / Recovery):
  ${NAME}.zip

内核版本: ${VER}
刷写分区: init_boot (A/B)
Root: Image 已内置 ReSukiSU，不要再用 LKM/修补工具

正确用法:
  1. ReSukiSU 管理器 -> 选择「安装 AnyKernel3 / 刷写本地内核 zip」
  2. 选本目录中的 ${NAME}.zip
  3. 不要走「修补 boot / LKM / 5_15+」入口
  4. 重启后: uname -r  应显示 ${VER}...

若界面仍显示:
  内核版本: 6.6.144  使用修补工具: 5_15+
说明走错了 LKM 修补路径，不是在刷本 zip 的 Image。

生成时间: $(date -Is)
EOF

# Move failure screenshots into releases/_debug if present
mkdir -p "$RELEASE_DIR/_debug"
for f in "$WIN"/626493096104473858*.jpg; do
  [ -f "$f" ] && mv -f "$f" "$RELEASE_DIR/_debug/" && echo "moved $(basename "$f") -> releases/_debug/"
done

# Clean root clutter: move old zips/images/sha256/reports into archive
ARCHIVE=$WIN/releases/_archive_old
mkdir -p "$ARCHIVE"
cd "$WIN"
for f in \
  OnePlus13-*.zip OnePlus13-*.zip.sha256 \
  v6.6.89-*.zip v6.6.89-*.zip.sha256 \
  v6.6.89-Image Image-release \
  BUILD_REPORT.md BUILD_REPORT.txt
 do
  [ -e "$f" ] || continue
  # don't move the releases dir itself
  mv -f "$f" "$ARCHIVE/" 2>/dev/null && echo "archived $f" || true
done

echo
echo "============================================"
echo " RECOMMENDED: $ZIP"
ls -lah "$ZIP"
echo " RELEASE DIR: $RELEASE_DIR"
ls -lah "$RELEASE_DIR"
echo "============================================"
