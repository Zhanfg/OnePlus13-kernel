#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GITHUB_WORKSPACE="$tmp"
export GITHUB_OUTPUT="$tmp/budget.outputs"
mkdir -p "$tmp/.fusion-cache/bazel-disk" \
         "$tmp/oki/.repo/project-objects/kernel_platform/prebuilts/clang-tools.git" \
         "$tmp/oki/.repo/project-objects/android_kernel_common_oneplus_sm8750.git"
printf 'test\n' > "$tmp/.fusion-cache/bazel-disk/action.data"
printf 'object\n' > "$tmp/oki/.repo/project-objects/kernel_platform/prebuilts/clang-tools.git/HEAD"
printf 'object\n' > "$tmp/oki/.repo/project-objects/android_kernel_common_oneplus_sm8750.git/HEAD"
bash "$root/scripts/fusion_cache_budget.sh"
grep -qx 'clang_cache_ok=false' "$GITHUB_OUTPUT"
grep -qx 'tools_cache_ok=true' "$GITHUB_OUTPUT"
grep -qx 'oss_cache_ok=true' "$GITHUB_OUTPUT"
grep -qx 'bazel_cache_ok=true' "$GITHUB_OUTPUT"
bash "$root/scripts/fusion_cache_status.sh" > "$tmp/measure.txt"
grep -q '\[fusion-cache\]' "$tmp/measure.txt"
echo "PASS: selected object stores measured; absent source is not cached"

# Sparse file: du -sb uses apparent bytes. Oversize sources must not be saved
# even when the file consumes no real storage on the test runner.
truncate -s 1400000000 \
  "$tmp/oki/.repo/project-objects/kernel_platform/prebuilts/clang-tools.git/oversize.pack"
: > "$GITHUB_OUTPUT"
bash "$root/scripts/fusion_cache_budget.sh"
grep -qx 'tools_cache_ok=false' "$GITHUB_OUTPUT"
grep -qx 'oss_cache_ok=true' "$GITHUB_OUTPUT"
echo "PASS: over-budget source cache rejected while other caches remain eligible"

# The pipeline may reuse Git objects only; checking out worktrees from a cache
# risks stale source, stale SHA and credentials.
workflow="$root/.github/workflows/fusion-v2-full-oki.yml"
grep -Fq "op13-src-clang-v1-" "$workflow"
grep -Fq "op13-src-tools-v1-" "$workflow"
grep -Fq "op13-src-oss-v1-" "$workflow"
grep -Fq 'hashFiles('\''manifests/oneplus_13_b_20261013_pinned.xml'\'')' "$workflow"
if grep -Eq '^[[:space:]]+oki/\.repo/projects(/|$)' "$workflow"; then
  echo "ERROR: unsafe git worktree metadata included in cache" >&2
  exit 1
fi
echo "PASS: manifest-scoped object caches do not include mutable worktrees"
