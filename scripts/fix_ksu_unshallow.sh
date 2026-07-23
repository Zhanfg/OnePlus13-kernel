#!/bin/bash
set -e
pkill -9 -f 'git fetch --unshallow' 2>/dev/null || true
pkill -9 -f 'git-remote-https' 2>/dev/null || true
pkill -9 -f 'index-pack' 2>/dev/null || true
pkill -9 -f 'make ARCH=arm64' 2>/dev/null || true
sleep 1

python3 - <<'PY'
from pathlib import Path
p = Path("/home/axymorrsen/op13-kernel/patches/resukisu/kernel/Kbuild")
lines = p.read_text().splitlines(True)
out = []
for line in lines:
    if "fetch --unshallow" in line and not line.lstrip().startswith("#"):
        out.append("# disabled offline: " + line)
        print("commented unshallow")
    else:
        out.append(line)
p.write_text("".join(out))
for i, l in enumerate(p.read_text().splitlines(), 1):
    if "unshallow" in l or "KSU_LOCAL_VERSION" in l:
        print(f"{i}: {l[:120]}")
PY

SH=/home/axymorrsen/op13-kernel/patches/resukisu/.git/shallow
if [ -f "$SH" ]; then
  mv "$SH" "${SH}.bak"
  echo "renamed shallow"
fi
rm -f /home/axymorrsen/op13-kernel/patches/resukisu/.git/shallow.lock

nohup bash /mnt/d/OnePlus13-kernel/scripts/wsl_rebuild.sh > /home/axymorrsen/op13-kernel/logs/build7-wrapper.log 2>&1 &
echo REBUILD_STARTED
sleep 5
bash /mnt/d/OnePlus13-kernel/scripts/wsl_status.sh
