#!/bin/bash
set -euo pipefail
SRC_IMG=/home/axymorrsen/op13-kernel/src/arch/arm64/boot/Image
STAGE=/home/axymorrsen/op13-kernel/release-mgr
TEMPLATE=/mnt/d/OnePlus13-kernel/ak3-template
OUT=/mnt/d/OnePlus13-kernel/releases
WSL_OUT=/home/axymorrsen/op13-kernel
STAMP=$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"

[ -f "$SRC_IMG" ] || { echo "no Image"; exit 1; }

# Version-first naming: v6.6.89-OnePlus13-sun-AK3-MGR-YYYYMMDD-HHMM.zip
VER=$(strings "$SRC_IMG" 2>/dev/null | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
VER=${VER:-6.6.89}
NAME="v${VER}-OnePlus13-sun-AK3-MGR-${STAMP}"
echo "NAME=$NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$TEMPLATE/." "$STAGE/"
cp -f "$SRC_IMG" "$STAGE/Image"
sed -i 's/\r$//' "$STAGE/anykernel.sh" "$STAGE/tools/ak3-core.sh" \
  "$STAGE/META-INF/com/google/android/update-binary" 2>/dev/null || true
chmod 755 "$STAGE/META-INF/com/google/android/update-binary"
chmod 755 "$STAGE/tools/"* 2>/dev/null || true

echo "=== gates ==="
strings "$STAGE/Image" | grep -E 'Linux version' | head -1
strings "$STAGE/Image" | grep -qi kernelsu && echo KSU_OK
grep -q 'non-interactive' "$STAGE/anykernel.sh" && echo MGR_SCRIPT_OK
grep -q 'do.devicecheck=0' "$STAGE/anykernel.sh" && echo NO_DEVICECHECK_OK

ZIP="$WSL_OUT/${NAME}.zip"
( cd "$STAGE" && zip -r9 "$ZIP" . )
cp -f "$ZIP" "$OUT/"
sha256sum "$ZIP" | tee "$OUT/${NAME}.zip.sha256"
ls -lah "$OUT/${NAME}.zip"
unzip -l "$ZIP" | head -22
echo "WIN=$OUT/${NAME}.zip"
