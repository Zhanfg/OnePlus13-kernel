#!/bin/bash
set -euo pipefail
SRC=/home/axymorrsen/op13-kernel/src
PATCH=/home/axymorrsen/op13-kernel/patches/bbg
LOGDIR=/home/axymorrsen/op13-kernel/logs

# 1) Symlink full BBG tree (includes tracing/)
rm -rf "$SRC/drivers/baseband_guard"
ln -sfn "$PATCH" "$SRC/drivers/baseband_guard"
echo "BBG linked: $(readlink -f $SRC/drivers/baseband_guard)"
ls "$SRC/drivers/baseband_guard/tracing" | head

# 2) Fix drivers/Makefile hook: CONFIG_BBG not CONFIG_BASEBAND_GUARD
python3 - <<'PY'
from pathlib import Path
p = Path("/home/axymorrsen/op13-kernel/src/drivers/Makefile")
t = p.read_text()
t2 = t.replace("obj-$(CONFIG_BASEBAND_GUARD) += baseband_guard/",
               "obj-$(CONFIG_BBG) += baseband_guard/")
if "obj-$(CONFIG_BBG) += baseband_guard/" not in t2:
    t2 += "\nobj-$(CONFIG_BBG) += baseband_guard/\n"
    print("appended BBG line")
else:
    print("BBG makefile line OK")
p.write_text(t2)
# show
for i,l in enumerate(p.read_text().splitlines(),1):
    if "baseband" in l:
        print(f"{i}: {l}")
PY

# 3) Disable unshallow in BBG Makefile
python3 - <<'PY'
from pathlib import Path
p = Path("/home/axymorrsen/op13-kernel/patches/bbg/Makefile")
lines = p.read_text().splitlines(True)
out=[]
for line in lines:
    if "fetch --unshallow" in line and not line.lstrip().startswith("#"):
        out.append("# disabled offline: " + line)
        print("commented bbg unshallow")
    else:
        out.append(line)
p.write_text("".join(out))
PY
# remove shallow if present
if [ -f "$PATCH/.git/shallow" ]; then
  mv "$PATCH/.git/shallow" "$PATCH/.git/shallow.bak"
fi
rm -f "$PATCH/.git/shallow.lock"

# 4) Fix .config: add baseband_guard to LSM, disable KASAN
python3 - <<'PY'
from pathlib import Path
p = Path("/home/axymorrsen/op13-kernel/src/.config")
text = p.read_text()

# LSM
import re
m = re.search(r'^CONFIG_LSM="([^"]*)"', text, re.M)
if m:
    lsm = m.group(1)
    if "baseband_guard" not in lsm:
        # insert before selinux if possible, else append
        parts = lsm.split(",")
        if "selinux" in parts:
            parts.insert(parts.index("selinux"), "baseband_guard")
        else:
            parts.append("baseband_guard")
        new = ",".join(parts)
        text = text.replace(m.group(0), f'CONFIG_LSM="{new}"')
        print("LSM ->", new)
    else:
        print("LSM already has baseband_guard")
else:
    text += '\nCONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,baseband_guard,selinux,smack,tomoyo,apparmor,bpf"\n'
    print("appended LSM")

# Disable KASAN for production size/perf
for key in [
    "CONFIG_KASAN=y",
    "CONFIG_KASAN_GENERIC=y",
    "CONFIG_KASAN_INLINE=y",
    "CONFIG_KASAN_SW_TAGS=y",
    "CONFIG_KASAN_HW_TAGS=y",
    "CONFIG_KASAN_OUTLINE=y",
    "CONFIG_KASAN_VMALLOC=y",
    "CONFIG_KASAN_STACK=y",
]:
    if key in text:
        text = text.replace(key, f"# {key} is not set".replace("=y is not set", " is not set"))
        # fix botched replace
        text = text.replace(f"# {key} is not set", f"# {key[:-2]} is not set")
        print("disabled", key)

# cleaner KASAN disable
import re
text = re.sub(r'^CONFIG_KASAN[A-Z_]*=y\s*$', lambda m: f"# {m.group(0)[7:].split('=')[0] if False else m.group(0).split('=')[0][7:] }", text, flags=re.M)
# do proper
lines=[]
for line in text.splitlines(True):
    if re.match(r'^CONFIG_KASAN(_|=)', line) and line.strip().endswith('=y'):
        k=line.strip().split('=')[0]
        lines.append(f"# {k} is not set\n")
        print("off", k)
    else:
        lines.append(line)
text=''.join(lines)

# Ensure CONFIG_BBG=y
if "CONFIG_BBG=y" not in text:
    text += "\nCONFIG_BBG=y\n"
    print("set CONFIG_BBG=y")

p.write_text(text)
print("config updated")
# verify
for pat in ["CONFIG_LSM=", "CONFIG_BBG=", "CONFIG_KASAN"]:
    for line in p.read_text().splitlines():
        if line.startswith(pat) or line.startswith(f"# {pat}"):
            if "KASAN" in pat or pat in line:
                print(line)
PY

cd "$SRC"
export ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu-
yes "" 2>/dev/null | make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >"$LOGDIR/olddef-bbg.log" 2>&1 || true

echo "=== verify config ==="
grep -E 'CONFIG_BBG=|CONFIG_LSM=|CONFIG_KASAN' .config | head -20

# force rebuild relevant parts
rm -f arch/arm64/boot/Image vmlinux System.map
rm -rf drivers/baseband_guard/*.o drivers/baseband_guard/*/*.o 2>/dev/null || true

LOG="$LOGDIR/build-bbg-$(date +%Y%m%d-%H%M%S).log"
echo "Building -> $LOG"
set +e
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

if [ -f arch/arm64/boot/Image ]; then
  echo "=== BUILD SUCCESS ==="
  ls -la arch/arm64/boot/Image
  for s in ksu_ susfs_ hmbird bbg baseband ntsync rekernel tcp_bbr3; do
    n=$(grep -c "$s" System.map || true)
    echo "$s: $n"
  done
  grep -iE 'bbg|baseband' System.map | head -15 || true
  exit 0
fi
echo "=== FAIL ==="
grep -E 'error:|Error 1|Stop' "$LOG" | sort -u | tail -40
exit 1
