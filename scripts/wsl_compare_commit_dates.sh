#!/bin/bash
# Compare tip commit times (committer date) of candidate repos
set -u
echo "查询时间: $(date -Is)"
echo "比较的是分支 tip 的 committer date（提交时间）"
echo "================================================"

one() {
  local label="$1" url="$2" branch="$3"
  local dir hash
  dir=$(mktemp -d /tmp/cdate.XXXXXX)
  if git clone --depth 1 --branch "$branch" --filter=blob:none --sparse "$url" "$dir/r" >/dev/null 2>&1; then
    (
      cd "$dir/r" || exit 0
      # date + subject
      git log -1 --format='%ci|%s|%h|%an'
    ) | while IFS='|' read -r ci subj h an; do
      printf '%s\t%s\t%s\t%s\n' "$ci" "$label" "$branch" "$subj"
    done
  else
    printf '%s\t%s\t%s\t%s\n' "0000-00-00 00:00:00 +0000" "$label" "$branch" "CLONE_FAILED"
  fi
  rm -rf "$dir"
}

# Collect then sort
{
  one "破星 brokestar233" "https://github.com/brokestar233/android_kernel_common_oneplus_sm8750.git" "6.6-final"
  one "破星 brokestar233" "https://github.com/brokestar233/android_kernel_common_oneplus_sm8750.git" "dev"
  one "schqiushui msm 6.6.118" "https://github.com/schqiushui/android_kernel_oneplus_sm8750.git" "kernel.lnx.6.6.r1-rel"
  one "schqiushui msm clo-rebase" "https://github.com/schqiushui/android_kernel_oneplus_sm8750.git" "clo-rebase"
  one "schqiushui common android15-6.6" "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" "android15-6.6"
  one "schqiushui common clo-rebase" "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" "clo-rebase"
  one "schqiushui common v16 oneplus13" "https://github.com/schqiushui/android_kernel_common_oneplus_sm8750.git" "oneplus/sm8750_v_16.0.0_oneplus_13"
  one "LineageOS sm8750" "https://github.com/LineageOS/android_kernel_oneplus_sm8750.git" "lineage-23.2"
  one "OnePlusOSS msm oneplus13" "https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750.git" "oneplus/sm8750_b_16.0.0_oneplus_13"
  one "OnePlusOSS common oneplus13" "https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750.git" "oneplus/sm8750_b_16.0.0_oneplus_13"
} | tee /tmp/commit_dates_raw.txt

echo ""
echo "======== 按提交时间从新到旧 ========"
sort -r /tmp/commit_dates_raw.txt | while IFS=$'\t' read -r ci label br subj; do
  printf '%-28s  %-40s  %s\n' "$ci" "$label ($br)" "$subj"
done

echo ""
echo "======== 成品/官方 Image 内嵌编译时间（不是 git 提交） ========"
if [ -f /mnt/d/OnePlus13-kernel/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip ]; then
  echo -n "可用 AK3 Image: "
  unzip -p /mnt/d/OnePlus13-kernel/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip Image 2>/dev/null \
    | strings | grep -oE 'SMP PREEMPT .*' | head -1
  echo -n "  完整: "
  unzip -p /mnt/d/OnePlus13-kernel/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip Image 2>/dev/null \
    | strings | grep 'Linux version' | head -1
fi
if [ -f /mnt/d/OnePlus13-kernel/releases/restore/boot.img ]; then
  echo -n "官方 stock boot.img: "
  strings /mnt/d/OnePlus13-kernel/releases/restore/boot.img | grep -oE 'SMP PREEMPT .*' | head -1
  echo -n "  完整: "
  strings /mnt/d/OnePlus13-kernel/releases/restore/boot.img | grep 'Linux version' | head -1
fi
echo "你手机 uname -v: #1 SMP PREEMPT Thu Jul  2 11:18:30 CST 2026"
echo DONE
