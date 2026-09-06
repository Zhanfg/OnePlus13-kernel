#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${KERNEL_PLATFORM:?set KERNEL_PLATFORM; common must exist below it}"
COMMON="$KERNEL_PLATFORM/common"

[[ -d "$COMMON/.git" ]] || { echo "[preflight][ERROR] missing common git tree" >&2; exit 1; }

# Source the production integration implementation itself. `help` makes its
# dispatcher side-effect-free while leaving all functions available here.
set -- help
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/fusion_v2.sh" >/dev/null
set --

actual="$(git -C "$COMMON" rev-parse HEAD)"
[[ "$actual" == "$FUSION_COMMON_COMMIT" ]] || {
  echo "[preflight][ERROR] wrong Fusion common: $actual" >&2
  exit 1
}

# Prove the minimal Fusion common still descends from the exact OnePlus ROM base.
git -C "$COMMON" cat-file -e "$ONEPLUS_COMMON_SHA^{commit}" || {
  git -C "$COMMON" fetch --force --depth=16 "$FUSION_COMMON_REPO" "$ONEPLUS_COMMON_SHA"
}
git -C "$COMMON" merge-base --is-ancestor "$ONEPLUS_COMMON_SHA" "$FUSION_COMMON_COMMIT" || {
  echo "[preflight][ERROR] Fusion common is not descended from OnePlus official common" >&2
  exit 1
}
ahead="$(git -C "$COMMON" rev-list --count "$ONEPLUS_COMMON_SHA..$FUSION_COMMON_COMMIT")"
[[ "$ahead" -ge 1 && "$ahead" -le 16 ]] || {
  echo "[preflight][ERROR] unexpected Fusion common delta: $ahead commits" >&2
  exit 1
}

require_clean_common
fetch_deps
install_ntsync
install_resukisu
install_susfs
bash "$ROOT_DIR/scripts/apply_fusion_v2_standard_config.sh" "$COMMON"

# Source-level verification without requiring the rest of the complete OKI tree.
[[ "$(git -C "$COMMON" hash-object "$COMMON/$NTSYNC_DRIVER_PATH")" == "$NTSYNC_DRIVER_BLOB" ]]
[[ "$(git -C "$COMMON" hash-object "$COMMON/$NTSYNC_UAPI_PATH")" == "$NTSYNC_UAPI_BLOB" ]]
grep -q '^config NTSYNC$' "$COMMON/drivers/misc/Kconfig"
grep -qF 'obj-$(CONFIG_NTSYNC)' "$COMMON/drivers/misc/Makefile"

grep -q '#define ADIOS_VERSION "3.2.0"' "$COMMON/block/adios.c"
[[ -L "$COMMON/drivers/kernelsu" ]]
[[ "$(git -C "$KERNEL_PLATFORM/KernelSU" rev-parse HEAD)" == "$RESUKISU_COMMIT" ]]
grep -q '#define SUSFS_VERSION "v2.3.0"' "$COMMON/include/linux/susfs.h"
git -C "$COMMON" apply --reverse --check "$DEPS_DIR/susfs/$SUSFS_KERNEL_PATCH"

echo "Fusion V2 common source preflight: PASS"
echo "official_common=$ONEPLUS_COMMON_SHA"
echo "fusion_common=$FUSION_COMMON_COMMIT"
echo "fusion_ahead=$ahead"
echo "ntsync_driver_blob=$NTSYNC_DRIVER_BLOB"
echo "ntsync_uapi_blob=$NTSYNC_UAPI_BLOB"
echo "resukisu=$RESUKISU_COMMIT"
echo "susfs=$SUSFS_COMMIT"
