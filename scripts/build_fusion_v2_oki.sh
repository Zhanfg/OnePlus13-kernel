#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_LOCK="$ROOT_DIR/configs/oneplus_13_16.0.9.401.lock"
OKI="${OKI_WORKSPACE:-$HOME/op13-oki-fusion-v2}"
ACTION="${1:-all}"

[[ -f "$BASE_LOCK" ]] || { echo "[ERROR] missing $BASE_LOCK" >&2; exit 1; }
# shellcheck disable=SC1090
source "$BASE_LOCK"

log() { printf '[fusion-v2-oki] %s\n' "$*"; }
die() { printf '[fusion-v2-oki][ERROR] %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

usage() {
  cat <<EOF
Usage: OKI_WORKSPACE=/path/to/op13-oki bash scripts/build_fusion_v2_oki.sh <action>
Actions:
  sync      Sync exact OnePlus complete OKI manifest and verify core SHAs
  prepare   Integrate ReSukiSU + SUSFS 2.3 and apply Fusion V2 root config
  build     Clean-build OnePlus sun perf and verify out/dist/Image
  kpatch    Build host KPatch-Next tools and patch out/dist/Image
  all       sync -> prepare -> build -> kpatch

Output:
  raw Image:      $OKI/out/dist/Image
  KPatch Image:   $OKI/out/dist/Image.kpatch-next
EOF
}

sync_oki() {
  need repo
  need git
  mkdir -p "$OKI"
  cd "$OKI"

  if [[ ! -d .repo ]]; then
    repo init -u "$MANIFEST_REPO" -b "$MANIFEST_BRANCH" -m "$MANIFEST_FILE"
  else
    repo init -u "$MANIFEST_REPO" -b "$MANIFEST_BRANCH" -m "$MANIFEST_FILE"
  fi

  repo sync -c --force-sync --no-clone-bundle --no-tags -j"${SYNC_JOBS:-$(nproc)}"
  repo manifest -r -o manifest-pinned.xml
  sha256sum manifest-pinned.xml > manifest-pinned.xml.sha256

  verify_base
  log "complete OKI sync verified"
}

verify_base() {
  [[ -d "$OKI/kernel_platform/common/.git" ]] || die "common repository missing"
  [[ -d "$OKI/kernel_platform/msm-kernel/.git" ]] || die "msm-kernel repository missing"

  local common_sha msm_sha modules_sha
  common_sha="$(git -C "$OKI/kernel_platform/common" rev-parse HEAD)"
  msm_sha="$(git -C "$OKI/kernel_platform/msm-kernel" rev-parse HEAD)"
  [[ "$common_sha" == "$ONEPLUS_COMMON_SHA" ]] || die "common SHA mismatch: $common_sha"
  [[ "$msm_sha" == "$ONEPLUS_MSM_SHA" ]] || die "msm-kernel SHA mismatch: $msm_sha"

  # oneplus_13_b.xml checks modules/devicetree out at the workspace root.
  if git -C "$OKI" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    modules_sha="$(git -C "$OKI" rev-parse HEAD)"
    [[ "$modules_sha" == "$ONEPLUS_MODULES_SHA" ]] || die "modules/devicetree SHA mismatch: $modules_sha"
  else
    log "workspace root is not exposed as a normal git worktree; modules SHA will be preserved in manifest-pinned.xml"
  fi

  log "OnePlus base: common=$common_sha msm=$msm_sha"
}

ensure_abogki_tags() {
  for repo_path in "$OKI/kernel_platform/common" "$OKI/kernel_platform/msm-kernel"; do
    if ! git -C "$repo_path" tag --points-at HEAD | grep -q '^abogki'; then
      git -C "$repo_path" tag -f abogki500782043 HEAD
    fi
  done
}

prepare_tree() {
  verify_base
  export KERNEL_PLATFORM="$OKI/kernel_platform"
  bash "$ROOT_DIR/scripts/fusion_v2.sh" integrate-root
  bash "$ROOT_DIR/scripts/apply_fusion_v2_config.sh" "$OKI/kernel_platform/common"
  bash "$ROOT_DIR/scripts/fusion_v2.sh" verify-source
  ensure_abogki_tags

  log "prepared source diff:"
  git -C "$OKI/kernel_platform/common" status --short
}

verify_requested_config() {
  local image_config="${1:-}"
  [[ -f "$image_config" ]] || die "resolved .config not found: $image_config"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#\ Fusion* || "$line" == \#\ Required* ]] && continue
    grep -qxF "$line" "$image_config" || die "resolved config mismatch: $line"
  done < "$ROOT_DIR/configs/fusion_v2_root.fragment"
}

build_oki() {
  need strings
  [[ -x "$OKI/kernel_platform/oplus/build/oplus_build_kernel.sh" ]] || die "OnePlus build script missing"
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

  [[ -s "$OKI/out/dist/Image" ]] || die "build returned success but out/dist/Image is missing"
  local image_size
  image_size="$(stat -c '%s' "$OKI/out/dist/Image")"
  (( image_size > 20 * 1024 * 1024 )) || die "Image is unexpectedly small: $image_size bytes"

  # Locate the final resolved common config if OnePlus emitted one.
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
    log "WARNING: resolved .config path not found; Image-level IKCONFIG verification is required before release"
  fi

  strings "$OKI/out/dist/Image" | grep -m1 'Linux version' > "$OKI/out/dist/Image.version.txt" || true
  sha256sum "$OKI/out/dist/Image" > "$OKI/out/dist/Image.sha256"
  log "raw Image built: $OKI/out/dist/Image ($image_size bytes)"
}

kpatch_image() {
  [[ -s "$OKI/out/dist/Image" ]] || die "raw Image missing; run build first"
  bash "$ROOT_DIR/scripts/fusion_v2.sh" build-kpatch-next
  bash "$ROOT_DIR/scripts/fusion_v2.sh" patch-image \
    "$OKI/out/dist/Image" \
    "$OKI/out/dist/Image.kpatch-next"
  log "KPatch-Next Image ready: $OKI/out/dist/Image.kpatch-next"
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
