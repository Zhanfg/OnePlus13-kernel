#!/bin/bash
set -euo pipefail
SRC=/home/axymorrsen/op13-kernel/src
OUT=/home/axymorrsen/op13-kernel
AK3_REPO=/mnt/d/OnePlus13-kernel/anykernel
AK3_TMP=$OUT/ak3-custom
cd "$SRC"

echo "=== Image ==="
ls -la arch/arm64/boot/Image
file arch/arm64/boot/Image || true
du -h arch/arm64/boot/Image

echo "=== Key configs ==="
grep -E 'DEFAULT_TCP_CONG|ZRAM_DEF_COMP=|CONFIG_BBG=|CONFIG_KSU=|CONFIG_HMBIRD|CONFIG_NTSYNC|CONFIG_REKERNEL|KALLSYMS_ALL|CONFIG_KASAN=|DEFAULT_BBR3|CONFIG_KSU_SUSFS=|TCP_CONG_BBR3|NET_SCH_FQ=|OVERLAY_FS=' .config || true

echo "=== Symbol counts ==="
for s in ksu_ susfs_ tcp_bbr3 hmbird ntsync rekernel baseband bbg_ ksu_susfs; do
  n=$(grep -c "$s" System.map || true)
  echo "$s: $n"
done
echo "--- sample BBG ---"
grep -iE 'baseband|bbg' System.map | head -15 || true
echo "--- sample KSU ---"
grep 'ksu_' System.map | head -8 || true
echo "--- sample HMBIRD ---"
grep 'hmbird' System.map | head -8 || true

echo "=== Package AK3 ==="
rm -rf "$AK3_TMP"
mkdir -p "$AK3_TMP/META-INF/com/google/android"

# Prefer project anykernel scripts from Windows repo if present
if [ -f "$AK3_REPO/anykernel.sh" ]; then
  cp "$AK3_REPO/anykernel.sh" "$AK3_TMP/"
  cp "$AK3_REPO/service.sh" "$AK3_TMP/" 2>/dev/null || true
  cp "$AK3_REPO/module.prop" "$AK3_TMP/" 2>/dev/null || true
  cp "$AK3_REPO/META-INF/com/google/android/update-binary" "$AK3_TMP/META-INF/com/google/android/"
  cp "$AK3_REPO/META-INF/com/google/android/updater-script" "$AK3_TMP/META-INF/com/google/android/"
  # tools if any
  if [ -d "$AK3_REPO/tools" ] && [ "$(ls -A "$AK3_REPO/tools" 2>/dev/null)" ]; then
    cp -a "$AK3_REPO/tools" "$AK3_TMP/"
  fi
else
  # fallback existing ak3 layout
  cp -a "$OUT/ak3/." "$AK3_TMP/" 2>/dev/null || true
fi

# If tools missing, try ak3-template from Windows
if [ ! -f "$AK3_TMP/tools/magiskboot" ] && [ -d /mnt/d/OnePlus13-kernel/ak3-template/tools ]; then
  echo "Copying tools from ak3-template"
  cp -a /mnt/d/OnePlus13-kernel/ak3-template/tools "$AK3_TMP/"
  # also use template anykernel if ours is incomplete
  if [ ! -f "$AK3_TMP/tools/ak3-core.sh" ]; then
    cp /mnt/d/OnePlus13-kernel/ak3-template/anykernel.sh "$AK3_TMP/" || true
  fi
fi

cp arch/arm64/boot/Image "$AK3_TMP/Image"

# module.prop version bump
if [ -f "$AK3_TMP/module.prop" ]; then
  sed -i "s/^version=.*/version=v3.0-custom-$(date +%Y%m%d)/" "$AK3_TMP/module.prop" || true
fi

ZIPNAME="OnePlus13-sun-custom-$(date +%Y%m%d-%H%M).zip"
cd "$AK3_TMP"
zip -r9 "$OUT/$ZIPNAME" . >/dev/null
cd "$OUT"
sha256sum "$ZIPNAME" | tee "${ZIPNAME}.sha256"
ls -lah "$ZIPNAME"
echo "ZIP=$OUT/$ZIPNAME"

# also copy to Windows project dir
cp -f "$ZIPNAME" "/mnt/d/OnePlus13-kernel/" 2>/dev/null || true
cp -f "${ZIPNAME}.sha256" "/mnt/d/OnePlus13-kernel/" 2>/dev/null || true
echo "Also copied to /mnt/d/OnePlus13-kernel/"
