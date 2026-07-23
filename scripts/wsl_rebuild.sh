#!/bin/bash
set -euo pipefail
SRC=/home/axymorrsen/op13-kernel/src
LOGDIR=/home/axymorrsen/op13-kernel/logs
mkdir -p "$LOGDIR"
cd "$SRC"
export ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu-

# Invalidate fixed object
rm -f kernel/sched/core.o kernel/sched/.core.o.cmd
rm -f arch/arm64/boot/Image vmlinux System.map

LOG="$LOGDIR/build4-$(date +%Y%m%d-%H%M%S).log"
echo "Building Image, log=$LOG"
set +e
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

if [ -f arch/arm64/boot/Image ]; then
  echo "=== BUILD SUCCESS ==="
  ls -la arch/arm64/boot/Image
  echo "=== symbol check ==="
  for s in ksu_ susfs_ tcp_bbr3 hmbird bbg rekernel ntsync; do
    n=$(grep -c "$s" System.map 2>/dev/null || echo 0)
    echo "$s: $n"
  done
  exit 0
fi
echo "=== BUILD FAILED rc=$rc ==="
grep -E 'error:|Error 1|undefined reference' "$LOG" | sort -u | tail -50
tail -40 "$LOG"
exit 1
