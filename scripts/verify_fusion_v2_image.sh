#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAGMENTS=(
  "$ROOT_DIR/configs/fusion_v2_root.fragment"
  "$ROOT_DIR/configs/fusion_v2_standard.fragment"
)
RAW_IMAGE="${1:-}"
PATCHED_IMAGE="${2:-}"
KERNEL_PLATFORM="${KERNEL_PLATFORM:-}"
KPTOOLS="${KPTOOLS:-}"

log() { printf '[fusion-v2-verify] %s\n' "$*"; }
die() { printf '[fusion-v2-verify][ERROR] %s\n' "$*" >&2; exit 1; }

[[ -n "$RAW_IMAGE" && -n "$PATCHED_IMAGE" ]] || die "usage: $0 <raw-Image> <kpatch-Image>"
[[ -s "$RAW_IMAGE" ]] || die "raw Image missing/empty: $RAW_IMAGE"
[[ -s "$PATCHED_IMAGE" ]] || die "patched Image missing/empty: $PATCHED_IMAGE"
for fragment in "${FRAGMENTS[@]}"; do [[ -f "$fragment" ]] || die "config fragment missing: $fragment"; done

for tool in stat sha256sum strings grep cmp file; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool missing: $tool"
done

file_desc="$(file "$RAW_IMAGE")"
printf '%s\n' "$file_desc" | grep -Eiq 'ARM64|aarch64|Linux kernel.*ARM64' || die "raw Image is not recognized as ARM64 kernel: $file_desc"

raw_size="$(stat -c '%s' "$RAW_IMAGE")"
patched_size="$(stat -c '%s' "$PATCHED_IMAGE")"
(( raw_size > 20 * 1024 * 1024 )) || die "raw Image unexpectedly small: $raw_size bytes"
(( patched_size > raw_size )) || die "KPatch-Next Image should be larger than raw Image: raw=$raw_size patched=$patched_size"

cmp -s "$RAW_IMAGE" "$PATCHED_IMAGE" && die "patched Image is byte-identical to raw Image"
raw_sha="$(sha256sum "$RAW_IMAGE" | awk '{print $1}')"
patched_sha="$(sha256sum "$PATCHED_IMAGE" | awk '{print $1}')"
[[ "$raw_sha" != "$patched_sha" ]] || die "raw and patched SHA256 unexpectedly match"

# Stable implementation markers; do not rely on SUBLEVEL/uname as a quality signal.
strings "$RAW_IMAGE" | grep -Fq 'susfs is initialized! version: v2.3.0' || die "SUSFS v2.3.0 marker not found"
strings "$RAW_IMAGE" | grep -Eiq 'ReSukiSU|resukisu\.org|dynamic_manager|MULTI.*MANAGER' || die "ReSukiSU/multi-manager marker not found"
strings "$RAW_IMAGE" | grep -Fq 'adios_dispatch_request' || die "ADIOS implementation marker not found"
strings "$RAW_IMAGE" | grep -Eiq '/dev/ntsync|drivers/misc/ntsync\.c|ntsync_create' || die "NTSYNC implementation marker not found"
strings "$RAW_IMAGE" | grep -Eiq 'hmbird|HMBIRD_TASK_PROP' || die "HMBIRD marker not found"
strings "$RAW_IMAGE" | grep -Fq 'slim_walt' || die "slim_walt marker not found"

# IKCONFIG is mandatory for this static gate.
[[ -n "$KERNEL_PLATFORM" ]] || die "KERNEL_PLATFORM is required for strict IKCONFIG verification"
extractor="$KERNEL_PLATFORM/common/scripts/extract-ikconfig"
[[ -f "$extractor" ]] || die "extract-ikconfig unavailable: $extractor"
config_tmp="$(mktemp)"
trap 'rm -f "$config_tmp"' EXIT
bash "$extractor" "$RAW_IMAGE" > "$config_tmp"
[[ -s "$config_tmp" ]] || die "IKCONFIG extraction returned empty output"

verify_fragment() {
  local fragment="$1"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^#[[:space:]][^C] ]] && continue
    grep -qxF "$line" "$config_tmp" || die "Image IKCONFIG mismatch from $(basename "$fragment"): $line"
  done < "$fragment"
}
for fragment in "${FRAGMENTS[@]}"; do verify_fragment "$fragment"; done
log "IKCONFIG verified against Root + Standard fragments"

# Standard must expose ADIOS but must not force it as the default scheduler.
grep -qx 'CONFIG_MQ_IOSCHED_ADIOS=y' "$config_tmp" || die "ADIOS is not built-in in Standard"
grep -qx '# CONFIG_MQ_IOSCHED_DEFAULT_ADIOS is not set' "$config_tmp" || die "ADIOS was unexpectedly forced as the default scheduler"
grep -qx 'CONFIG_NTSYNC=y' "$config_tmp" || die "NTSYNC is not built-in in Standard"

# Optional experimental layers must be absent both built-in and as modules.
grep -Eq '^CONFIG_BBG=[ym]$' "$config_tmp" && die "Baseband Guard unexpectedly enabled in Standard"
grep -Eq '^CONFIG_DRM_LINDROID_EVDI=[ym]$' "$config_tmp" && die "Lindroid EVDI unexpectedly enabled in Standard"

# KPatch-Next metadata must be parseable by the exact host tool.
[[ -n "$KPTOOLS" ]] || die "KPTOOLS is required for strict KPatch-Next verification"
[[ -x "$KPTOOLS" ]] || die "KPTOOLS is not executable: $KPTOOLS"
"$KPTOOLS" --version >/dev/null || die "KPTOOLS cannot execute on this host"
info="$($KPTOOLS -l -i "$PATCHED_IMAGE")" || die "KPatch-Next metadata parse failed"
[[ -n "$info" ]] || die "KPatch-Next metadata output is empty"
printf '%s\n' "$info" | grep -Eiq 'kpimg|kpatch|kernel' || die "KPatch-Next metadata lacks expected sections"
log "KPatch-Next metadata verified"

cat <<EOF
Fusion V2 strict static Image verification: PASS
file=$file_desc
raw_size=$raw_size
patched_size=$patched_size
raw_sha256=$raw_sha
patched_sha256=$patched_sha
EOF
