#!/bin/bash
# M4-SAFE: 按「能刷 6.6.144」配置对齐破星 6.6.126 干净 Image
# 根因分析：M1-M3 反复重启，M1 也挂 → 不是 ReSukiSU，是基线编译/配置
# 能刷包差异：无 ThinLTO、无 Polly、无 ARCH_ORYON、无 BORE；Android clang r510928
# 本脚本：关掉上述激进项；暂仍用系统 clang（无 Android 预编译工具链时的最小修复）
set -euo pipefail
export http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= all_proxy=

ROOT=/home/axymorrsen/op13-kernel
SRC="${ROOT}/brokestar-6.6"
LOGDIR="${ROOT}/logs"
OUT_WIN=/mnt/d/OnePlus13-kernel/releases
AK3_REF="${OUT_WIN}/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip"
STAMP=$(date +%Y%m%d-%H%M)
NPROC=$(nproc)

mkdir -p "$LOGDIR" "$OUT_WIN"
cd "$SRC"

echo "=== reset tree to clean 6.6-final (drop M2/M3 dirty) ==="
# keep origin/upstream remotes
git checkout --force 6.6-final
git reset --hard origin/6.6-final 2>/dev/null || git reset --hard HEAD
git clean -fdx -e '.config' 2>/dev/null || git clean -fdx
# remove leftover symlinks/stubs from M2/M3
rm -f drivers/kernelsu 2>/dev/null || true
rm -rf drivers/baseband_guard drivers/rekernel 2>/dev/null || true
rm -f fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h 2>/dev/null || true

# parent check_file + starkernel stub
cat > "${ROOT}/check_file.sh" << 'EOF'
#!/bin/bash
set -e
SK="drivers/starkernel"
mkdir -p "$SK"
[ -f "$SK/Kconfig" ] || echo "# stub starkernel" > "$SK/Kconfig"
[ -f "$SK/Makefile" ] || echo "obj-y :=" > "$SK/Makefile"
exit 0
EOF
chmod +x "${ROOT}/check_file.sh"
mkdir -p drivers/starkernel
echo "# stub" > drivers/starkernel/Kconfig
echo "obj-y :=" > drivers/starkernel/Makefile

echo "=== HEAD ==="
git log -1 --oneline
head -6 Makefile

export ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu-
export KCFLAGS="${KCFLAGS:-} -Wno-error"

echo "=== toolchain ==="
clang --version | head -1

echo "=== mrproper + gki_defconfig ==="
make ARCH=arm64 LLVM=1 CC=clang mrproper 2>&1 | tail -5 || true
mkdir -p drivers/starkernel
echo "# stub" > drivers/starkernel/Kconfig
echo "obj-y :=" > drivers/starkernel/Makefile
make ARCH=arm64 LLVM=1 CC=clang gki_defconfig 2>&1 | tee "${LOGDIR}/m4-defconfig.log" | tail -15

echo "=== align to working 6.6.144 config (disable bootloop suspects) ==="
# Working Image config: no LTO thin, no POLLY, no ARCH_ORYON, no BORE; has HMBIRD, CFI, KASAN_HW_TAGS
scripts/config --file .config \
  -d LLVM_POLLY \
  -d ARCH_ORYON \
  -d SCHED_BORE \
  -d LTO_CLANG \
  -d LTO_CLANG_THIN \
  -d LTO_CLANG_FULL \
  -d LTO \
  --set-str LOCALVERSION "-4k-safe" \
  -d LOCALVERSION_AUTO \
  -d WERROR \
  -d CONFIG_WERROR \
  -d DEBUG_INFO_BTF \
  -e KALLSYMS \
  -e KALLSYMS_ALL \
  2>/dev/null || true

# also via python for robustness
python3 << 'PY'
from pathlib import Path
import re
p = Path(".config")
t = p.read_text()

def off(k):
    global t
    t = re.sub(rf"^{re.escape(k)}=.*$", f"# {k} is not set", t, flags=re.M)
    if not re.search(rf"^# {re.escape(k)} is not set", t, re.M) and not re.search(rf"^{re.escape(k)}=", t, re.M):
        t += f"\n# {k} is not set\n"
    print("off", k)

def on(k, val="y"):
    global t
    t2 = re.sub(rf"^# {re.escape(k)} is not set\s*$", f"{k}={val}", t, flags=re.M)
    if t2 != t:
        t = t2; print("en", k); return
    if re.search(rf"^{re.escape(k)}=", t, re.M):
        t = re.sub(rf"^{re.escape(k)}=.*$", f"{k}={val}", t, flags=re.M); print("set", k, val)
    else:
        t += f"\n{k}={val}\n"; print("app", k, val)

for k in [
    "CONFIG_LLVM_POLLY",
    "CONFIG_ARCH_ORYON",
    "CONFIG_SCHED_BORE",
    "CONFIG_LTO_CLANG",
    "CONFIG_LTO_CLANG_THIN",
    "CONFIG_LTO_CLANG_FULL",
    "CONFIG_LTO",
    "CONFIG_LOCALVERSION_AUTO",
]:
    off(k)
on("CONFIG_LOCALVERSION", '"-4k-safe"')
# keep HMBIRD like working
on("CONFIG_HMBIRD_SCHED", "y")
on("CONFIG_KALLSYMS", "y")
on("CONFIG_KALLSYMS_ALL", "y")
p.write_text(t)
PY

set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang olddefconfig 2>&1 | tail -12 || true
set -o pipefail

echo "=== verify safe config ==="
grep -E 'CONFIG_LLVM_POLLY|CONFIG_ARCH_ORYON|CONFIG_SCHED_BORE|CONFIG_LTO|CONFIG_LTO_CLANG|CONFIG_HMBIRD|CONFIG_LOCALVERSION|CONFIG_CFI_CLANG' .config | head -30

# sanity: Makefile must not inject -mcpu=oryon-1 / polly when configs off
echo "=== dry-run one file flags sample ==="
# after prepare
make ARCH=arm64 LLVM=1 CC=clang prepare 2>&1 | tail -10 || true

echo "=== build Image -j${NPROC} ==="
LOG="${LOGDIR}/brokestar-m4-safe-${STAMP}.log"
set +e
set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"${NPROC}" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
set -o pipefail

if [ ! -f arch/arm64/boot/Image ]; then
  echo "M4 BUILD FAIL rc=$rc"
  grep -E 'error:|Error 1|fatal' "$LOG" | grep -v 'Could not read' | sort -u | tail -40
  exit 1
fi

echo "=== BUILD OK ==="
ls -lah arch/arm64/boot/Image
strings arch/arm64/boot/Image | grep -E 'Linux version 6\.6' | head -2
# ensure polly/oryon not in build log for kernel C files
if grep -q 'mcpu=oryon' "$LOG"; then
  echo "WARN: still saw mcpu=oryon in log"
else
  echo "OK: no mcpu=oryon in build log"
fi
if grep -q '\-polly' "$LOG"; then
  echo "WARN: still saw polly in log"
else
  echo "OK: no polly in build log"
fi

VER=$(strings arch/arm64/boot/Image | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
VER=${VER:-6.6.126}
STAGE="${ROOT}/ak3-brokestar-m4-safe"
rm -rf "$STAGE"; mkdir -p "$STAGE"
unzip -q "$AK3_REF" -d "$STAGE"
cp -f arch/arm64/boot/Image "$STAGE/Image"
rm -f "$STAGE/module.prop" 2>/dev/null || true
sed -i "s/kernel.string=.*/kernel.string=v${VER} brokestar-M4-SAFE (no LTO\/Polly\/Oryon\/BORE)/" "$STAGE/anykernel.sh"
sed -i 's/^block=.*/block=boot/' "$STAGE/anykernel.sh"
find "$STAGE" -name '*.sh' -o -name 'update-binary' | while read f; do sed -i 's/\r$//' "$f" 2>/dev/null || true; done
chmod 755 "$STAGE/META-INF/com/google/android/update-binary" "$STAGE/tools/"* 2>/dev/null || true
NAME="v${VER}-OnePlus13-sun-AK3-BROKESTAR-M4-SAFE-${STAMP}"
ZIP="${OUT_WIN}/${NAME}.zip"
( cd "$STAGE" && zip -r9 "$ZIP" . )
sha256sum "$ZIP" | tee "${ZIP}.sha256"
cp -f arch/arm64/boot/Image "${OUT_WIN}/v${VER}-Image-brokestar-m4-safe"
sha256sum "${OUT_WIN}/v${VER}-Image-brokestar-m4-safe" | tee "${OUT_WIN}/v${VER}-Image-brokestar-m4-safe.sha256"

cat > "${OUT_WIN}/M4_SAFE_FLASH_NOTE.txt" << EOF
M4-SAFE 测试包（针对 M1-M3 反复重启）
======================================
文件: ${NAME}.zip
基线: 破星 6.6.126，相对能刷 6.6.144 配置对齐：
  - 关闭 ThinLTO
  - 关闭 LLVM Polly
  - 关闭 ARCH_ORYON (-mcpu=oryon-1)
  - 关闭 SCHED_BORE
  - 保留 HMBIRD（能刷包也有）
  - LOCALVERSION=-4k-safe
工具链: 仍为系统 clang（尚未换 Android r510928）
目的: 验证「激进优化」是否为重启根因

刷法: ReSukiSU Manager → AnyKernel3 → 本 zip
成功: 过 Logo 进桌面；uname 含 6.6.126 与 4k-safe
失败: fastboot flash boot releases/restore/boot.img
      下一步将换 Android clang / 或改 schqiushui 同源树

生成: $(date -Is)
EOF

# analysis note
cat > "${OUT_WIN}/BOOTLOOP_ANALYSIS.txt" << EOF
M1/M2/M3 全部失败（反复重启）分析
================================
结论: 不是 ReSukiSU/BBG 问题——M1 vanilla 也挂。

能刷包 6.6.144 (schqiushui) vs 我们的 M1 关键差异:
1) 工具链: Android clang 18 r510928  vs  Ubuntu clang 21.1.8
2) ThinLTO: 关 vs 开
3) Polly: 关 vs 开（破星 Makefile 在 CONFIG_LLVM_POLLY 时注入大量 -mllvm -polly）
4) ARCH_ORYON: 关 vs 开（注入 -mcpu=oryon-1）
5) SCHED_BORE: 关 vs 开
6) HMBIRD: 两边都开
7) Image 大小: ~36MB vs ~30MB

反复重启典型于早期 kernel panic（错误 codegen / CFI / 调度 / 模块 ABI）。

M4-SAFE 已先消 2-5；若仍挂，优先:
A) 安装 Android clang r510928 再编
B) 改用与能刷包同源/同策略的树（schqiushui 或官方 GKI 流程）
C) 抓 last_kmsg / pstore 确认 panic 点

EOF

ls -lah "$ZIP"
echo "M4-SAFE DONE"
