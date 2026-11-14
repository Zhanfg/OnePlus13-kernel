#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$ROOT_DIR/configs/fusion_v2_release.policy"

fail() { echo "[fusion-v2-release][ERROR] $*" >&2; exit 1; }
pass() { echo "[fusion-v2-release] $*"; }

[[ -f "$POLICY" ]] || fail "missing release policy"
# shellcheck disable=SC1090
source "$POLICY"

IMAGE="${1:-}"
[[ -n "$IMAGE" && -s "$IMAGE" ]] || fail "usage: $0 /path/to/final/Image"

[[ "$ROOT_CORE" == "ReSukiSU" ]] || fail "unexpected root core: $ROOT_CORE"
[[ "$KPATCH_NEXT_REQUIRED" == "1" ]] || fail "KPatch-Next must be required for Fusion V2 release"
[[ "$KPM_INTERACTIVE_TOGGLE" == "0" ]] || fail "interactive KPM toggle must stay disabled"
[[ "$KPATCH_NEXT_STAGE" == "post-build-image" ]] || fail "unexpected KPatch-Next stage"

INFO="${IMAGE}.kpatch-info.txt"
HASHES="${IMAGE}.sha256"
[[ -s "$INFO" ]] || fail "missing KPatch-Next info: $INFO"
[[ -s "$HASHES" ]] || fail "missing pre/post patch hashes: $HASHES"

grep -Eqi 'KernelPatch|KPatch|kpimg|KPM' "$INFO" || fail "KPatch-Next metadata marker not found"

mapfile -t hash_lines < <(grep -E '^[0-9a-fA-F]{64}[[:space:]]' "$HASHES")
[[ ${#hash_lines[@]} -ge 2 ]] || fail "expected at least two SHA256 records (pre/post patch)"

final_sha="$(sha256sum "$IMAGE" | awk '{print $1}')"
grep -Eqi "^${final_sha}[[:space:]]+.*$(basename "$IMAGE")$" "$HASHES" || \
  grep -Eqi "^${final_sha}[[:space:]]" "$HASHES" || \
  fail "final Image hash is not recorded in provenance"

pass "release Image passed KPatch-Next/KPM policy checks"
pass "root core: ReSukiSU"
pass "SUSFS target: $SUSFS_TARGET"
pass "final Image sha256: $final_sha"
