#!/bin/bash
set -euo pipefail
SRC=/home/axymorrsen/op13-kernel/src
PATCHES=/home/axymorrsen/op13-kernel/patches
LOGDIR=/home/axymorrsen/op13-kernel/logs
mkdir -p "$LOGDIR"
cd "$SRC"

echo "=== Unicode bypass ==="
UB="$PATCHES/wildkernels_patches/common/unicode_bypass_fix_6.1+.patch"
if grep -q 'Check if the decomposition result is empty' fs/unicode/utf8-norm.c 2>/dev/null; then
  echo "already applied"
else
  set +e
  patch -p1 --forward < "$UB" >"$LOGDIR/unicode_bypass.log" 2>&1
  rc=$?
  set -e
  echo "unicode patch rc=$rc"
  tail -20 "$LOGDIR/unicode_bypass.log" || true
fi

echo "=== Enable configs ==="
python3 - <<'PY'
from pathlib import Path
import re
p = Path(".config")
t = p.read_text()

def set_y(k):
    global t
    t2 = re.sub(rf"^# {re.escape(k)} is not set\s*$", f"{k}=y", t, flags=re.M)
    if t2 != t:
        t = t2
        print("en", k)
        return
    if re.search(rf"^{re.escape(k)}=", t, re.M):
        t = re.sub(rf"^{re.escape(k)}=.*$", f"{k}=y", t, flags=re.M)
        print("set", k)
    else:
        t += f"\n{k}=y\n"
        print("app", k)

for k in [
    "CONFIG_IP_SET",
    "CONFIG_IP_SET_BITMAP_IP",
    "CONFIG_IP_SET_BITMAP_IPMAC",
    "CONFIG_IP_SET_BITMAP_PORT",
    "CONFIG_IP_SET_HASH_IP",
    "CONFIG_IP_SET_HASH_IPMARK",
    "CONFIG_IP_SET_HASH_IPPORT",
    "CONFIG_IP_SET_HASH_IPPORTIP",
    "CONFIG_IP_SET_HASH_IPPORTNET",
    "CONFIG_IP_SET_HASH_IPMAC",
    "CONFIG_IP_SET_HASH_MAC",
    "CONFIG_IP_SET_HASH_NETPORTNET",
    "CONFIG_IP_SET_HASH_NET",
    "CONFIG_IP_SET_HASH_NETNET",
    "CONFIG_IP_SET_HASH_NETPORT",
    "CONFIG_IP_SET_HASH_NETIFACE",
    "CONFIG_IP_SET_LIST_SET",
    "CONFIG_NET_SCH_CAKE",
    "CONFIG_NETFILTER_XT_SET",
    "CONFIG_MQ_IOSCHED_ADIOS",
]:
    set_y(k)
p.write_text(t)
PY

export ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu-
yes "" 2>/dev/null | make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >"$LOGDIR/olddef-feat.log" 2>&1 || true
echo "--- config ---"
grep -E 'CONFIG_IP_SET=|CONFIG_NET_SCH_CAKE=|CONFIG_MQ_IOSCHED_ADIOS=|CONFIG_NETFILTER_XT_SET=' .config || true

echo "=== Probe compile adios.o ==="
set +e
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" block/adios.o 2>&1 | tee "$LOGDIR/adios_compile.log"
rc=${PIPESTATUS[0]}
set -e
if [ $rc -ne 0 ] || [ ! -f block/adios.o ]; then
  echo "ADIOS compile failed — collect errors"
  grep -E 'error:|Error 1' "$LOGDIR/adios_compile.log" | head -40
  echo "Will attempt API fixes..."
  # Continue to show errors; rebuild script may fix
  exit 2
fi
echo "ADIOS.o OK"

echo "=== Full Image rebuild ==="
rm -f arch/arm64/boot/Image vmlinux System.map
LOG="$LOGDIR/build-feat-$(date +%Y%m%d-%H%M%S).log"
set +e
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

if [ ! -f arch/arm64/boot/Image ]; then
  echo "BUILD FAILED"
  grep -E 'error:|Error 1' "$LOG" | sort -u | tail -50
  exit 1
fi

echo "=== BUILD SUCCESS ==="
ls -la arch/arm64/boot/Image
STRINGS=$(mktemp)
strings arch/arm64/boot/Image > "$STRINGS"
for pat in 'Linux version' 'susfs|kernelsu' 'hmbird' 'bbr3' 'baseband_guard' 'adios' 'sch_cake|cake' 'ip_set'; do
  if grep -qiE "$pat" "$STRINGS"; then
    echo "[PASS] $pat"
  else
    echo "[FAIL] $pat"
  fi
done
rm -f "$STRINGS"
for s in ksu_ susfs_ hmbird bbg adios ntsync rekernel tcp_bbr3 ip_set cake; do
  n=$(grep -c "$s" System.map || true)
  echo "sym $s: $n"
done
exit 0
