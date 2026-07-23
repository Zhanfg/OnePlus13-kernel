#!/bin/bash
set -euo pipefail
SRC=/home/axymorrsen/op13-kernel/src
LOGDIR=/home/axymorrsen/op13-kernel/logs
cd "$SRC"
export ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu-
rm -f arch/arm64/boot/Image vmlinux System.map
LOG="$LOGDIR/build-feat-full-$(date +%Y%m%d-%H%M%S).log"
echo "Building Image log=$LOG jobs=$(nproc)"
set +e
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
if [ -f arch/arm64/boot/Image ]; then
  echo "=== BUILD SUCCESS ==="
  ls -la arch/arm64/boot/Image
  S=$(mktemp)
  strings arch/arm64/boot/Image > "$S"
  for pat in 'Linux version' 'susfs|kernelsu' 'hmbird' 'bbr3' 'baseband_guard' 'adios' 'ip_set' 'sch_cake|cake'; do
    if grep -qiE "$pat" "$S"; then echo "[PASS] $pat"; else echo "[FAIL] $pat"; fi
  done
  rm -f "$S"
  for s in ksu_ susfs_ hmbird bbg adios ntsync rekernel tcp_bbr3 ip_set cake; do
    echo "sym $s: $(grep -c "$s" System.map || true)"
  done
  exit 0
fi
echo "=== BUILD FAILED rc=$rc ==="
grep -E 'error:|Error 1' "$LOG" | sort -u | tail -40
exit 1
