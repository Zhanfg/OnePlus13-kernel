#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${1:-${KERNEL_PLATFORM:-}/common}"
FRAGMENTS=(
  "$ROOT_DIR/configs/fusion_v2_root.fragment"
  "$ROOT_DIR/configs/fusion_v2_standard.fragment"
)

fail() { echo "[fusion-v2-config][ERROR] $*" >&2; exit 1; }
log() { echo "[fusion-v2-config] $*"; }

[[ -d "$COMMON" ]] || fail "common tree not found; pass /path/to/kernel_platform/common"
[[ -x "$COMMON/scripts/config" ]] || fail "scripts/config missing or not executable"
[[ -f "$COMMON/arch/arm64/configs/gki_defconfig" ]] || fail "gki_defconfig missing"
[[ -e "$COMMON/drivers/kernelsu/Kconfig" ]] || fail "ReSukiSU is not integrated"
[[ -f "$COMMON/fs/susfs.c" ]] || fail "SUSFS is not integrated"

defconfig="$COMMON/arch/arm64/configs/gki_defconfig"
config_tool="$COMMON/scripts/config"

apply_line() {
  local line="$1"
  if [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=y$ ]]; then
    "$config_tool" --file "$defconfig" -e "${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=m$ ]]; then
    "$config_tool" --file "$defconfig" -m "${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^#\ CONFIG_([A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
    "$config_tool" --file "$defconfig" -d "${BASH_REMATCH[1]}"
  else
    fail "unsupported fragment line: $line"
  fi
}

for fragment in "${FRAGMENTS[@]}"; do
  [[ -f "$fragment" ]] || fail "missing fragment: $fragment"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]][^C] ]] && continue
    apply_line "$line"
  done < "$fragment"
done

# Resolve dependencies using the real source tree, then verify final values.
make -C "$COMMON" ARCH=arm64 olddefconfig >/dev/null

for fragment in "${FRAGMENTS[@]}"; do
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]][^C] ]] && continue
    if [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=([ym])$ ]]; then
      grep -qx "$line" "$defconfig" || fail "final config mismatch: $line"
    elif [[ "$line" =~ ^#\ CONFIG_([A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
      grep -qx "$line" "$defconfig" || fail "final config did not keep disabled symbol: ${BASH_REMATCH[1]}"
    fi
  done < "$fragment"
done

log "Fusion V2 Standard config verified"
log "ADIOS is compiled but not forced as default; BBG/EVDI remain disabled in Standard"
