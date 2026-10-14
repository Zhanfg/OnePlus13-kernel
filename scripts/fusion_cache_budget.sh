#!/usr/bin/env bash
# Fail-safe cache budget gate for GitHub Actions: preserve build, skip oversize cache.
set -euo pipefail
root="${GITHUB_WORKSPACE:-$(pwd)}"
out="${GITHUB_OUTPUT:-}"
[[ -n "$out" ]] || { echo "GITHUB_OUTPUT required" >&2; exit 2; }
within() {
  local label="$1" limit="$2"
  shift 2
  local path bytes=0 one
  for path in "$@"; do
    [[ -d "$root/$path" ]] || continue
    one="$(du -sb "$root/$path" | awk '{print $1}')"
    bytes=$((bytes + one))
  done
  local ok=false
  if (( bytes > 0 && bytes <= limit * 1024 * 1024 )); then ok=true; fi
  printf '%s=%s\n' "$label" "$ok" >> "$out"
  echo "[cache-budget] $label bytes=$bytes max_mib=$limit save=$ok"
}
within clang_cache_ok 1600 \
  oki/.repo/project-objects/kernelplatform/prebuilts-master/clang/host/linux-x86.git
within tools_cache_ok 1200 \
  oki/.repo/project-objects/kernel_platform/prebuilts/clang-tools.git \
  oki/.repo/project-objects/kernel_platform/prebuilts/build-tools.git \
  oki/.repo/project-objects/kernel/prebuilts/build-tools.git
within oss_cache_ok 1800 \
  oki/.repo/project-objects/android_kernel_common_oneplus_sm8750.git \
  oki/.repo/project-objects/android_kernel_oneplus_sm8750.git \
  oki/.repo/project-objects/android_kernel_modules_and_devicetree_oneplus_sm8750.git
within bazel_cache_ok 3000 \
  .fusion-cache/bazel-disk \
  .fusion-cache/bazel-repository
