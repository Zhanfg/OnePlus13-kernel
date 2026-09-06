#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAGMENT="$ROOT_DIR/configs/fusion_v2_root.fragment"
COMMON="${1:-${KERNEL_PLATFORM:-}/common}"

fail() { echo "[fusion-v2-config][ERROR] $*" >&2; exit 1; }
log() { echo "[fusion-v2-config] $*"; }

[[ -d "$COMMON" ]] || fail "common tree not found; pass /path/to/kernel_platform/common"
[[ -f "$COMMON/scripts/config" ]] || fail "scripts/config missing in common tree"
[[ -f "$COMMON/arch/arm64/configs/gki_defconfig" ]] || fail "gki_defconfig missing"
[[ -f "$FRAGMENT" ]] || fail "fragment missing: $FRAGMENT"
[[ -e "$COMMON/drivers/kernelsu/Kconfig" ]] || fail "ReSukiSU is not integrated yet"
[[ -f "$COMMON/fs/susfs.c" ]] || fail "SUSFS kernel source is not integrated yet"

defconfig="$COMMON/arch/arm64/configs/gki_defconfig"
config_tool="$COMMON/scripts/config"

while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#\ Fusion* || "$line" == \#\ Required* ]] && continue
  if [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=y$ ]]; then
    "$config_tool" --file "$defconfig" -e "${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=m$ ]]; then
    "$config_tool" --file "$defconfig" -m "${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^#\ CONFIG_([A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
    "$config_tool" --file "$defconfig" -d "${BASH_REMATCH[1]}"
  else
    fail "unsupported fragment line: $line"
  fi
done < "$FRAGMENT"

# Verify the exact requested values are now represented in the source defconfig.
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#\ Fusion* || "$line" == \#\ Required* ]] && continue
  if [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=([ym])$ ]]; then
    grep -qx "$line" "$defconfig" || fail "defconfig did not retain: $line"
  elif [[ "$line" =~ ^#\ CONFIG_([A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
    grep -qx "$line" "$defconfig" || fail "defconfig did not retain disabled symbol: ${BASH_REMATCH[1]}"
  fi
done < "$FRAGMENT"

log "Fusion V2 root config applied to $defconfig"
log "Kconfig dependency resolution must still be checked by the full OnePlus sun perf build."
