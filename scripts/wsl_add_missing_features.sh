#!/bin/bash
# Enable IP_SET/CAKE + apply unicode bypass + attempt ADIOS
set -euo pipefail
SRC=/home/axymorrsen/op13-kernel/src
PATCHES=/home/axymorrsen/op13-kernel/patches
LOGDIR=/home/axymorrsen/op13-kernel/logs
mkdir -p "$LOGDIR"
cd "$SRC"

echo "=== [1] Apply unicode bypass (6.1+) ==="
UB="$PATCHES/wildkernels_patches/common/unicode_bypass_fix_6.1+.patch"
if grep -q 'LEAF_STR(leaf)' fs/unicode/utf8-norm.c 2>/dev/null && \
   grep -q 'Check if the decomposition result is empty' fs/unicode/utf8-norm.c 2>/dev/null; then
  echo "unicode bypass already applied"
else
  set +e
  patch -p1 --forward --reject-file=- < "$UB" >"$LOGDIR/unicode_bypass.log" 2>&1
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    echo "unicode bypass: applied cleanly"
  elif [ $rc -eq 1 ]; then
    echo "unicode bypass: partial (see log)"
    cat "$LOGDIR/unicode_bypass.log" | tail -30
  else
    echo "unicode bypass: failed rc=$rc"
    cat "$LOGDIR/unicode_bypass.log" | tail -30
  fi
fi

echo "=== [2] Attempt ADIOS 6.12 patch on 6.6 (reject mode) ==="
ADIOS_PATCH="$PATCHES/adios/patches/stable/0001-linux6.12.44-ADIOS-3.2.0.patch"
if [ -f block/adios-iosched.c ] || [ -f block/adios.c ]; then
  echo "ADIOS already present"
else
  set +e
  patch -p1 --forward --reject-file=- < "$ADIOS_PATCH" >"$LOGDIR/adios_apply.log" 2>&1
  rc=$?
  set -e
  echo "adios patch rc=$rc"
  tail -40 "$LOGDIR/adios_apply.log"
  # count rejects
  find . -name '*.rej' 2>/dev/null | head -30 | tee "$LOGDIR/adios_rejs.list" || true
  if [ -f block/adios-iosched.c ] || ls block/*adios* 2>/dev/null; then
    echo "ADIOS source files appeared"
    ls -la block/*adios* 2>/dev/null || true
  else
    echo "ADIOS files not created — will try manual extract from patch"
  fi
fi

echo "=== [3] Enable config options ==="
python3 - <<'PY'
from pathlib import Path
p = Path(".config")
text = p.read_text()

def set_y(key):
    global text
    import re
    # replace not set
    text2 = re.sub(rf"^# {re.escape(key)} is not set\s*$", f"{key}=y", text, flags=re.M)
    if text2 != text:
        text = text2
        print("enabled", key)
        return
    if re.search(rf"^{re.escape(key)}=", text, re.M):
        text = re.sub(rf"^{re.escape(key)}=.*$", f"{key}=y", text, flags=re.M)
        print("set", key, "=y")
    else:
        text += f"\n{key}=y\n"
        print("appended", key)

# IP_SET family
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
    "CONFIG_NET_SCH_FQ_CODEL",
    "CONFIG_NETFILTER_XT_SET",
]:
    set_y(k)

# ADIOS if Kconfig present
if Path("block/Kconfig.iosched").exists() and "ADIOS" in Path("block/Kconfig.iosched").read_text():
    set_y("CONFIG_MQ_IOSCHED_ADIOS")
    print("ADIOS Kconfig found")
elif Path("block/Kconfig").exists() and "ADIOS" in Path("block/Kconfig").read_text():
    set_y("CONFIG_MQ_IOSCHED_ADIOS")
    print("ADIOS in block/Kconfig")
else:
    print("ADIOS Kconfig not present yet")

p.write_text(text)
print("config written")
PY

export ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu-
yes "" 2>/dev/null | make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >"$LOGDIR/olddef-feat.log" 2>&1 || true

echo "=== verify config ==="
grep -E 'CONFIG_IP_SET=|CONFIG_NET_SCH_CAKE=|CONFIG_MQ_IOSCHED|CONFIG_NETFILTER_XT_SET' .config | head -30

echo "=== done stage ==="
