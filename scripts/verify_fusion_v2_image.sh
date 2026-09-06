#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAGMENT="$ROOT_DIR/configs/fusion_v2_root.fragment"
RAW_IMAGE="${1:-}"
PATCHED_IMAGE="${2:-}"
KERNEL_PLATFORM="${KERNEL_PLATFORM:-}"
KPTOOLS="${KPTOOLS:-}"

log() { printf '[fusion-v2-verify] %s\n' "$*"; }
die() { printf '[fusion-v2-verify][ERROR] %s\n' "$*" >&2; exit 1; }

[[ -n "$RAW_IMAGE" && -n "$PATCHED_IMAGE" ]] || die "usage: $0 <raw-Image> <kpatch-Image>"
[[ -s "$RAW_IMAGE" ]] || die "raw Image missing/empty: $RAW_IMAGE"
[[ -s "$PATCHED_IMAGE" ]] || die "patched Image missing/empty: $PATCHED_IMAGE"
[[ -f "$FRAGMENT" ]] || die "config fragment missing: $FRAGMENT"

for tool in stat sha256sum strings grep cmp; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool missing: $tool"
done

raw_size="$(stat -c '%s' "$RAW_IMAGE")"
patched_size="$(stat -c '%s' "$PATCHED_IMAGE")"
(( raw_size > 20 * 1024 * 1024 )) || die "raw Image unexpectedly small: $raw_size bytes"
(( patched_size > raw_size )) || die "KPatch-Next Image should be larger than raw Image: raw=$raw_size patched=$patched_size"

if cmp -s "$RAW_IMAGE" "$PATCHED_IMAGE"; then
  die "patched Image is byte-identical to raw Image"
fi

raw_sha="$(sha256sum "$RAW_IMAGE" | awk '{print $1}')"
patched_sha="$(sha256sum "$PATCHED_IMAGE" | awk '{print $1}')"
[[ "$raw_sha" != "$patched_sha" ]] || die "raw and patched SHA256 unexpectedly match"

# These are stable binary-level markers from the intended stack, not uname/SUBLEVEL checks.
strings "$RAW_IMAGE" | grep -Fq 'susfs is initialized! version: v2.3.0' || \
  die "SUSFS v2.3.0 initialization marker not found in raw Image"

if ! strings "$RAW_IMAGE" | grep -Eiq 'ReSukiSU|resukisu\.org|MULTI.*MANAGER|dynamic_manager'; then
  die "no ReSukiSU/multi-manager binary marker found in raw Image"
fi

# Extract and validate IKCONFIG when the complete kernel source workspace is available.
config_tmp="$(mktemp)"
trap 'rm -f "$config_tmp"' EXIT
extractor=""
if [[ -n "$KERNEL_PLATFORM" && -x "$KERNEL_PLATFORM/common/scripts/extract-ikconfig" ]]; then
  extractor="$KERNEL_PLATFORM/common/scripts/extract-ikconfig"
elif [[ -n "$KERNEL_PLATFORM" && -f "$KERNEL_PLATFORM/common/scripts/extract-ikconfig" ]]; then
  extractor="$KERNEL_PLATFORM/common/scripts/extract-ikconfig"
fi

if [[ -n "$extractor" ]]; then
  bash "$extractor" "$RAW_IMAGE" > "$config_tmp"
  [[ -s "$config_tmp" ]] || die "IKCONFIG extraction returned empty output"

  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#\ Fusion* || "$line" == \#\ Required* ]] && continue
    grep -qxF "$line" "$config_tmp" || die "Image IKCONFIG mismatch: $line"
  done < "$FRAGMENT"
  log "IKCONFIG verified against fusion_v2_root.fragment"
else
  log "WARNING: KERNEL_PLATFORM/common/scripts/extract-ikconfig unavailable; IKCONFIG gate skipped"
fi

# KPatch-Next metadata must be parseable by the exact host kptools when supplied.
if [[ -n "$KPTOOLS" ]]; then
  [[ -x "$KPTOOLS" ]] || die "KPTOOLS is not executable: $KPTOOLS"
  "$KPTOOLS" --version >/dev/null || die "KPTOOLS cannot execute on this host"
  info="$($KPTOOLS -l -i "$PATCHED_IMAGE")" || die "KPatch-Next metadata parse failed"
  [[ -n "$info" ]] || die "KPatch-Next metadata output is empty"
  printf '%s\n' "$info" | grep -Eiq 'kpimg|kpatch|kernel' || die "KPatch-Next metadata lacks expected sections"
  log "KPatch-Next metadata verified"
else
  log "WARNING: KPTOOLS not supplied; KPatch metadata parse gate skipped"
fi

cat <<EOF
Fusion V2 Image verification: PASS
raw_size=$raw_size
patched_size=$patched_size
raw_sha256=$raw_sha
patched_sha256=$patched_sha
EOF
