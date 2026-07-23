#!/bin/bash
# Package official release: real Image + standard AK3 template
set -euo pipefail

SRC=/home/axymorrsen/op13-kernel/src
IMG="$SRC/arch/arm64/boot/Image"
TEMPLATE=/mnt/d/OnePlus13-kernel/ak3-template
WSL_OUT=/home/axymorrsen/op13-kernel
WIN_OUT=/mnt/d/OnePlus13-kernel/releases
STAMP=$(date +%Y%m%d-%H%M)
STAGE="$WSL_OUT/release-stage"
mkdir -p "$WIN_OUT"

echo "=== Preflight ==="
[ -f "$IMG" ] || { echo "FAIL: no Image"; exit 1; }

# Version-first naming: v6.6.89-OnePlus13-sun-AK3-release-YYYYMMDD-HHMM.zip
VER=$(strings "$IMG" 2>/dev/null | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
VER=${VER:-6.6.89}
NAME="v${VER}-OnePlus13-sun-AK3-release-${STAMP}"
echo "NAME=$NAME"
[ -f "$TEMPLATE/tools/ak3-core.sh" ] || { echo "FAIL: no ak3-core.sh"; exit 1; }
[ -f "$TEMPLATE/tools/magiskboot" ] || { echo "FAIL: no magiskboot"; exit 1; }
[ -f "$TEMPLATE/META-INF/com/google/android/update-binary" ] || { echo "FAIL: no update-binary"; exit 1; }

# Mandatory strings gates (spec §6)
# Use temp file to avoid pipefail/set -e quirks with grep -q
fail=0
STRINGS_TMP=$(mktemp)
strings "$IMG" > "$STRINGS_TMP"
check_pat() {
  local pat="$1"
  if grep -iE "$pat" "$STRINGS_TMP" >/dev/null 2>&1; then
    echo "[PASS] strings: $pat"
    return 0
  fi
  echo "[FAIL] strings: $pat"
  return 1
}
check_pat 'Linux version' || fail=1
check_pat 'susfs|kernelsu' || fail=1
check_pat 'hmbird' || fail=1
check_pat 'bbr3' || fail=1
check_pat 'baseband_guard' || fail=1
rm -f "$STRINGS_TMP"
[ "$fail" -eq 0 ] || { echo "REFUSE to pack: Image failed feature strings gate"; exit 1; }

echo "=== Stage package ==="
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$TEMPLATE/." "$STAGE/"
# overwrite Image with OUR compiled one (never ship template's old Image)
cp -f "$IMG" "$STAGE/Image"
# ensure verified flags in anykernel.sh
sed -i 's/^HMBIRD_VERIFIED=.*/HMBIRD_VERIFIED=1   # verified 2026-07-20/' "$STAGE/anykernel.sh"
sed -i 's/^SCX_VERIFIED=.*/SCX_VERIFIED=0      # gen-1 fengchi not fully integrated/' "$STAGE/anykernel.sh"
sed -i 's/^ZSTD_AVAILABLE=.*/ZSTD_AVAILABLE=1/' "$STAGE/anykernel.sh"

# Sanity: no empty critical files
for f in Image anykernel.sh tools/ak3-core.sh tools/magiskboot tools/busybox \
         META-INF/com/google/android/update-binary \
         META-INF/com/google/android/updater-script; do
  if [ ! -s "$STAGE/$f" ]; then
    echo "FAIL: missing/empty $f"
    exit 1
  fi
  echo "  OK $f ($(wc -c < "$STAGE/$f") bytes)"
done

# Strip any accidental .git / junk
rm -rf "$STAGE/.git" "$STAGE/.gitignore" 2>/dev/null || true

echo "=== Zip ==="
ZIP="$WSL_OUT/${NAME}.zip"
( cd "$STAGE" && zip -r9 "$ZIP" . -x '*.DS_Store' )
sha256sum "$ZIP" | tee "${ZIP}.sha256"
ls -lah "$ZIP"

# Copy to Windows project root
cp -f "$ZIP" "$WIN_OUT/"
cp -f "${ZIP}.sha256" "$WIN_OUT/"
# Also copy Image for inspection
cp -f "$IMG" "$WIN_OUT/Image-release"
cp -f "$IMG" "$WSL_OUT/Image-release"

echo "=== Package contents ==="
unzip -l "$ZIP" | head -40
echo "..."
unzip -l "$ZIP" | tail -5

echo
echo "RELEASE_ZIP=$ZIP"
echo "WIN_ZIP=$WIN_OUT/$(basename "$ZIP")"
echo "IMAGE_SIZE=$(du -h "$IMG" | cut -f1)"
echo "ZIP_SIZE=$(du -h "$ZIP" | cut -f1)"
