#!/bin/bash
set -euo pipefail
ROOT=/mnt/d/OnePlus13-kernel
REF=/tmp/user_ref
rm -rf "$REF"
mkdir -p "$REF/stock" "$REF/working_ak3"

unzip -o "$ROOT/oplus13-16.0.9.401-stock.zip" -d "$REF/stock"
unzip -o "$ROOT/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip" -d "$REF/working_ak3"

echo "=== working anykernel.sh ==="
cat "$REF/working_ak3/anykernel.sh"

echo "=== working Image version ==="
strings "$REF/working_ak3/Image" | grep -iE 'Linux version' | head -5

echo "=== sizes ==="
ls -lah "$REF/stock"
ls -lah "$REF/working_ak3/Image"

# restore folder for user
mkdir -p "$ROOT/releases/restore"
cp -f "$REF/stock/"*.img "$ROOT/releases/restore/"
cp -f "$ROOT/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip" "$ROOT/releases/" 2>/dev/null || true
cp -f "$ROOT/oplus13-16.0.9.401-stock.zip" "$ROOT/releases/" 2>/dev/null || true

# flash script
cat > "$ROOT/releases/restore/RESTORE_FASTBOOT.txt" << 'EOF'
一加13 救砖 / 恢复开机 (Fastboot)
================================

前提: 手机已进 Fastboot, 电脑能识别:
  fastboot devices

【方案 A — 刷回官方 16.0.9.401 boot（推荐先试）】
  cd 到本目录 releases/restore 后:

  fastboot flash boot boot.img
  fastboot reboot

若双槽不确定, 可两个都刷:
  fastboot flash boot_a boot.img
  fastboot flash boot_b boot.img
  fastboot reboot

【方案 B — 用你确认能刷的 AK3 恢复】
  关机/进系统前, 用 ReSukiSU 管理器:
  刷写 AnyKernel3 -> 选:
  AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip

  或 Fastboot 下若你已用 magiskboot 打好 boot, 刷该 boot.

【本目录文件】
  boot.img       - 官方 16.0.9.401 boot (~96MB, 含内核)
  init_boot.img  - 官方 init_boot (~8MB, ramdisk)
  recovery.img
  dtbo.img

【重要结论】
  你能正常用的核是 6.6.144 (Oplus sun GKI)
  我们之前编的是 6.6.89 — 版本线不对, 所以卡 Logo+黄字
  下一步自定义核必须基于 6.6.144 / 16.0.9.401 对齐重编

【一般不需要先动 init_boot】
  只刷坏 boot 时, 只恢复 boot.img 即可
  若仍异常再考虑:
  fastboot flash init_boot init_boot.img
EOF

echo "=== restore ready ==="
ls -lah "$ROOT/releases/restore/"
echo "DONE"
