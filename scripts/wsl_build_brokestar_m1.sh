#!/bin/bash
# M1: 破星 6.6-final 干净 Image（无额外补丁）
set -euo pipefail

# WSL 失效本地代理会让 git 挂掉
export http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= all_proxy=

ROOT=/home/axymorrsen/op13-kernel
SRC="${ROOT}/brokestar-6.6"
LOGDIR="${ROOT}/logs"
OUT_WIN=/mnt/d/OnePlus13-kernel/releases
STAMP=$(date +%Y%m%d-%H%M)
mkdir -p "$LOGDIR" "$OUT_WIN"

cd "$SRC"
echo "=== 源码 ==="
git log -1 --oneline
head -6 Makefile

export ARCH=arm64
export LLVM=1
export CC=clang
export CROSS_COMPILE=aarch64-linux-gnu-
export KCFLAGS="${KCFLAGS:-} -Wno-error"

# 子模块 StarKernel 私有：失败则用 stub（破星 kconfig 仍 source 它）
git -c http.proxy= -c https.proxy= submodule update --init --depth 1 2>&1 \
  | tee "$LOGDIR/brokestar-submodule.log" | tail -20 || true

# 破星 scripts/kconfig/Makefile 会从「内核树根」执行 ../check_file.sh
# 即要求 $ROOT/check_file.sh 存在；同时补 drivers/starkernel 空壳
cat > "${ROOT}/check_file.sh" << 'EOF'
#!/bin/bash
set -e
SK="drivers/starkernel"
mkdir -p "$SK"
[ -f "$SK/Kconfig" ] || echo "# stub starkernel (submodule private/missing)" > "$SK/Kconfig"
[ -f "$SK/Makefile" ] || echo "obj-y :=" > "$SK/Makefile"
exit 0
EOF
chmod +x "${ROOT}/check_file.sh"
mkdir -p drivers/starkernel
[ -f drivers/starkernel/Kconfig ] || echo "# stub starkernel" > drivers/starkernel/Kconfig
[ -f drivers/starkernel/Makefile ] || echo "obj-y :=" > drivers/starkernel/Makefile
# 本地 git 忽略 stub，避免污染 fork（若已是 submodule 空目录则无妨）
if [ -d .git ]; then
  grep -qxF 'drivers/starkernel/' .git/info/exclude 2>/dev/null || echo 'drivers/starkernel/' >> .git/info/exclude
fi

echo "=== 工具链 ==="
clang --version | head -1
which ld.lld || true
which aarch64-linux-gnu-ld || true

echo "=== defconfig ==="
# 干净配置：gki_defconfig（含树内 BORE/HMBIRD 默认）
make ARCH=arm64 LLVM=1 CC=clang mrproper 2>&1 | tail -5 || true
# mrproper 可能清掉 stub，重建
mkdir -p drivers/starkernel
[ -f drivers/starkernel/Kconfig ] || echo "# stub starkernel" > drivers/starkernel/Kconfig
[ -f drivers/starkernel/Makefile ] || echo "obj-y :=" > drivers/starkernel/Makefile
make ARCH=arm64 LLVM=1 CC=clang gki_defconfig 2>&1 | tee "$LOGDIR/brokestar-defconfig.log" | tail -30

# 强制关 Werror 类易炸项（若存在）
scripts/config --file .config -d WERROR -d CONFIG_WERROR 2>/dev/null || true
scripts/config --file .config -d CONFIG_DEBUG_INFO_BTF 2>/dev/null || true
# 保留 kallsyms 便于后续 KSU
scripts/config --file .config -e KALLSYMS -e KALLSYMS_ALL 2>/dev/null || true
# 避免 yes|make 在 pipefail 下因 SIGPIPE 误杀整脚本
set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang olddefconfig 2>&1 | tail -15 || true
set -o pipefail

echo "=== 编译 Image (-j$(nproc)) ==="
LOG="$LOGDIR/brokestar-m1-build-${STAMP}.log"
set +e
set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
set -o pipefail

if [ ! -f arch/arm64/boot/Image ]; then
  echo "=== BUILD FAIL rc=$rc ==="
  grep -E 'error:|Error 1|fatal' "$LOG" | sort -u | tail -40
  exit 1
fi

echo "=== BUILD OK ==="
ls -lah arch/arm64/boot/Image
strings arch/arm64/boot/Image | grep -E 'Linux version' | head -2
VER=$(strings arch/arm64/boot/Image | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
VER=${VER:-6.6.126}

# 打包：完全照抄能刷的 AK3 结构
AK3_REF=/mnt/d/OnePlus13-kernel/releases/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip
STAGE=/home/axymorrsen/op13-kernel/ak3-brokestar-m1
rm -rf "$STAGE"
mkdir -p "$STAGE"
unzip -q "$AK3_REF" -d "$STAGE"
cp -f arch/arm64/boot/Image "$STAGE/Image"
# 改 kernel.string，去掉强制 KPM 交互失败风险：保留脚本但默认跳过逻辑已有 timeout
# 覆盖 anykernel 为与参考包相同逻辑（已是 boot）
# 确保无 module.prop
rm -f "$STAGE/module.prop" 2>/dev/null || true

# 微调 kernel.string
if grep -q "kernel.string=" "$STAGE/anykernel.sh"; then
  sed -i "s/kernel.string=.*/kernel.string=v${VER} brokestar-M1 vanilla (BORE tree, no extra patches)/" "$STAGE/anykernel.sh"
fi
# 保证 block=boot
sed -i 's/^block=.*/block=boot/' "$STAGE/anykernel.sh" 2>/dev/null || true

find "$STAGE" -name '*.sh' -o -name 'update-binary' | while read f; do sed -i 's/\r$//' "$f" 2>/dev/null || true; done
chmod 755 "$STAGE/META-INF/com/google/android/update-binary" "$STAGE/tools/"* 2>/dev/null || true

NAME="v${VER}-OnePlus13-sun-AK3-BROKESTAR-M1-VANILLA-${STAMP}"
ZIP="$OUT_WIN/${NAME}.zip"
( cd "$STAGE" && zip -r9 "$ZIP" . )
sha256sum "$ZIP" | tee "${ZIP}.sha256"
cp -f arch/arm64/boot/Image "$OUT_WIN/v${VER}-Image-brokestar-m1"
sha256sum "$OUT_WIN/v${VER}-Image-brokestar-m1" | tee "$OUT_WIN/v${VER}-Image-brokestar-m1.sha256"

cat > "$OUT_WIN/M1_FLASH_NOTE.txt" << EOF
M1 干净破星 Image 测试包
========================
文件: ${NAME}.zip
内核: 破星 6.6-final，无额外 ReSukiSU/SuSFS 等（树内 BORE 保留）
目的: 验证 6.6.126 GKI Image 能否在 PJZ110 16.0.9.401 上开机

刷法: ReSukiSU → 刷写 AnyKernel3 → 选本 zip
成功标志:
  - 能过 Logo 进桌面
  - uname -r 含 6.6.126 或类似
失败:
  - fastboot flash boot releases/restore/boot.img 救砖
  - 把现象发回，再调工具链/配置

生成: $(date -Is)
EOF

echo "=== M1 产物 ==="
ls -lah "$ZIP"
echo "DONE"
