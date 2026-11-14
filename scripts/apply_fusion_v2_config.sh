#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${1:-${KERNEL_PLATFORM:-}/common}"
shift $(( $# > 0 ? 1 : 0 ))

fail() { echo "[fusion-v2-config][ERROR] $*" >&2; exit 1; }
log() { echo "[fusion-v2-config] $*"; }

[[ -d "$COMMON" ]] || fail "common tree not found; pass /path/to/kernel_platform/common"
[[ -f "$COMMON/scripts/config" ]] || fail "scripts/config missing in common tree"
[[ -f "$COMMON/arch/arm64/configs/gki_defconfig" ]] || fail "gki_defconfig missing"
[[ -e "$COMMON/drivers/kernelsu/Kconfig" ]] || fail "ReSukiSU is not integrated yet"
[[ -f "$COMMON/fs/susfs.c" ]] || fail "SUSFS kernel source is not integrated yet"

if [[ $# -gt 0 ]]; then
  fragments=("$@")
else
  fragments=("$ROOT_DIR/configs/fusion_v2_root.fragment")
fi

defconfig="$COMMON/arch/arm64/configs/gki_defconfig"
config_tool="$COMMON/scripts/config"

apply_fragment() {
  local fragment="$1"
  [[ -f "$fragment" ]] || fail "fragment missing: $fragment"
  log "applying fragment: $fragment"

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]]*Fusion || "$line" =~ ^#[[:space:]]*Network || "$line" =~ ^#[[:space:]]*Linux || "$line" =~ ^#[[:space:]]*Retain || "$line" =~ ^#[[:space:]]*Required ]] && continue

    if [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=y$ ]]; then
      "$config_tool" --file "$defconfig" -e "${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=m$ ]]; then
      "$config_tool" --file "$defconfig" -m "${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^#\ CONFIG_([A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
      "$config_tool" --file "$defconfig" -d "${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^#[[:space:]] ]]; then
      continue
    else
      fail "unsupported fragment line in $fragment: $line"
    fi
  done < "$fragment"
}

verify_fragment() {
  local fragment="$1"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]]*Fusion || "$line" =~ ^#[[:space:]]*Network || "$line" =~ ^#[[:space:]]*Linux || "$line" =~ ^#[[:space:]]*Retain || "$line" =~ ^#[[:space:]]*Required ]] && continue

    if [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=([ym])$ ]]; then
      grep -qxF "$line" "$defconfig" || fail "defconfig did not retain: $line"
    elif [[ "$line" =~ ^#\ CONFIG_([A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
      grep -qxF "$line" "$defconfig" || fail "defconfig did not retain disabled symbol: ${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^#[[:space:]] ]]; then
      continue
    fi
  done < "$fragment"
}

for fragment in "${fragments[@]}"; do
  apply_fragment "$fragment"
done
for fragment in "${fragments[@]}"; do
  verify_fragment "$fragment"
done

log "Fusion V2 config fragments applied to $defconfig"
log "Kconfig dependency resolution must still be checked by the full OnePlus sun perf build."
