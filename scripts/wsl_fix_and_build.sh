#!/bin/bash
# Fix defaults + rebuild OnePlus13 custom kernel Image
set -euo pipefail

SRC=/home/axymorrsen/op13-kernel/src
LOGDIR=/home/axymorrsen/op13-kernel/logs
mkdir -p "$LOGDIR"
cd "$SRC"

echo "=== [1/4] Fix .config defaults ==="
python3 <<'PY'
from pathlib import Path
p = Path(".config")
text = p.read_text()
replacements = [
    ('CONFIG_DEFAULT_TCP_CONG="cubic"', 'CONFIG_DEFAULT_TCP_CONG="bbr3"'),
    ("# CONFIG_DEFAULT_BBR3 is not set", "CONFIG_DEFAULT_BBR3=y"),
    ("CONFIG_DEFAULT_CUBIC=y", "# CONFIG_DEFAULT_CUBIC is not set"),
    ("CONFIG_ZRAM_DEF_COMP_LZORLE=y", "# CONFIG_ZRAM_DEF_COMP_LZORLE is not set"),
    ("# CONFIG_ZRAM_DEF_COMP_LZ4 is not set", "CONFIG_ZRAM_DEF_COMP_LZ4=y"),
    ('CONFIG_ZRAM_DEF_COMP="lzo-rle"', 'CONFIG_ZRAM_DEF_COMP="lz4"'),
    ("# CONFIG_ZRAM_WRITEBACK is not set", "CONFIG_ZRAM_WRITEBACK=y"),
    ("# CONFIG_ZRAM_MULTI_COMP is not set", "CONFIG_ZRAM_MULTI_COMP=y"),
]
for a, b in replacements:
    if a in text:
        text = text.replace(a, b)
        print("OK:", a[:70])
    else:
        print("MISS/already:", a[:70])
if "CONFIG_DEFAULT_BBR3=y" not in text:
    text += "\nCONFIG_DEFAULT_BBR3=y\n"
    print("APPENDED DEFAULT_BBR3")
# Ensure cubic default off if bbr3 default on
if "CONFIG_DEFAULT_BBR3=y" in text and "CONFIG_DEFAULT_CUBIC=y" in text:
    text = text.replace("CONFIG_DEFAULT_CUBIC=y", "# CONFIG_DEFAULT_CUBIC is not set")
p.write_text(text)
print("config written")
PY

echo "=== [2/4] Ensure BBG wired into drivers ==="
if ! grep -q baseband_guard drivers/Makefile; then
  printf 'obj-$(CONFIG_BBG) += baseband_guard/\n' >> drivers/Makefile
  echo "APPENDED BBG to drivers/Makefile"
else
  echo "BBG already in Makefile"
fi
if ! grep -q baseband_guard drivers/Kconfig; then
  printf 'source "drivers/baseband_guard/Kconfig"\n' >> drivers/Kconfig
  echo "APPENDED BBG to drivers/Kconfig"
else
  echo "BBG already in Kconfig"
fi

echo "=== [3/4] Invalidate stale objects (pre-patch) ==="
rm -f kernel/sched/build_policy.o kernel/sched/.build_policy.o.cmd
rm -f arch/arm64/boot/Image vmlinux System.map .tmp_vmlinux* vmlinux.o vmlinux.a built-in.a
# Force KSU / BBG rebuild path
rm -rf drivers/kernelsu/*.o drivers/kernelsu/*/*.o drivers/kernelsu/*/*/*.o 2>/dev/null || true
rm -f drivers/baseband_guard/*.o 2>/dev/null || true

export ARCH=arm64
export CC=clang
export CROSS_COMPILE=aarch64-linux-gnu-
# Do NOT force LLVM=1 for host tools if it causes issues; clang for target is enough

echo "=== olddefconfig ==="
set +e
yes "" 2>/dev/null | make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >"$LOGDIR/olddef3.log" 2>&1
set -e

echo "=== defaults after olddef ==="
grep -E 'DEFAULT_TCP_CONG|DEFAULT_BBR3|DEFAULT_CUBIC|ZRAM_DEF_COMP=|CONFIG_BBG=|CONFIG_KSU=|CONFIG_HMBIRD|CONFIG_NTSYNC|CONFIG_REKERNEL|CONFIG_KSU_SUSFS=|CONFIG_TCP_CONG_BBR3' .config || true

echo "=== [4/4] Build Image ==="
LOG="$LOGDIR/build3-$(date +%Y%m%d-%H%M%S).log"
echo "Logging to $LOG"
set +e
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

if [ -f arch/arm64/boot/Image ]; then
  echo "=== BUILD SUCCESS ==="
  ls -la arch/arm64/boot/Image
  echo "Size: $(du -h arch/arm64/boot/Image | cut -f1)"
  echo "=== symbol checks ==="
  nm vmlinux 2>/dev/null | grep -E 'ksu_|susfs_|tcp_bbr3|hmbird|bbg_|rekernel|ntsync' | head -40 || \
    grep -E 'ksu_|susfs_|tcp_bbr3|hmbird|bbg|rekernel|ntsync' System.map | head -40 || true
  exit 0
else
  echo "=== BUILD FAILED rc=$rc ==="
  grep -iE 'error:|Error 1|undefined reference|No rule to make' "$LOG" | tail -40
  tail -50 "$LOG"
  exit 1
fi
