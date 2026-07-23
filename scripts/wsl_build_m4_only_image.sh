#!/bin/bash
# M4-SAFE image build (config already prepared on tree)
set -euo pipefail
export http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= all_proxy=
SRC=/home/axymorrsen/op13-kernel/brokestar-6.6
OUT=/mnt/d/OnePlus13-kernel/releases
LOGDIR=/home/axymorrsen/op13-kernel/logs
STAMP=$(date +%Y%m%d-%H%M)
cd "$SRC"
export ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu-

echo "=== config snapshot ==="
grep -E 'LOCALVERSION=|ARCH_ORYON|LLVM_POLLY|SCHED_BORE|LTO_NONE|LTO_CLANG_THIN|HMBIRD' .config | head -20
echo "=== Makefile guards ==="
grep -n "M4_SAFE\|DISABLED_FOR_SAFE\|mcpu=oryon\|CONFIG_LLVM_POLLY" Makefile | head -20

echo "=== build ==="
LOG="${LOGDIR}/brokestar-m4-safe-${STAMP}.log"
set +e
set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
set -o pipefail

if [ ! -f arch/arm64/boot/Image ]; then
  echo "BUILD FAIL rc=$rc"
  grep -E 'error:|Error 1|fatal' "$LOG" | grep -v 'Could not read' | sort -u | tail -40
  exit 1
fi

echo "=== flag audit ==="
if grep -q 'mcpu=oryon' "$LOG"; then echo "WARN: oryon still in log"; else echo "OK: no oryon"; fi
if grep -q '\-polly' "$LOG"; then echo "WARN: polly still in log"; else echo "OK: no polly"; fi
if grep -q 'flto=thin\|-flto' "$LOG"; then echo "WARN: lto still in log"; else echo "OK: no lto flags (or few)"; fi

ls -lah arch/arm64/boot/Image
strings arch/arm64/boot/Image | grep -E 'Linux version 6\.6' | head -2

AK3="$OUT/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip"
STAGE=/home/axymorrsen/op13-kernel/ak3-m4-safe
rm -rf "$STAGE"; mkdir -p "$STAGE"
unzip -q "$AK3" -d "$STAGE"
cp -f arch/arm64/boot/Image "$STAGE/Image"
rm -f "$STAGE/module.prop"
sed -i 's/kernel.string=.*/kernel.string=v6.6.126 brokestar-M4-SAFE no-LTO-Polly-Oryon-BORE/' "$STAGE/anykernel.sh"
sed -i 's/^block=.*/block=boot/' "$STAGE/anykernel.sh"
find "$STAGE" -name '*.sh' -o -name 'update-binary' | while read f; do sed -i 's/\r$//' "$f"; done
chmod 755 "$STAGE/META-INF/com/google/android/update-binary" "$STAGE/tools/"* 2>/dev/null || true
NAME="v6.6.126-OnePlus13-sun-AK3-BROKESTAR-M4-SAFE-${STAMP}"
( cd "$STAGE" && zip -r9 "$OUT/${NAME}.zip" . )
sha256sum "$OUT/${NAME}.zip" | tee "$OUT/${NAME}.zip.sha256"
cp -f arch/arm64/boot/Image "$OUT/v6.6.126-Image-brokestar-m4-safe"
sha256sum "$OUT/v6.6.126-Image-brokestar-m4-safe" | tee "$OUT/v6.6.126-Image-brokestar-m4-safe.sha256"

cat > "$OUT/M4_SAFE_FLASH_NOTE.txt" << EOF
M4-SAFE（针对 M1-M3 反复重启）
================================
文件: ${NAME}.zip
已关闭: ThinLTO / Polly / -mcpu=oryon-1 / BORE
保留: HMBIRD（能刷 144 也有）
LOCALVERSION: -4k-safe
工具链: Ubuntu clang 21（尚未换 Android r510928）
目的: 验证激进优化是否为 bootloop 主因

刷法: ReSukiSU Manager → AnyKernel3 → 本 zip
成功: 过 Logo 进桌面
失败: fastboot flash boot releases/restore/boot.img
详见: BOOTLOOP_ANALYSIS.md
生成: $(date -Is)
EOF
echo "M4-SAFE DONE: $OUT/${NAME}.zip"
