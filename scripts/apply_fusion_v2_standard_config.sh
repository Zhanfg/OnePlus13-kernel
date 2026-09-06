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

# Resolve the edited gki_defconfig in an isolated output directory. Running
# `make olddefconfig` in the source root would validate common/.config instead of
# the gki_defconfig we just edited and could therefore report a false PASS.
resolve_dir="$(mktemp -d)"
cleanup() { rm -rf "$resolve_dir"; }
trap cleanup EXIT

make -s -C "$COMMON" O="$resolve_dir" ARCH=arm64 gki_defconfig >/dev/null
make -s -C "$COMMON" O="$resolve_dir" ARCH=arm64 olddefconfig >/dev/null
resolved_config="$resolve_dir/.config"
[[ -s "$resolved_config" ]] || fail "Kconfig resolution produced no .config"

verify_line() {
  local line="$1"
  if [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=([ym])$ ]]; then
    grep -qxF "$line" "$resolved_config" || fail "resolved config mismatch: $line"
  elif [[ "$line" =~ ^#\ CONFIG_([A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
    grep -qxF "$line" "$resolved_config" || fail "resolved config did not keep disabled symbol: ${BASH_REMATCH[1]}"
  else
    fail "unsupported fragment line during verification: $line"
  fi
}

for fragment in "${FRAGMENTS[@]}"; do
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]][^C] ]] && continue
    verify_line "$line"
  done < "$fragment"
done

log "Fusion V2 config fragments passed real Kconfig dependency resolution"
log "NTSYNC + ADIOS enabled; ADIOS default disabled; BBG/EVDI remain deferred in Standard"
