#!/bin/bash
# Spec compliance audit for OnePlus13 custom kernel
set -euo pipefail
SRC=/home/axymorrsen/op13-kernel/src
OUT=/home/axymorrsen/op13-kernel
IMG="$SRC/arch/arm64/boot/Image"
REPORT="$OUT/BUILD_REPORT.txt"

exec > >(tee "$REPORT") 2>&1

echo "=============================================="
echo " OnePlus 13 (sun/SM8750) Build Spec Audit"
echo " Date: $(date -Is)"
echo "=============================================="

echo
echo "=== 1. Image existence ==="
if [ ! -f "$IMG" ]; then
  echo "FAIL: Image missing at $IMG"
  exit 1
fi
ls -la "$IMG"
file "$IMG"
du -h "$IMG"

echo
echo "=== 2. Official tree identity ==="
cd "$SRC"
echo "remote:"
git remote -v 2>/dev/null || true
echo "branch:"
git branch -vv 2>/dev/null | head -5 || true
echo "commit:"
git rev-parse HEAD 2>/dev/null || true
git log -1 --oneline 2>/dev/null || true
echo "kernelversion:"
make kernelversion 2>/dev/null || true
# version string from Image
echo "--- strings Linux version ---"
strings "$IMG" | grep -iE 'Linux version' | head -5 || echo "WARN: no Linux version string"

echo
echo "=== 3. strings Image feature checks (spec §6) ==="
check_str() {
  local label="$1" pat="$2"
  local hits
  hits=$(strings "$IMG" | grep -iE "$pat" | head -8 || true)
  if [ -n "$hits" ]; then
    echo "[PASS] $label"
    echo "$hits" | sed 's/^/    /'
  else
    echo "[FAIL] $label (pattern: $pat)"
  fi
}
check_str "Root/SuSFS/KSU" 'susfs|SUS_PATH|kernelsu|resukisu|sukisu|ksu_'
check_str "HMBIRD/fengchi" 'hmbird|fengchi'
check_str "BBRv3" 'bbr3'
check_str "BBG" 'baseband_guard|baseband.guard|bbg_'
check_str "NTSYNC" 'ntsync'
check_str "ReKernel" 'rekernel|re_kernel|Re:Kernel'
check_str "WireGuard" 'wireguard|WireGuard'
check_str "OVERLAY_FS" 'overlay'

echo
echo "=== 4. System.map symbol counts ==="
if [ -f System.map ]; then
  for s in ksu_ susfs_ hmbird bbg baseband ntsync rekernel tcp_bbr3 wireguard overlay; do
    n=$(grep -c "$s" System.map || true)
    echo "  $s: $n"
  done
else
  echo "WARN: no System.map"
fi

echo
echo "=== 5. Key .config defaults ==="
for k in \
  CONFIG_KSU CONFIG_KSU_SUSFS CONFIG_HMBIRD_SCHED CONFIG_TCP_CONG_BBR3 \
  CONFIG_DEFAULT_BBR3 CONFIG_DEFAULT_TCP_CONG CONFIG_NET_SCH_FQ \
  CONFIG_ZRAM_DEF_COMP CONFIG_BBG CONFIG_REKERNEL CONFIG_NTSYNC \
  CONFIG_KALLSYMS CONFIG_KALLSYMS_ALL CONFIG_OVERLAY_FS CONFIG_TMPFS_XATTR \
  CONFIG_TMPFS_POSIX_ACL CONFIG_PID_NS CONFIG_IPC_NS CONFIG_SYSVIPC \
  CONFIG_WIREGUARD CONFIG_KASAN CONFIG_LSM; do
  grep -E "^$k=|^# $k is not set|^$k " .config 2>/dev/null | head -1 || echo "$k: MISSING"
done
# ZRAM detail
grep -E 'ZRAM_DEF_COMP|ZRAM_WRITEBACK|ZRAM_MULTI' .config | head -10

echo
echo "=== 6. Patch repos commits ==="
for d in resukisu susfs sched_patch bbg re-kernel wildkernels_patches; do
  p="/home/axymorrsen/op13-kernel/patches/$d"
  if [ -d "$p/.git" ]; then
    echo "--- $d ---"
    git -C "$p" remote get-url origin 2>/dev/null || true
    git -C "$p" rev-parse HEAD 2>/dev/null || true
    git -C "$p" log -1 --oneline 2>/dev/null || true
  elif [ -d "$p" ]; then
    echo "--- $d --- (no .git, directory present)"
    ls "$p" | head -8
  else
    echo "--- $d --- MISSING"
  fi
done

echo
echo "=== 7. Missing feature probe (source tree) ==="
probe() {
  local name="$1"; shift
  local found=0
  for f in "$@"; do
    if [ -e "$f" ]; then found=1; echo "  [found] $name: $f"; break; fi
  done
  [ "$found" -eq 1 ] || echo "  [missing] $name"
}
probe ADIOS drivers/block/adios* block/adios* include/linux/adios*
probe SCX_sched kernel/sched/ext.c
probe Unicode_bypass drivers/tty/*unicode* *unicode*bypass* 2>/dev/null || true
find . -iname '*unicode*bypass*' 2>/dev/null | head -5 | sed 's/^/  unicode candidate: /' || true
find . -iname '*xus*' 2>/dev/null | head -5 | sed 's/^/  xus candidate: /' || true
find . -iname '*adios*' 2>/dev/null | head -5 | sed 's/^/  adios candidate: /' || true

echo
echo "=== 8. Existing AK3 packages ==="
ls -la "$OUT"/*.zip 2>/dev/null || true
ls -la /mnt/d/OnePlus13-kernel/*.zip 2>/dev/null || true

echo
echo "=== 9. anykernel tree in project ==="
for d in /mnt/d/OnePlus13-kernel/anykernel /mnt/d/OnePlus13-kernel/ak3-template /home/axymorrsen/op13-kernel/ak3-custom; do
  if [ -d "$d" ]; then
    echo "--- $d ---"
    find "$d" -maxdepth 3 -type f | head -40
  fi
done

echo
echo "REPORT_WRITTEN=$REPORT"
