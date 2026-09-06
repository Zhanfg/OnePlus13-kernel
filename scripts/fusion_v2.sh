#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/configs/fusion_v2_sources.lock"
WORK_DIR="${FUSION_WORK_DIR:-$ROOT_DIR/.work/fusion-v2}"
DEPS_DIR="$WORK_DIR/deps"

log() { printf '[fusion-v2] %s\n' "$*"; }
die() { printf '[fusion-v2][ERROR] %s\n' "$*" >&2; exit 1; }

[[ -f "$LOCK_FILE" ]] || die "missing lock file: $LOCK_FILE"
# shellcheck disable=SC1090
source "$LOCK_FILE"

usage() {
  cat <<'EOF'
Usage:
  scripts/fusion_v2.sh fetch
  KERNEL_PLATFORM=/path/to/kernel_platform scripts/fusion_v2.sh integrate-root
  KERNEL_PLATFORM=/path/to/kernel_platform scripts/fusion_v2.sh verify-source
  scripts/fusion_v2.sh build-kpatch-next
  scripts/fusion_v2.sh patch-image /path/to/Image /path/to/Image.kpatch-next

Architecture:
  OnePlus common -> ReSukiSU + SUSFS 2.3.x -> build Image -> KPatch-Next -> AK3

Important:
  - ReSukiSU remains the only root core.
  - SUSFS official-KernelSU 10_enable_susfs_for_ksu.patch is intentionally NOT applied.
  - KPatch-Next is a post-build Image patch/KPM runtime, not a root core.
EOF
}

clone_pinned() {
  local name="$1" repo="$2" commit="$3" dest="$4"
  if [[ -d "$dest/.git" ]]; then
    log "reuse $name cache: $dest"
  else
    rm -rf "$dest"
    git clone --filter=blob:none --no-checkout "$repo" "$dest"
  fi
  git -C "$dest" fetch --force --depth=1 origin "$commit"
  git -C "$dest" checkout --detach "$commit"
  local actual
  actual="$(git -C "$dest" rev-parse HEAD)"
  [[ "$actual" == "$commit" ]] || die "$name pin mismatch: expected $commit got $actual"
  log "$name pinned at $actual"
}

fetch_deps() {
  mkdir -p "$DEPS_DIR"
  clone_pinned "ReSukiSU" "$RESUKISU_REPO" "$RESUKISU_COMMIT" "$DEPS_DIR/resukisu"
  clone_pinned "SUSFS" "$SUSFS_REPO" "$SUSFS_COMMIT" "$DEPS_DIR/susfs"
  clone_pinned "KPatch-Next" "$KPATCH_NEXT_REPO" "$KPATCH_NEXT_COMMIT" "$DEPS_DIR/kpatch-next"
}

require_platform() {
  : "${KERNEL_PLATFORM:?set KERNEL_PLATFORM to the complete OnePlus kernel_platform directory}"
  [[ -d "$KERNEL_PLATFORM/common/.git" ]] || die "not a complete kernel_platform/common git tree: $KERNEL_PLATFORM/common"
  [[ -d "$KERNEL_PLATFORM/oplus/build" ]] || die "missing OnePlus OKI build tree: $KERNEL_PLATFORM/oplus/build"
}

require_clean_common() {
  local common="$KERNEL_PLATFORM/common"
  git -C "$common" diff --quiet || die "common worktree has unstaged changes"
  git -C "$common" diff --cached --quiet || die "common worktree has staged changes"
  [[ -z "$(git -C "$common" ls-files --others --exclude-standard | head -n1)" ]] || die "common worktree has untracked files"
}

install_resukisu() {
  local common="$KERNEL_PLATFORM/common"
  local dst="$KERNEL_PLATFORM/KernelSU"
  local makefile="$common/drivers/Makefile"
  local kconfig="$common/drivers/Kconfig"

  [[ -f "$makefile" && -f "$kconfig" ]] || die "common drivers Makefile/Kconfig missing"
  rm -rf "$dst"
  git clone --no-checkout "$RESUKISU_REPO" "$dst"
  git -C "$dst" fetch --force --depth=1 origin "$RESUKISU_COMMIT"
  git -C "$dst" checkout --detach "$RESUKISU_COMMIT"
  [[ "$(git -C "$dst" rev-parse HEAD)" == "$RESUKISU_COMMIT" ]] || die "ReSukiSU checkout mismatch"

  # ReSukiSU's supported source-tree integration model: drivers/kernelsu -> KernelSU/kernel.
  rm -rf "$common/drivers/kernelsu"
  ln -s "$(realpath --relative-to="$common/drivers" "$dst/kernel")" "$common/drivers/kernelsu"

  grep -qF 'obj-$(CONFIG_KSU) += kernelsu/' "$makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$makefile"
  grep -qF 'source "drivers/kernelsu/Kconfig"' "$kconfig" || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$kconfig"

  grep -q 'config KSU_SUSFS' "$dst/kernel/Kconfig" || die "pinned ReSukiSU lacks CONFIG_KSU_SUSFS"
  grep -Rqs 'susfs_is_current_proc_no_su' "$dst/kernel" || die "pinned ReSukiSU lacks SUSFS 2.3 compatibility marker: proc_no_su"
  grep -Rqs 'is_zygote_next' "$dst/kernel" || die "pinned ReSukiSU lacks zygote_next compatibility"
  log "ReSukiSU source integration prepared"
}

install_susfs() {
  local common="$KERNEL_PLATFORM/common"
  local susfs="$DEPS_DIR/susfs"
  local patch="$susfs/$SUSFS_KERNEL_PATCH"

  [[ -f "$patch" ]] || die "SUSFS kernel patch missing: $patch"
  [[ -d "$susfs/$SUSFS_FS_DIR" ]] || die "SUSFS fs source missing"
  [[ -d "$susfs/$SUSFS_INCLUDE_DIR" ]] || die "SUSFS include source missing"

  # Kernel-side SUSFS implementation only. Do NOT apply KernelSU/10_enable_susfs_for_ksu.patch:
  # ReSukiSU owns its own KSU<->SUSFS hook/adaptation layer.
  cp -a "$susfs/$SUSFS_FS_DIR/." "$common/fs/"
  cp -a "$susfs/$SUSFS_INCLUDE_DIR/." "$common/include/linux/"

  git -C "$common" apply --check "$patch" || die "SUSFS 2.3 common patch conflicts with this OnePlus base; manual adaptation required"
  git -C "$common" apply "$patch"

  grep -q '#define SUSFS_VERSION "v2.3.0"' "$common/include/linux/susfs.h" || die "SUSFS version is not v2.3.0"
  [[ -f "$common/fs/susfs.c" ]] || die "fs/susfs.c missing after integration"
  log "SUSFS 2.3 kernel-side integration prepared"
}

integrate_root() {
  require_platform
  require_clean_common
  fetch_deps
  install_resukisu
  install_susfs

  log "root stack prepared; no KPatch-Next code was inserted into common"
  log "review common diff before committing: git -C '$KERNEL_PLATFORM/common' status --short"
}

verify_source() {
  require_platform
  local common="$KERNEL_PLATFORM/common"
  local resukisu="$KERNEL_PLATFORM/KernelSU"

  [[ -L "$common/drivers/kernelsu" ]] || die "drivers/kernelsu is not the expected ReSukiSU symlink"
  [[ -d "$resukisu/.git" ]] || die "KernelSU/ReSukiSU checkout missing"
  [[ "$(git -C "$resukisu" rev-parse HEAD)" == "$RESUKISU_COMMIT" ]] || die "ReSukiSU SHA drift"
  [[ -f "$common/fs/susfs.c" ]] || die "SUSFS source missing"
  grep -q '#define SUSFS_VERSION "v2.3.0"' "$common/include/linux/susfs.h" || die "SUSFS version verification failed"
  grep -qF 'obj-$(CONFIG_KSU) += kernelsu/' "$common/drivers/Makefile" || die "ReSukiSU Makefile entry missing"
  grep -qF 'source "drivers/kernelsu/Kconfig"' "$common/drivers/Kconfig" || die "ReSukiSU Kconfig entry missing"

  if git -C "$common" apply --reverse --check "$DEPS_DIR/susfs/$SUSFS_KERNEL_PATCH" >/dev/null 2>&1; then
    log "SUSFS common patch: applied"
  else
    die "cannot prove SUSFS common patch is applied cleanly"
  fi

  log "source verification passed"
}

build_kpatch_next() {
  fetch_deps
  local kp="$DEPS_DIR/kpatch-next"
  : "${ANDROID_NDK:?set ANDROID_NDK to an Android NDK directory}"
  : "${TARGET_COMPILE:=aarch64-none-elf-}"
  command -v "${TARGET_COMPILE}gcc" >/dev/null 2>&1 || die "missing bare-metal compiler: ${TARGET_COMPILE}gcc"
  command -v cmake >/dev/null 2>&1 || die "cmake not found"

  export TARGET_COMPILE
  (
    cd "$kp/kernel"
    make clean
    make
  )
  (
    cd "$kp/tools"
    rm -rf build/android
    cmake -S . -B build/android \
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
      -DCMAKE_BUILD_TYPE=Release \
      -DANDROID_PLATFORM=android-33 \
      -DANDROID_ABI=arm64-v8a
    cmake --build build/android
  )

  [[ -s "$kp/kernel/kpimg" ]] || die "kpimg build failed"
  [[ -s "$kp/tools/build/android/kptools" ]] || die "kptools build failed"
  log "KPatch-Next tools built from pinned commit $KPATCH_NEXT_COMMIT"
}

patch_image() {
  local input="${1:-}" output="${2:-}"
  [[ -n "$input" && -n "$output" ]] || die "patch-image requires input Image and output path"
  [[ -s "$input" ]] || die "input Image missing/empty: $input"

  fetch_deps
  local kp="$DEPS_DIR/kpatch-next"
  local kptools="${KPTOOLS:-$kp/tools/build/android/kptools}"
  local kpimg="${KPIMG:-$kp/kernel/kpimg}"
  [[ -x "$kptools" ]] || die "kptools not built; run build-kpatch-next or set KPTOOLS"
  [[ -s "$kpimg" ]] || die "kpimg not built; run build-kpatch-next or set KPIMG"

  "$kptools" -p -i "$input" -k "$kpimg" -o "$output"
  [[ -s "$output" ]] || die "KPatch-Next produced no output Image"
  "$kptools" -l -i "$output" > "${output}.kpatch-info.txt"
  sha256sum "$input" "$output" > "${output}.sha256"
  log "KPatch-Next Image ready: $output"
}

case "${1:-}" in
  fetch) fetch_deps ;;
  integrate-root) integrate_root ;;
  verify-source) fetch_deps; verify_source ;;
  build-kpatch-next) build_kpatch_next ;;
  patch-image) shift; patch_image "$@" ;;
  -h|--help|help|'') usage ;;
  *) die "unknown command: $1" ;;
esac
