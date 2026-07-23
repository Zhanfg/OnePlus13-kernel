#!/bin/bash
# Locate OnePlus OSS source matching 6.6.118-android15-9 / PJZ110 16.0.9.401
set -euo pipefail
ROOT=/mnt/d/OnePlus13-kernel
REF=/tmp/baseline_a
rm -rf "$REF"
mkdir -p "$REF/stock" "$REF/ak3" "$REF/boot_unpack"

echo "=== 1. Stock boot version string ==="
unzip -o "$ROOT/oplus13-16.0.9.401-stock.zip" -d "$REF/stock" >/dev/null
MB=
if [ -f "$ROOT/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip" ]; then
  unzip -o "$ROOT/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip" -d "$REF/ak3" >/dev/null
  MB="$REF/ak3/tools/magiskboot"
fi
if [ -n "$MB" ] && [ -x "$MB" ]; then
  cd "$REF/boot_unpack"
  cp "$REF/stock/boot.img" .
  "$MB" unpack boot.img 2>&1 | tail -15
  ls -la
  echo "--- stock kernel strings ---"
  strings kernel 2>/dev/null | grep -iE 'Linux version' | head -5
  echo "--- build user/host ---"
  strings kernel 2>/dev/null | grep -iE 'SMP PREEMPT|android15|g6901' | head -10
fi

echo
echo "=== 2. OnePlusOSS remote branches (sm8750) ==="
# shallow list remote heads
git ls-remote --heads https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750.git 2>/dev/null | grep -iE 'sm8750|16\.0|oneplus_13|b_' | head -40

echo
echo "=== 3. kernel_manifest sm8750 ==="
git ls-remote --heads https://github.com/OnePlusOSS/kernel_manifest.git 2>/dev/null | head -20
# try fetch manifest listing via raw
for path in oneplus/sm8750 oneplus_sm8750 sm8750; do
  echo "try list $path"
done

echo
echo "=== 4. common kernel repo branches ==="
git ls-remote --heads https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750.git 2>/dev/null | grep -iE 'sm8750|16\.0|6\.6|android15' | head -40

echo
echo "=== 5. modules repo ==="
git ls-remote --heads https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750.git 2>/dev/null | grep -iE 'sm8750|16\.0|oneplus_13' | head -40

echo DONE
