#!/bin/bash
# Fix BBG CONFIG_LSM and rebuild M3 FULL package only
set -euo pipefail
export http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= all_proxy=

ROOT=/home/axymorrsen/op13-kernel
SRC="${ROOT}/brokestar-6.6"
PATCHES="${ROOT}/patches"
LOGDIR="${ROOT}/logs"
OUT_WIN=/mnt/d/OnePlus13-kernel/releases
AK3_REF="${OUT_WIN}/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip"
STAMP=$(date +%Y%m%d-%H%M)
NPROC=$(nproc)

cd "$SRC"
mkdir -p "$LOGDIR"

# ensure parent check_file
cat > "${ROOT}/check_file.sh" << 'EOF'
#!/bin/bash
set -e
SK="drivers/starkernel"
mkdir -p "$SK"
[ -f "$SK/Kconfig" ] || echo "# stub" > "$SK/Kconfig"
[ -f "$SK/Makefile" ] || echo "obj-y :=" > "$SK/Makefile"
exit 0
EOF
chmod +x "${ROOT}/check_file.sh"

echo "=== ensure BBG tracing sources ==="
if [ -d "${PATCHES}/bbg/tracing" ]; then
  mkdir -p drivers/baseband_guard/tracing
  cp -a "${PATCHES}/bbg/tracing/." drivers/baseband_guard/tracing/
fi
# if Makefile expects tracing/tracing.o path
if [ -f drivers/baseband_guard/tracing/tracing.c ]; then
  echo "tracing.c ok"
elif [ -f "${PATCHES}/bbg/tracing/tracing.c" ]; then
  mkdir -p drivers/baseband_guard/tracing
  cp -f "${PATCHES}/bbg/tracing/tracing.c" drivers/baseband_guard/tracing/
fi
ls -la drivers/baseband_guard/ || true
ls -la drivers/baseband_guard/tracing/ 2>/dev/null || true

echo "=== fix CONFIG_LSM for baseband_guard ==="
python3 << 'PY'
from pathlib import Path
import re
p = Path(".config")
t = p.read_text()

def fix_lsm(m):
    val = m.group(1)
    if "baseband_guard" in val:
        return m.group(0)
    parts = [x.strip() for x in val.split(",") if x.strip()]
    if "selinux" in parts:
        i = parts.index("selinux")
        parts.insert(i, "baseband_guard")
    else:
        parts.append("baseband_guard")
    return 'CONFIG_LSM="' + ",".join(parts) + '"'

t2, n = re.subn(r'^CONFIG_LSM="([^"]*)"', fix_lsm, t, flags=re.M)
if n == 0:
    t2 = t + '\nCONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,baseband_guard,selinux,smack,tomoyo,apparmor,bpf"\n'
# ensure BBG/REKERNEL
for k in ("CONFIG_BBG=y", "CONFIG_REKERNEL=y"):
    key = k.split("=")[0]
    if re.search(rf"^{key}=", t2, re.M):
        t2 = re.sub(rf"^{key}=.*$", k, t2, flags=re.M)
    elif re.search(rf"^# {key} is not set", t2, re.M):
        t2 = re.sub(rf"^# {key} is not set", k, t2, flags=re.M)
    else:
        t2 += f"\n{k}\n"
p.write_text(t2)
print(re.search(r"^CONFIG_LSM=.*", p.read_text(), re.M).group(0))
print("BBG", re.search(r"^CONFIG_BBG=.*", p.read_text(), re.M))
print("REKERNEL", re.search(r"^CONFIG_REKERNEL=.*", p.read_text(), re.M))
PY

set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang olddefconfig 2>&1 | tail -8 || true
set -o pipefail
grep -E 'CONFIG_LSM=|CONFIG_BBG=|CONFIG_REKERNEL=' .config

echo "=== probe BBG ==="
set +e
make ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu- drivers/baseband_guard/ 2>&1 | tee "${LOGDIR}/bbg-fix-${STAMP}.log" | tail -40
bbg_rc=${PIPESTATUS[0]}
set -e
echo "BBG_RC=$bbg_rc"
if [ "$bbg_rc" -ne 0 ]; then
  echo "BBG still failing — dump log head errors"
  grep -E 'error:|Error|fatal|\*\*\*' "${LOGDIR}/bbg-fix-${STAMP}.log" | head -40
  exit 1
fi

echo "=== probe Re:Kernel ==="
set +e
make ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu- drivers/rekernel/ 2>&1 | tee "${LOGDIR}/rekernel-fix-${STAMP}.log" | tail -30
rk_rc=${PIPESTATUS[0]}
set -e
echo "RK_RC=$rk_rc"
if [ "$rk_rc" -ne 0 ]; then
  grep -E 'error:|Error|fatal|\*\*\*' "${LOGDIR}/rekernel-fix-${STAMP}.log" | head -40
  exit 1
fi

echo "=== rebuild Image (M3) ==="
rm -f arch/arm64/boot/Image vmlinux System.map .tmp_vmlinux* 2>/dev/null || true
LOG="${LOGDIR}/brokestar-m3-rebuild-${STAMP}.log"
set +e
set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"${NPROC}" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
set -o pipefail

if [ ! -f arch/arm64/boot/Image ]; then
  echo "M3 REBUILD FAIL rc=$rc"
  grep -E 'error:|Error 1|fatal error:|\*\*\*' "$LOG" | grep -v 'Could not read' | sort -u | tail -40
  exit 1
fi

echo "=== pack M3 ==="
ver=$(strings arch/arm64/boot/Image | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
ver=${ver:-6.6.126}
uname_s=$(strings arch/arm64/boot/Image | grep -E 'Linux version 6\.6' | head -1 | cut -c1-160 || true)
STAGE="${ROOT}/ak3-brokestar-M3-FULL"
rm -rf "$STAGE"
mkdir -p "$STAGE"
unzip -q "$AK3_REF" -d "$STAGE"
cp -f arch/arm64/boot/Image "$STAGE/Image"
rm -f "$STAGE/module.prop" 2>/dev/null || true
sed -i "s/kernel.string=.*/kernel.string=v${ver} brokestar-M3-FULL/" "$STAGE/anykernel.sh"
sed -i 's/^block=.*/block=boot/' "$STAGE/anykernel.sh" 2>/dev/null || true
find "$STAGE" -name '*.sh' -o -name 'update-binary' | while read -r f; do sed -i 's/\r$//' "$f" 2>/dev/null || true; done
chmod 755 "$STAGE/META-INF/com/google/android/update-binary" "$STAGE/tools/"* 2>/dev/null || true
NAME="v${ver}-OnePlus13-sun-AK3-BROKESTAR-M3-FULL-${STAMP}"
ZIP="${OUT_WIN}/${NAME}.zip"
( cd "$STAGE" && zip -r9 "$ZIP" . )
sha256sum "$ZIP" | tee "${ZIP}.sha256"
cp -f arch/arm64/boot/Image "${OUT_WIN}/v${ver}-Image-brokestar-M3-FULL"
sha256sum "${OUT_WIN}/v${ver}-Image-brokestar-M3-FULL" | tee "${OUT_WIN}/v${ver}-Image-brokestar-M3-FULL.sha256"

cat > "${OUT_WIN}/M3-FULL_FLASH_NOTE.txt" << EOF
破星 M3 FULL 包
================
文件: ${NAME}.zip
uname 线索: ${uname_s}
内容: ReSukiSU+SuSFS + BBG(LSM) + Re:Kernel + BBR/FQ/CAKE/IP_SET + NTSYNC；树内 BORE/HMBIRD
刷法: ReSukiSU Manager → AnyKernel3 → 本 zip
失败: fastboot flash boot releases/restore/boot.img
生成: $(date -Is)
EOF

cat > "${OUT_WIN}/BUILD_ALL_NOTES.txt" << EOF
破星全阶段产物（编译机已完成，待真机验证）
==========================================
日期: $(date -Is)
源码: fork Zhanfg/android_kernel_common_oneplus_sm8750 @ 6.6-final + 本地集成
工具链: Ubuntu clang 21 + LLD

建议刷机顺序（明早）:
1) M1 VANILLA — 只验证 6.6.126 能否开机
   $(basename $(ls -1 ${OUT_WIN}/v6.6.126-*-M1-VANILLA-*.zip 2>/dev/null | head -1))
2) M2 RESUKISU — 验证 Root/Manager
   $(basename $(ls -1 ${OUT_WIN}/v6.6.126-*-M2-RESUKISU-*.zip 2>/dev/null | head -1))
3) M3 FULL — 全功能
   $(basename "$ZIP")

任一步失败: fastboot flash boot releases/restore/boot.img
不要再刷 v6.6.89 旧包。

说明:
- M1: 干净破星（BORE/HMBIRD）
- M2: + ReSukiSU + SuSFS
- M3: + BBG(CONFIG_LSM) + Re:Kernel + 默认 BBR+FQ + IP_SET/CAKE 等
- 树内无独立 BBR3 源码，故默认 BBR（非 cubic）
EOF

ls -lah "$ZIP" "${OUT_WIN}/v${ver}-Image-brokestar-M3-FULL" "${OUT_WIN}/BUILD_ALL_NOTES.txt"
echo "M3 DONE"
