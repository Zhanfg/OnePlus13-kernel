#!/bin/bash
# M2 + M3 on 破星 6.6-final (fork tree)
# M1 vanilla already built separately; this produces:
#   M2: ReSukiSU + SuSFS
#   M3: M2 + BBG + Re:Kernel + 网络/IP_SET/ZRAM 等配置
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

mkdir -p "$LOGDIR" "$OUT_WIN"
cd "$SRC"

log() { echo "=== $* ==="; }
ensure_check_file() {
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
  [ -f drivers/starkernel/Kconfig ] || echo "# stub starkernel" > drivers/starkernel/Kconfig
  [ -f drivers/starkernel/Makefile ] || echo "obj-y :=" > drivers/starkernel/Makefile
}

pack_ak3() {
  local tag="$1"   # M2-RESUKISU / M3-FULL
  local note="$2"
  local img="arch/arm64/boot/Image"
  [ -f "$img" ] || { echo "missing Image"; return 1; }

  local ver
  ver=$(strings "$img" | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
  ver=${ver:-6.6.126}
  local uname_s
  uname_s=$(strings "$img" | grep -E 'Linux version 6\.6' | head -1 | cut -c1-160 || true)

  local stage="${ROOT}/ak3-brokestar-${tag}"
  rm -rf "$stage"
  mkdir -p "$stage"
  unzip -q "$AK3_REF" -d "$stage"
  cp -f "$img" "$stage/Image"
  rm -f "$stage/module.prop" 2>/dev/null || true
  if grep -q "kernel.string=" "$stage/anykernel.sh"; then
    sed -i "s/kernel.string=.*/kernel.string=v${ver} brokestar-${tag}/" "$stage/anykernel.sh"
  fi
  sed -i 's/^block=.*/block=boot/' "$stage/anykernel.sh" 2>/dev/null || true
  find "$stage" -name '*.sh' -o -name 'update-binary' | while read -r f; do sed -i 's/\r$//' "$f" 2>/dev/null || true; done
  chmod 755 "$stage/META-INF/com/google/android/update-binary" "$stage/tools/"* 2>/dev/null || true

  local name="v${ver}-OnePlus13-sun-AK3-BROKESTAR-${tag}-${STAMP}"
  local zip="${OUT_WIN}/${name}.zip"
  ( cd "$stage" && zip -r9 "$zip" . )
  sha256sum "$zip" | tee "${zip}.sha256"
  cp -f "$img" "${OUT_WIN}/v${ver}-Image-brokestar-${tag}"
  sha256sum "${OUT_WIN}/v${ver}-Image-brokestar-${tag}" | tee "${OUT_WIN}/v${ver}-Image-brokestar-${tag}.sha256"

  cat > "${OUT_WIN}/${tag}_FLASH_NOTE.txt" << EOF
破星 ${tag} 包
================
文件: ${name}.zip
Image: v${ver}-Image-brokestar-${tag}
uname 线索: ${uname_s}
说明: ${note}
刷法: ReSukiSU Manager → 刷写 AnyKernel3 → 选本 zip
成功: 过 Logo 进桌面；uname -r 含 6.6.126
失败: fastboot flash boot releases/restore/boot.img
生成: $(date -Is)
EOF
  echo "PACKED $zip"
}

build_image() {
  local phase="$1"
  local logf="${LOGDIR}/brokestar-${phase}-build-${STAMP}.log"
  log "Build Image (${phase}) -j${NPROC}"
  set +e
  set +o pipefail
  make ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu- -j"${NPROC}" Image 2>&1 | tee "$logf"
  local rc=${PIPESTATUS[0]}
  set -e
  set -o pipefail
  if [ ! -f arch/arm64/boot/Image ]; then
    echo "BUILD FAIL phase=$phase rc=$rc"
    grep -E 'error:|Error 1|fatal error:' "$logf" | sort -u | tail -50
    return 1
  fi
  ls -lah arch/arm64/boot/Image
  strings arch/arm64/boot/Image | grep -E 'Linux version 6\.6' | head -2
  return 0
}

apply_config_python() {
  python3 - "$@" << 'PY'
import re, sys
from pathlib import Path
p = Path(".config")
t = p.read_text()

def set_val(key, val):
    global t
    # val is 'y' / 'n' / '"string"'
    if val == "n":
        t2 = re.sub(rf"^{re.escape(key)}=.*$", f"# {key} is not set", t, flags=re.M)
        if t2 == t:
            if re.search(rf"^# {re.escape(key)} is not set", t, re.M):
                return
            t += f"\n# {key} is not set\n"
        else:
            t = t2
        print("off", key)
        return
    t2 = re.sub(rf"^# {re.escape(key)} is not set\s*$", f"{key}={val}", t, flags=re.M)
    if t2 != t:
        t = t2
        print("en", key, val)
        return
    if re.search(rf"^{re.escape(key)}=", t, re.M):
        t = re.sub(rf"^{re.escape(key)}=.*$", f"{key}={val}", t, flags=re.M)
        print("set", key, val)
    else:
        t += f"\n{key}={val}\n"
        print("app", key, val)

mode = sys.argv[1] if len(sys.argv) > 1 else "m2"

# common
set_val("CONFIG_KALLSYMS", "y")
set_val("CONFIG_KALLSYMS_ALL", "y")
set_val("CONFIG_KPROBES", "y")
set_val("CONFIG_HAVE_KPROBES", "y")
set_val("CONFIG_KPROBE_EVENTS", "y")

# ReSukiSU — use SUSFS as hook method (matches prior working 6.6 tree)
set_val("CONFIG_KSU", "y")
set_val("CONFIG_KSU_DEBUG", "n")
set_val("CONFIG_KSU_TRACEPOINT_HOOK", "n")
set_val("CONFIG_KSU_MANUAL_HOOK", "n")
set_val("CONFIG_KSU_SUSFS", "y")
for k in [
    "CONFIG_KSU_SUSFS_SUS_PATH",
    "CONFIG_KSU_SUSFS_SUS_MOUNT",
    "CONFIG_KSU_SUSFS_SUS_KSTAT",
    "CONFIG_KSU_SUSFS_SPOOF_UNAME",
    "CONFIG_KSU_SUSFS_ENABLE_LOG",
    "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS",
    "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG",
    "CONFIG_KSU_SUSFS_OPEN_REDIRECT",
    "CONFIG_KSU_SUSFS_SUS_MAP",
    "CONFIG_KSU_MULTI_MANAGER_SUPPORT",
]:
    set_val(k, "y")

if mode == "m3":
    # network
    set_val("CONFIG_TCP_CONG_ADVANCED", "y")
    set_val("CONFIG_TCP_CONG_BBR", "y")
    set_val("CONFIG_DEFAULT_TCP_CONG", '"bbr"')
    set_val("CONFIG_DEFAULT_BBR", "y")
    set_val("CONFIG_DEFAULT_CUBIC", "n")
    set_val("CONFIG_NET_SCH_FQ", "y")
    set_val("CONFIG_NET_SCH_FQ_CODEL", "y")
    set_val("CONFIG_NET_SCH_CAKE", "y")
    set_val("CONFIG_DEFAULT_FQ", "y")
    set_val("CONFIG_DEFAULT_FQ_CODEL", "n")
    # IP_SET
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
        "CONFIG_NETFILTER_XT_SET",
    ]:
        set_val(k, "y")
    # ZRAM prefs
    set_val("CONFIG_ZRAM", "y")
    set_val("CONFIG_ZRAM_WRITEBACK", "y")
    set_val("CONFIG_ZRAM_MULTI_COMP", "y")
    # BBG / ReKernel
    set_val("CONFIG_BBG", "y")
    set_val("CONFIG_REKERNEL", "y")
    set_val("CONFIG_NTSYNC", "y")
    # BBG LSM 必须写进 CONFIG_LSM（否则 Makefile 硬失败）
    import re as _re
    m = _re.search(r'^CONFIG_LSM="([^"]*)"', t, _re.M)
    if m and "baseband_guard" not in m.group(1):
        parts = [x.strip() for x in m.group(1).split(",") if x.strip()]
        if "selinux" in parts:
            parts.insert(parts.index("selinux"), "baseband_guard")
        else:
            parts.append("baseband_guard")
        t = _re.sub(r'^CONFIG_LSM="[^"]*"', 'CONFIG_LSM="' + ",".join(parts) + '"', t, flags=_re.M)
        print("set CONFIG_LSM with baseband_guard")
    # namespaces / overlay for modules
    for k in [
        "CONFIG_OVERLAY_FS",
        "CONFIG_TMPFS_XATTR",
        "CONFIG_TMPFS_POSIX_ACL",
        "CONFIG_PID_NS",
        "CONFIG_IPC_NS",
        "CONFIG_UTS_NS",
        "CONFIG_USER_NS",
        "CONFIG_NET_NS",
    ]:
        set_val(k, "y")

p.write_text(t)
print("config written mode=", mode)
PY
}

# ---------------------------------------------------------------------------
log "Source"
git log -1 --oneline
head -6 Makefile
ensure_check_file

# ---------------------------------------------------------------------------
log "M2: wire ReSukiSU (symlink, no unshallow)"
RESU="${PATCHES}/resukisu"
if [ ! -d "${RESU}/kernel" ]; then
  echo "missing $RESU/kernel"
  exit 1
fi
# Prefer local patches copy; keep git remote out of build path
rm -f drivers/kernelsu
ln -sfn "${RESU}/kernel" drivers/kernelsu
if ! grep -q 'kernelsu' drivers/Makefile; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
fi
if ! grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig; then
  # insert before last endmenu if possible
  if grep -q '^endmenu' drivers/Kconfig; then
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
  else
    printf '\nsource "drivers/kernelsu/Kconfig"\n' >> drivers/Kconfig
  fi
fi
ls -la drivers/kernelsu | head -3

# ---------------------------------------------------------------------------
log "M2: apply SuSFS GKI android15-6.6 patch"
SUSFS_PATCH="${PATCHES}/susfs/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
# also copy helper sources if present alongside patch
if [ -f "${PATCHES}/susfs/kernel_patches/fs/susfs.c" ]; then
  cp -f "${PATCHES}/susfs/kernel_patches/fs/susfs.c" fs/susfs.c
fi
if [ -d "${PATCHES}/susfs/kernel_patches/include/linux" ]; then
  cp -f "${PATCHES}/susfs/kernel_patches/include/linux/"*.h include/linux/ 2>/dev/null || true
fi
set +e
patch -p1 --forward --reject-file=- < "$SUSFS_PATCH" >"${LOGDIR}/susfs-apply-${STAMP}.log" 2>&1
rc=$?
set -e
echo "susfs patch rc=$rc"
tail -40 "${LOGDIR}/susfs-apply-${STAMP}.log" || true
# ensure fs/Makefile has susfs
if ! grep -q 'susfs.o' fs/Makefile; then
  sed -i '/obj-y :=/a obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile || \
    printf '\nobj-$(CONFIG_KSU_SUSFS) += susfs.o\n' >> fs/Makefile
fi
test -f fs/susfs.c && echo "fs/susfs.c ok" || echo "WARN: fs/susfs.c missing"
test -f include/linux/susfs.h && echo "susfs.h ok" || echo "WARN: susfs.h missing"

# ---------------------------------------------------------------------------
log "M2: defconfig + KSU config"
make ARCH=arm64 LLVM=1 CC=clang gki_defconfig 2>&1 | tee "${LOGDIR}/brokestar-m2-defconfig.log" | tail -15
ensure_check_file
scripts/config --file .config -d WERROR -d CONFIG_WERROR 2>/dev/null || true
scripts/config --file .config -d CONFIG_DEBUG_INFO_BTF 2>/dev/null || true
apply_config_python m2
set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang olddefconfig 2>&1 | tail -15 || true
set -o pipefail
echo "--- KSU config ---"
grep -E 'CONFIG_KSU|CONFIG_KSU_SUSFS|CONFIG_KSU_TRACE|CONFIG_KSU_MANUAL' .config | head -40

# ---------------------------------------------------------------------------
log "M2: compile"
if ! build_image m2; then
  echo "M2 build failed — stop before M3"
  exit 1
fi
pack_ak3 "M2-RESUKISU" "破星6.6.126 + ReSukiSU + SuSFS；无 BBG/ReKernel 额外魔改"

# ---------------------------------------------------------------------------
log "M3: Baseband Guard"
BBG_SRC="${PATCHES}/bbg"
rm -rf drivers/baseband_guard
mkdir -p drivers/baseband_guard
# copy sources only (not .o)
for f in Kconfig LICENSE Makefile baseband_guard.c baseband_guard.h blkdev_helper.c blkdev_helper.h kernel_compat.h sepatch.txt; do
  [ -f "${BBG_SRC}/$f" ] && cp -f "${BBG_SRC}/$f" "drivers/baseband_guard/$f"
done
# if setup expects security/, we use drivers path like prior tree
if ! grep -q 'baseband_guard' drivers/Makefile; then
  printf '\nobj-$(CONFIG_BBG) += baseband_guard/\n' >> drivers/Makefile
fi
if ! grep -q 'baseband_guard/Kconfig' drivers/Kconfig; then
  if grep -q '^endmenu' drivers/Kconfig; then
    sed -i '/^endmenu/i source "drivers/baseband_guard/Kconfig"' drivers/Kconfig
  else
    printf '\nsource "drivers/baseband_guard/Kconfig"\n' >> drivers/Kconfig
  fi
fi
ls drivers/baseband_guard/

# ---------------------------------------------------------------------------
log "M3: Re:Kernel integrate"
set +e
bash "${PATCHES}/re-kernel/Integrate/patches.sh" >"${LOGDIR}/rekernel-apply-${STAMP}.log" 2>&1
rk_rc=$?
set -e
echo "rekernel rc=$rk_rc"
tail -30 "${LOGDIR}/rekernel-apply-${STAMP}.log" || true
ls drivers/rekernel/ 2>/dev/null || echo "WARN: rekernel dir missing"

# ---------------------------------------------------------------------------
log "M3: unicode bypass (optional)"
UB="${PATCHES}/wildkernels_patches/common/unicode_bypass_fix_6.1+.patch"
if [ -f "$UB" ]; then
  set +e
  patch -p1 --forward --reject-file=- < "$UB" >"${LOGDIR}/unicode-${STAMP}.log" 2>&1
  echo "unicode rc=$?"
  tail -15 "${LOGDIR}/unicode-${STAMP}.log" || true
  set -e
fi

# ---------------------------------------------------------------------------
log "M3: config extras"
apply_config_python m3
set +o pipefail
make ARCH=arm64 LLVM=1 CC=clang olddefconfig 2>&1 | tail -15 || true
set -o pipefail
echo "--- M3 config snapshot ---"
grep -E 'CONFIG_KSU=|CONFIG_KSU_SUSFS=|CONFIG_BBG=|CONFIG_REKERNEL=|CONFIG_DEFAULT_TCP_CONG|CONFIG_NET_SCH_FQ=|CONFIG_IP_SET=|CONFIG_NTSYNC=|CONFIG_TCP_CONG_BBR=' .config | head -40

# invalidate hot paths
rm -f arch/arm64/boot/Image vmlinux System.map .tmp_vmlinux* vmlinux.o 2>/dev/null || true

log "M3: compile"
if ! build_image m3; then
  echo "M3 build failed — M2 package still valid"
  exit 1
fi
pack_ak3 "M3-FULL" "破星6.6.126 + ReSukiSU/SuSFS + BBG + Re:Kernel + BBR/FQ/CAKE/IP_SET + NTSYNC；树内 BORE/HMBIRD 保留。无独立 BBR3 源码则默认 BBR。"

# ---------------------------------------------------------------------------
log "Summary index"
cat > "${OUT_WIN}/BUILD_ALL_NOTES.txt" << EOF
破星全阶段产物（编译机已完成，待真机验证）
==========================================
日期: $(date -Is)
源码: Zhanfg/android_kernel_common_oneplus_sm8750 @ 6.6-final (+ 本地集成)
工具链: system clang/LLVM

建议刷机顺序（明早）:
1) M1 VANILLA — 只验证 6.6.126 能否开机
   $(ls -1 ${OUT_WIN}/v6.6.126-*-M1-VANILLA-*.zip 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null || echo M1 zip)
2) M2 RESUKISU — 验证 Root/Manager
   $(ls -1 ${OUT_WIN}/v6.6.126-*-M2-RESUKISU-*.zip 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null || echo M2 zip)
3) M3 FULL — 全功能
   $(ls -1 ${OUT_WIN}/v6.6.126-*-M3-FULL-*.zip 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null || echo M3 zip)

任一步失败: fastboot flash boot releases/restore/boot.img
不要再刷 v6.6.89 旧包。

M1 无 Root；M2 起含 ReSukiSU（内联 SuSFS hook 模式）。
M3 另含 BBG、Re:Kernel、网络默认 BBR+FQ、IP_SET、CAKE 等。
EOF

ls -lah "${OUT_WIN}"/v6.6.126-* "${OUT_WIN}"/*FLASH_NOTE.txt "${OUT_WIN}/BUILD_ALL_NOTES.txt" 2>/dev/null
echo "ALL DONE"
