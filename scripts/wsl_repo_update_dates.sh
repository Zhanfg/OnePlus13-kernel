#!/bin/bash
# Show last update times for candidate kernel repos/branches
set -u

print_branch_date() {
  local name="$1"
  local url="$2"
  local branch="$3"
  echo ""
  echo "======== $name ========"
  echo "repo: $url"
  echo "branch: $branch"
  # get commit hash for branch
  local line hash
  line=$(git ls-remote --heads "$url" "refs/heads/${branch}" 2>/dev/null | head -1)
  if [ -z "$line" ]; then
    # try without refs/heads
    line=$(git ls-remote --heads "$url" "$branch" 2>/dev/null | head -1)
  fi
  if [ -z "$line" ]; then
    echo "STATUS: branch not found or repo unreachable"
    return 1
  fi
  hash=$(echo "$line" | awk '{print $1}')
  echo "tip: $hash"
  # shallow fetch commit date via git archive not available; use git clone depth1 log
  local dir
  dir=$(mktemp -d /tmp/rdate.XXXXXX)
  if git clone --depth 1 --branch "$branch" --filter=blob:none --sparse "$url" "$dir/r" 2>/dev/null; then
    (
      cd "$dir/r" || exit 0
      git log -1 --format='author_date: %ai%ncommitter_date: %ci%nsubject: %s%nauthor: %an'
    )
  else
    echo "STATUS: clone failed (cannot get date)"
  fi
  rm -rf "$dir"
}

echo "Query time (host): $(date -Is)"
echo "=============================================="

# Brokestar
print_branch_date "破星 brokestar233" \
  "https://github.com/brokestar233/android_kernel_common_oneplus_sm8750.git" \
  "6.6-final"
print_branch_date "破星 brokestar233" \
  "https://github.com/brokestar233/android_kernel_common_oneplus_sm8750.git" \
  "dev"

# schqiushui
print_branch_date "schqiushui msm-kernel" \
  "https://github.com/schqiushui/android_kernel_oneplus_sm8750.git" \
  "kernel.lnx.6.6.r1-rel"
print_branch_date "schqiushui msm-kernel" \
  "https://github.com/schqiushui/android_kernel_oneplus_sm8750.git" \
  "clo-rebase"
print_branch_date "schqiushui common" \
  "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" \
  "android15-6.6"
print_branch_date "schqiushui common" \
  "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" \
  "oneplus/sm8750_v_16.0.0_oneplus_13"
print_branch_date "schqiushui common" \
  "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" \
  "clo-rebase"

# LineageOS
print_branch_date "LineageOS sm8750" \
  "https://github.com/LineageOS/android_kernel_oneplus_sm8750.git" \
  "lineage-23.2"

# OnePlusOSS
print_branch_date "OnePlusOSS oneplus_13" \
  "https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750.git" \
  "oneplus/sm8750_b_16.0.0_oneplus_13"
print_branch_date "OnePlusOSS common oneplus_13" \
  "https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750.git" \
  "oneplus/sm8750_b_16.0.0_oneplus_13"

# AOSP tag (not a branch)
echo ""
echo "======== AOSP GKI tag android15-6.6.118_r00 ========"
git ls-remote https://android.googlesource.com/kernel/common refs/tags/android15-6.6.118_r00 2>/dev/null | head -2
# try get tagger date via clone
dir=$(mktemp -d /tmp/aosp.XXXXXX)
if git clone --depth 1 --branch android15-6.6.118_r00 --filter=blob:none --sparse \
    https://android.googlesource.com/kernel/common "$dir/r" 2>/dev/null; then
  (
    cd "$dir/r" || exit 0
    git log -1 --format='author_date: %ai%ncommitter_date: %ci%nsubject: %s'
    head -5 Makefile
  )
else
  echo "AOSP shallow tag clone failed or slow"
fi
rm -rf "$dir"

# Working AK3 image build date from strings (if available)
echo ""
echo "======== 你能刷的 AK3 Image 内建时间串 ========"
AK3=/mnt/d/OnePlus13-kernel/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip
if [ -f "$AK3" ]; then
  unzip -p "$AK3" Image 2>/dev/null | strings | grep -iE 'Linux version|SMP PREEMPT' | head -4
  echo "AK3 zip mtime (host file): $(stat -c %y "$AK3" 2>/dev/null || stat -f %Sm "$AK3" 2>/dev/null)"
fi

# Stock boot
echo ""
echo "======== 官方 stock boot.img 内建时间串 ========"
BOOT=/mnt/d/OnePlus13-kernel/releases/restore/boot.img
if [ -f "$BOOT" ]; then
  strings "$BOOT" | grep -iE 'Linux version|SMP PREEMPT' | head -4
  echo "boot.img file mtime: $(stat -c %y "$BOOT" 2>/dev/null)"
fi

echo ""
echo "DONE $(date -Is)"
