#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/configs/fusion_v2_sources.lock"
source "$ROOT_DIR/configs/oneplus_13_16.0.10.501.lock"

FAST_ROOT="${FAST_WORKSPACE:-$ROOT_DIR/.fast-oki}"
KP="$FAST_ROOT/kernel_platform"
COMMON="$KP/common"
OUT="${FAST_OUT:-$FAST_ROOT/out}"
DIST="${FAST_DIST:-$FAST_ROOT/dist}"
CCACHE_DIR="${CCACHE_DIR:-$ROOT_DIR/.fusion-cache/ccache}"

log() { printf '[fusion-fast] %s\n' "$*"; }
die() { printf '[fusion-fast][ERROR] %s\n' "$*" >&2; exit 1; }

timer_begin() {
  TIMER_NAME="$1"
  TIMER_START="$(date +%s)"
  log "phase-start $TIMER_NAME $(date -u +%FT%TZ)"
}
timer_end() {
  local now elapsed
  now="$(date +%s)"
  elapsed=$((now - TIMER_START))
  log "phase-end $TIMER_NAME seconds=$elapsed"
  printf '%s=%s\n' "$TIMER_NAME" "$elapsed" >> "$FAST_ROOT/timings.env"
}

clone_common() {
  timer_begin source
  mkdir -p "$KP"
  if [[ ! -d "$COMMON/.git" ]]; then
    rm -rf "$COMMON"
    git clone --filter=blob:none --no-tags --depth=1 "$FUSION_COMMON_REPO" "$COMMON"
  fi
  git -C "$COMMON" fetch --force --no-tags --depth=1 origin "$FUSION_COMMON_COMMIT"
  git -C "$COMMON" checkout --detach "$FUSION_COMMON_COMMIT"
  git -C "$COMMON" reset --hard "$FUSION_COMMON_COMMIT"
  git -C "$COMMON" clean -ffdqx
  [[ "$(git -C "$COMMON" rev-parse HEAD)" == "$FUSION_COMMON_COMMIT" ]] || die "Fusion common SHA mismatch"
  timer_end source
}

integrate() {
  timer_begin integrate
  export KERNEL_PLATFORM="$KP"
  export FUSION_WORK_DIR="${FUSION_WORK_DIR:-$ROOT_DIR/.work/fusion-v2}"
  bash "$ROOT_DIR/scripts/fusion_v2.sh" integrate-root-fast
  bash "$ROOT_DIR/scripts/fusion_v2.sh" verify-source-fast
  timer_end integrate
}

configure() {
  timer_begin configure
  rm -rf "$OUT"
  mkdir -p "$OUT" "$DIST" "$CCACHE_DIR"
  make -C "$COMMON" O="$OUT" ARCH=arm64 gki_defconfig
  bash "$COMMON/scripts/kconfig/merge_config.sh" -m -O "$OUT"     "$OUT/.config"     "$ROOT_DIR/configs/fusion_v2_root.fragment"     "$ROOT_DIR/configs/fusion_v2_standard.fragment"
  make -C "$COMMON" O="$OUT" ARCH=arm64 olddefconfig

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]][^C] ]] && continue
    grep -qxF "$line" "$OUT/.config" || die "resolved fast config mismatch: $line"
  done < "$ROOT_DIR/configs/fusion_v2_root.fragment"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]][^C] ]] && continue
    grep -qxF "$line" "$OUT/.config" || die "resolved fast config mismatch: $line"
  done < "$ROOT_DIR/configs/fusion_v2_standard.fragment"

  grep -qx 'CONFIG_MODVERSIONS=y' "$OUT/.config" || die "CONFIG_MODVERSIONS lost in fast config"
  cp "$OUT/.config" "$DIST/fast-resolved.config"
  timer_end configure
}

build_image() {
  timer_begin compile
  export CCACHE_DIR
  export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2500M}"
  export CCACHE_COMPRESS=1
  export CCACHE_COMPRESSLEVEL=3
  ccache -M "$CCACHE_MAXSIZE" >/dev/null
  ccache -z >/dev/null

  make -C "$COMMON"     O="$OUT"     ARCH=arm64     LLVM=1 LLVM_IAS=1     HOSTCC="ccache clang" HOSTCXX="ccache clang++"     CC="ccache clang"     -j"${FAST_JOBS:-$(nproc)}"     Image

  test -s "$OUT/arch/arm64/boot/Image" || die "Image missing"
  cp "$OUT/arch/arm64/boot/Image" "$DIST/Image"
  cp "$OUT/vmlinux" "$DIST/vmlinux" 2>/dev/null || true
  sha256sum "$DIST/Image" > "$DIST/Image.sha256"
  ccache -s | tee "$DIST/ccache-stats.txt"
  timer_end compile
}

verify_image() {
  timer_begin verify
  local size
  size="$(stat -c '%s' "$DIST/Image")"
  (( size > 20 * 1024 * 1024 )) || die "Image unexpectedly small: $size"
  strings "$DIST/Image" | grep -m1 'Linux version' > "$DIST/Image.version.txt" || true
  strings "$DIST/Image" | grep -Eq 'KernelSU|ReSukiSU|KSU' || die "ReSukiSU marker missing from fast Image"
  strings "$DIST/Image" | grep -Eq 'susfs|SUSFS' || die "SUSFS marker missing from fast Image"
  {
    echo "mode=fast-common-image-only"
    echo "device=$DEVICE_MODEL"
    echo "rom=$ROM_BASE"
    echo "fusion_common=$FUSION_COMMON_COMMIT"
    echo "release_equivalent=false"
    echo "kmi_release_gate=deferred-to-full-oki"
  } > "$DIST/FAST_PROVENANCE.txt"
  timer_end verify
}

main() {
  rm -f "$FAST_ROOT/timings.env"
  mkdir -p "$FAST_ROOT"
  clone_common
  integrate
  configure
  build_image
  verify_image
  cat "$FAST_ROOT/timings.env"
}

main "$@"
