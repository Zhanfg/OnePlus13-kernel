#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_LOCK="$ROOT_DIR/configs/oneplus_13_16.0.9.401.lock"
FUSION_LOCK="$ROOT_DIR/configs/fusion_v2_sources.lock"
OKI="${OKI_WORKSPACE:-$HOME/op13-oki-fusion-v2}"
ACTION="${1:-all}"

[[ -f "$BASE_LOCK" ]] || { echo "[ERROR] missing $BASE_LOCK" >&2; exit 1; }
[[ -f "$FUSION_LOCK" ]] || { echo "[ERROR] missing $FUSION_LOCK" >&2; exit 1; }
# shellcheck disable=SC1090
source "$BASE_LOCK"
# shellcheck disable=SC1090
source "$FUSION_LOCK"

log() { printf '[fusion-v2-oki] %s\n' "$*"; }
die() { printf '[fusion-v2-oki][ERROR] %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

usage() {
  cat <<EOF
Usage: OKI_WORKSPACE=/path/to/op13-oki bash scripts/build_fusion_v2_oki.sh <action>
Actions:
  sync      Sync exact OnePlus complete OKI manifest, verify official platform, then pin Fusion common
  prepare   Integrate ReSukiSU + SUSFS 2.3 and apply Fusion V2 Standard config
  build     Clean-build OnePlus sun perf and verify Image/config
  kpatch    Build KPatch-Next and patch Image, then run static gates
  all       sync -> prepare -> build -> kpatch

Output:
  raw Image:      $OKI/out/dist/Image
  KPatch Image:   $OKI/out/dist/Image.kpatch-next
EOF
}

verify_official_platform() {
  [[ -d "$OKI/kernel_platform/common/.git" ]] || die "official common repository missing"
  [[ -d "$OKI/kernel_platform/msm-kernel/.git" ]] || die "msm-kernel repository missing"
  local common_sha msm_sha
  common_sha="$(git -C "$OKI/kernel_platform/common" rev-parse HEAD)"
  msm_sha="$(git -C "$OKI/kernel_platform/msm-kernel" rev-parse HEAD)"
  [[ "$common_sha" == "$ONEPLUS_COMMON_SHA" ]] || die "official common SHA mismatch: $common_sha"
  [[ "$msm_sha" == "$ONEPLUS_MSM_SHA" ]] || die "msm-kernel SHA mismatch: $msm_sha"
  log "official OnePlus platform verified: common=$common_sha msm=$msm_sha"
}

switch_fusion_common() {
  local common="$OKI/kernel_platform/common"
  git -C "$common" remote remove fusion >/dev/null 2>&1 || true
  git -C "$common" remote add fusion "$FUSION_COMMON_REPO"
  git -C "$common" fetch --force --depth=1 fusion "$FUSION_COMMON_COMMIT"
  git -C "$common" checkout --detach FETCH_HEAD
  [[ "$(git -C "$common" rev-parse HEAD)" == "$FUSION_COMMON_COMMIT" ]] || die "Fusion common checkout mismatch"
  git -C "$common" diff --quiet || die "Fusion common dirty immediately after checkout"
  log "Fusion common pinned: $FUSION_COMMON_COMMIT"
}

verify_build_platform() {
  local common_sha msm_sha
  common_sha="$(git -C "$OKI/kernel_platform/common" rev-parse HEAD)"
  msm_sha="$(git -C "$OKI/kernel_platform/msm-kernel" rev-parse HEAD)"
  [[ "$common_sha" == "$FUSION_COMMON_COMMIT" ]] || die "Fusion common drift: $common_sha"
  [[ "$msm_sha" == "$ONEPLUS_MSM_SHA" ]] || die "msm-kernel drift: $msm_sha"
  log "build platform verified: fusion-common=$common_sha msm=$msm_sha"
}

sync_oki() {
  need repo
  need git
  mkdir -p "$OKI"
  cd "$OKI"

  repo init -u "$MANIFEST_REPO" -b "$MANIFEST_BRANCH" -m "$MANIFEST_FILE"
  repo sync -c --force-sync --no-clone-bundle --no-tags -j"${SYNC_JOBS:-$(nproc)}"
  repo manifest -r -o manifest-pinned.xml
  sha256sum manifest-pinned.xml > manifest-pinned.xml.sha256

  verify_official_platform
  switch_fusion_common
  verify_build_platform
  log "complete OKI sync + Fusion common switch verified"
}

ensure_abogki_tags() {
  for repo_path in "$OKI/kernel_platform/common" "$OKI/kernel_platform/msm-kernel"; do
    if ! git -C "$repo_path" tag --points-at HEAD | grep -q '^abogki'; then
      git -C "$repo_path" tag -f abogki500782043 HEAD
    fi
  done
}

prepare_tree() {
  verify_build_platform
  export KERNEL_PLATFORM="$OKI/kernel_platform"
  bash "$ROOT_DIR/scripts/fusion_v2.sh" integrate-root
  bash "$ROOT_DIR/scripts/apply_fusion_v2_standard_config.sh" "$OKI/kernel_platform/common"
  bash "$ROOT_DIR/scripts/fusion_v2.sh" verify-source
  ensure_abogki_tags

  log "prepared source diff:"
  git -C "$OKI/kernel_platform/common" status --short
}

verify_fragment() {
  local image_config="$1" fragment="$2"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]][^C] ]] && continue
    grep -qxF "$line" "$image_config" || die "resolved config mismatch from $(basename "$fragment"): $line"
  done < "$fragment"
}

verify_requested_config() {
  local image_config="${1:-}"
  [[ -f "$image_config" ]] || die "resolved .config not found: $image_config"
  verify_fragment "$image_config" "$ROOT_DIR/configs/fusion_v2_root.fragment"
  verify_fragment "$image_config" "$ROOT_DIR/configs/fusion_v2_standard.fragment"
}

locate_image() {
  local candidate
  for candidate in \
    "$OKI/out/dist/Image" \
    "$OKI/kernel_platform/out/msm-kernel-sun-perf/dist/Image" \
    "$OKI/kernel_platform/out/msm-kernel-sun-perf/Image"; do
    if [[ -s "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

build_oki() {
  need strings
  [[ -x "$OKI/kernel_platform/oplus/build/oplus_build_kernel.sh" ]] || die "OnePlus build script missing"
  verify_build_platform
  ensure_abogki_tags

  rm -rf "$OKI/out/dist"
  rm -rf "$OKI/kernel_platform/out/msm-kernel-sun-perf"
  mkdir -p "$OKI/out/dist"

  local stamp log_file
  stamp="$(date +%Y%m%d_%H%M%S)"
  log_file="$OKI/build_fusion_v2_${stamp}.log"
  cd "$OKI"

  set +e
  ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf 2>&1 | tee "$log_file"
  local rc=${PIPESTATUS[0]}
  set -e
  [[ $rc -eq 0 ]] || die "sun perf build failed (rc=$rc); log=$log_file"

  local built_image
  built_image="$(locate_image)" || die "build returned success but no Image was found"
  if [[ "$built_image" != "$OKI/out/dist/Image" ]]; then
    cp "$built_image" "$OKI/out/dist/Image"
  fi

  local image_size
  image_size="$(stat -c '%s' "$OKI/out/dist/Image")"
  (( image_size > 20 * 1024 * 1024 )) || die "Image is unexpectedly small: $image_size bytes"

  local resolved=""
  for candidate in \
    "$OKI/kernel_platform/out/msm-kernel-sun-perf/common/.config" \
    "$OKI/kernel_platform/out/msm-kernel-sun-perf/gki_kernel/common/.config" \
    "$OKI/kernel_platform/common/.config"; do
    if [[ -f "$candidate" ]]; then resolved="$candidate"; break; fi
  done
  if [[ -n "$resolved" ]]; then
    verify_requested_config "$resolved"
    cp "$resolved" "$OKI/out/dist/fusion-v2-resolved.config"
  else
    log "WARNING: resolved .config path not found; Image IKCONFIG gate remains mandatory"
  fi

  strings "$OKI/out/dist/Image" | grep -m1 'Linux version' > "$OKI/out/dist/Image.version.txt" || true
  sha256sum "$OKI/out/dist/Image" > "$OKI/out/dist/Image.sha256"
  git -C "$OKI/kernel_platform/common" rev-parse HEAD > "$OKI/out/dist/fusion-common.commit"
  git -C "$OKI/kernel_platform/msm-kernel" rev-parse HEAD > "$OKI/out/dist/msm-kernel.commit"
  cp "$OKI/manifest-pinned.xml" "$OKI/out/dist/manifest-pinned.xml"
  cp "$OKI/manifest-pinned.xml.sha256" "$OKI/out/dist/manifest-pinned.xml.sha256"
  cp "$log_file" "$OKI/out/dist/build.log"
  log "raw Image built: $OKI/out/dist/Image ($image_size bytes)"
}

kpatch_image() {
  [[ -s "$OKI/out/dist/Image" ]] || die "raw Image missing; run build first"
  export TARGET_COMPILE="${TARGET_COMPILE:-aarch64-linux-gnu-}"
  bash "$ROOT_DIR/scripts/fusion_v2.sh" build-kpatch-next
  bash "$ROOT_DIR/scripts/fusion_v2.sh" patch-image \
    "$OKI/out/dist/Image" \
    "$OKI/out/dist/Image.kpatch-next"

  export KERNEL_PLATFORM="$OKI/kernel_platform"
  export KPTOOLS="$ROOT_DIR/.work/fusion-v2/deps/kpatch-next/tools/build/host/kptools"
  bash "$ROOT_DIR/scripts/verify_fusion_v2_image.sh" \
    "$OKI/out/dist/Image" "$OKI/out/dist/Image.kpatch-next" | tee "$OKI/out/dist/static-gate.txt"
  bash "$ROOT_DIR/scripts/verify_fusion_v2_release.sh" "$OKI/out/dist/Image.kpatch-next" | tee -a "$OKI/out/dist/static-gate.txt"
  log "KPatch-Next Image + static gates passed"
}

case "$ACTION" in
  sync) sync_oki ;;
  prepare) prepare_tree ;;
  build) build_oki ;;
  kpatch) kpatch_image ;;
  all) sync_oki; prepare_tree; build_oki; kpatch_image ;;
  help|-h|--help) usage ;;
  *) usage; die "unknown action: $ACTION" ;;
esac
