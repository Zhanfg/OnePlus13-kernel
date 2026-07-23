#!/bin/bash
set -u
TMP=/tmp/schq_ver
rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP"

check() {
  local url="$1"
  local br="$2"
  local dir="$3"
  echo ""
  echo "======== $url @ $br ========"
  rm -rf "$dir"
  if ! git clone --depth 1 --branch "$br" --filter=blob:none --sparse "$url" "$dir" 2>"$dir.err"; then
    echo "CLONE FAIL"
    cat "$dir.err" | tail -3
    return 1
  fi
  (
    cd "$dir" || exit 1
    git sparse-checkout set Makefile 2>/dev/null || true
    if [ -f Makefile ]; then
      head -6 Makefile
    else
      echo "(no Makefile at root)"
      ls | head -15
    fi
    echo "HEAD: $(git log -1 --oneline)"
    git log -1 --format=%s
  )
}

check "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" \
  "oneplus/sm8750_v_16.0.0_oneplus_13" "common_v16"
check "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" \
  "clo-rebase" "common_clo"
check "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" \
  "android15-6.6" "common_a15"
check "https://github.com/schqiushui/android_kernel_oneplus_sm8750.git" \
  "oneplus/sm8750_v_16.0.0_oneplus_13" "msm_v16"
check "https://github.com/schqiushui/android_kernel_oneplus_sm8750.git" \
  "kernel.lnx.6.6.r1-rel" "msm_118"
check "https://github.com/schqiushui/android_kernel_oneplus_sm8750.git" \
  "clo-rebase" "msm_clo"

# Does common have a 6.6.118-related branch name?
echo ""
echo "======== all common branches containing 6.6 or lnx ========"
git ls-remote --heads https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git \
  | grep -iE '6\.6|lnx|118|android15|clo|16\.0'

echo DONE
