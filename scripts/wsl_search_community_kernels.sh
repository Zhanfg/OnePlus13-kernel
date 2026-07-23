#!/bin/bash
# Search community repos for OnePlus 13 / sm8750 kernels near 6.6.118
set -u
TMP=/tmp/community_kernels
rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP"

check_repo() {
  local url="$1"
  local branch="$2"
  local name
  name=$(echo "$url" | sed 's|https://github.com/||;s|/|_|g;s|\.git||')
  echo ""
  echo "======== $url  branch=$branch ========"
  rm -rf "$name"
  if ! git clone --depth 1 --branch "$branch" --filter=blob:none --sparse "$url" "$name" 2>"$name.err"; then
    echo "CLONE FAIL:"
    tail -5 "$name.err"
    return 1
  fi
  cd "$name" || return 1
  git sparse-checkout set Makefile README.md 2>/dev/null || true
  if [ -f Makefile ]; then
    echo "Makefile version:"
    head -5 Makefile
  elif [ -f kernel/Makefile ]; then
    echo "kernel/Makefile version:"
    head -5 kernel/Makefile
  else
    echo "No top Makefile, listing:"
    ls | head -20
  fi
  echo "HEAD: $(git log -1 --oneline 2>/dev/null)"
  echo "Commit msg match 16.0.9/6.6.118?"
  git log -1 --format=%B 2>/dev/null | head -5
  cd "$TMP" || true
}

# Known community candidates
check_repo "https://github.com/LineageOS/android_kernel_oneplus_sm8750.git" "lineage-23.2"
check_repo "https://github.com/brokestar233/android_kernel_common_oneplus_sm8750.git" "6.6-final"
check_repo "https://github.com/brokestar233/android_kernel_common_oneplus_sm8750.git" "dev"

# WildJames / common build bases often use google common
echo ""
echo "======== AOSP common android15-6.6.118_r00 ========"
git ls-remote https://android.googlesource.com/kernel/common refs/tags/android15-6.6.118_r00

# Search more github repos via git (no API)
echo ""
echo "======== probe more github names ========"
for path in \
  "schqiushui/android_kernel_oneplus_sm8750" \
  "schqiushui/kernel_manifest" \
  "Numbersf/android_kernel_oneplus_sm8750" \
  "cctv18/android_kernel_oneplus_sm8750" \
  "HanetakaChou/android_kernel_oneplus_sm8750" \
  "Persano/android_kernel_oneplus_sm8750" \
  "OnePlusOSS/android_kernel_common_oneplus_sm8750" \
  "yuzhihui1008/android_kernel_oneplus_sm8750" \
  "AsakuraHaise/android_kernel_oneplus_sm8750" \
  "kernelsu-sm8750/android_kernel_common_oneplus_sm8750" \
  "OplusOpenSource/android_kernel_oneplus_sm8750"
 do
  url="https://github.com/${path}.git"
  echo -n "probe $path ... "
  if git ls-remote --heads "$url" 2>/dev/null | head -3 | grep -q .; then
    echo "EXISTS"
    git ls-remote --heads "$url" 2>/dev/null | head -10
  else
    echo "no"
  fi
done

echo ""
echo "======== TheWildJames OnePlus scripts via raw ========"
curl -sL "https://raw.githubusercontent.com/TheWildJames/kernel_build_scripts/main/OnePlus/opopen_a15_build_kernel_susfs_release.sh" 2>/dev/null | head -80

echo DONE
