#!/usr/bin/env bash
# Show actual persistent-cache payload sizes without claiming a cache hit.
set -euo pipefail
workspace="${GITHUB_WORKSPACE:-$(pwd)}"
function show() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    printf '[fusion-cache] %-19s %12s %s\n' "$label" "$(du -sh "$path" | awk '{print $1}')" "$path"
  else
    printf '[fusion-cache] %-19s %12s %s\n' "$label" 'MISS/EMPTY' "$path"
  fi
}
show 'bazel-disk' "$workspace/.fusion-cache/bazel-disk"
show 'bazel-repository' "$workspace/.fusion-cache/bazel-repository"
show 'src-clang' "$workspace/oki/.repo/project-objects/kernelplatform/prebuilts-master/clang/host/linux-x86.git"
show 'src-compiler-tools' "$workspace/oki/.repo/project-objects/kernel_platform/prebuilts/clang-tools.git"
show 'src-build-tools' "$workspace/oki/.repo/project-objects/kernel_platform/prebuilts/build-tools.git"
show 'src-vendor' "$workspace/oki/.repo/project-objects/android_kernel_modules_and_devicetree_oneplus_sm8750.git"
show 'src-common' "$workspace/oki/.repo/project-objects/android_kernel_common_oneplus_sm8750.git"
df -h "$workspace"
