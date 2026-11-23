#!/bin/bash
set -euo pipefail
ROOT=${ROOT:-/mnt/d/OnePlus13-kernel}
REF="${TMPDIR:-/tmp}/user_ref"
RESTORE="$ROOT/releases/restore"
mkdir -p "$REF"
WORK=$(mktemp -d "$REF/extract.XXXXXXXX")
STAGE=
BACKUP=
cleanup() {
  if [ -n "$BACKUP" ] && [ -d "$BACKUP" ] && [ ! -e "$RESTORE" ]; then
    mv -T "$BACKUP" "$RESTORE"
  fi
  [ -z "$STAGE" ] || rm -rf "$STAGE"
  if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then
    echo "ERROR: previous restore directory retained at $BACKUP" >&2
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/stock" "$WORK/working_ak3"

STOCK_ZIP="$ROOT/oplus13-16.0.9.401-stock.zip"
AK3_ZIP="$ROOT/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip"
sha256() { sha256sum < "$1" | cut -d ' ' -f 1; }
fail() { echo "ERROR: $*" >&2; exit 1; }
# Hash and extract the same snapshot even if the source file changes during the run.
cp "$STOCK_ZIP" "$WORK/source.zip"
SOURCE_SHA256=$(sha256 "$WORK/source.zip")
if [ -n "${EXPECTED_SOURCE_SHA256:-}" ] && [ "$SOURCE_SHA256" != "${EXPECTED_SOURCE_SHA256,,}" ]; then
  fail "stock ZIP does not match EXPECTED_SOURCE_SHA256"
fi
unzip -o "$WORK/source.zip" -d "$WORK/stock"
unzip -o "$AK3_ZIP" -d "$WORK/working_ak3"

echo "=== working anykernel.sh ==="
cat "$WORK/working_ak3/anykernel.sh"

echo "=== working Image version ==="
strings "$WORK/working_ak3/Image" | grep -iE 'Linux version' | sed -n '1,5p'

echo "=== sizes ==="
ls -lah "$WORK/stock"
ls -lah "$WORK/working_ak3/Image"

stock=$(realpath "$WORK/stock")
metadata="$stock/META-INF/com/android/metadata"
read_property() {
  local file=$1 key=$2
  [ -f "$file" ] && [ ! -L "$file" ] || return 0
  # A metadata path through a symlink could describe a file outside the ZIP.
  if [[ "$file" == "$stock/"* && "$(realpath "$file")" != "$file" ]]; then
    return 0
  fi
  awk -v key="$key" 'index($0, key "=") == 1 { sub(/^[^=]*=/, ""); sub(/\r$/, ""); print; exit }' "$file"
}
BUILD_FINGERPRINT=$(read_property "$metadata" post-build)
BUILD_INCREMENTAL=$(read_property "$metadata" post-build-incremental)
# Use system build properties only when the OTA lacks target metadata.
for prop in "$stock/build.prop" "$stock/system/build.prop" "$stock/SYSTEM/build.prop" "$stock/system/system/build.prop"; do
  [ -n "$BUILD_FINGERPRINT" ] || BUILD_FINGERPRINT=$(read_property "$prop" ro.build.fingerprint)
  [ -n "$BUILD_INCREMENTAL" ] || BUILD_INCREMENTAL=$(read_property "$prop" ro.build.version.incremental)
done
if [ -z "$BUILD_FINGERPRINT" ]; then
  BUILD_FINGERPRINT=unverified
  echo "WARNING: source build fingerprint unavailable; recorded as unverified" >&2
fi
if [ -z "$BUILD_INCREMENTAL" ]; then
  BUILD_INCREMENTAL=unverified
  echo "WARNING: source build number unavailable; recorded as unverified" >&2
fi

for image in boot init_boot dtbo recovery; do
  [ -s "$WORK/stock/$image.img" ] || fail "source package is missing a nonempty $image.img"
done

# Serialize checks and publication with other invocations of this script.
mkdir -p "$ROOT/releases"
exec 9< "$ROOT/releases"
flock -x 9
BACKUP="$ROOT/releases/.restore-previous"
# Finish an interrupted directory swap before checking the installed fingerprint.
if [ -d "$BACKUP" ]; then
  if [ -d "$RESTORE" ]; then
    rm -rf "$BACKUP"
  else
    mv -T "$BACKUP" "$RESTORE"
  fi
fi
shopt -s nullglob
existing_images=("$RESTORE/"*.img)
new_images=("$WORK/stock/"*.img)
if [ ${#existing_images[@]} -gt 0 ]; then
  old_fingerprint=$(read_property "$RESTORE/restore-provenance.txt" BUILD_FINGERPRINT)
  if [ -n "$old_fingerprint" ] && [ "$old_fingerprint" != unverified ] &&
     [ "$old_fingerprint" != "$BUILD_FINGERPRINT" ]; then
    fail "existing restore images have a different source fingerprint; refusing overwrite"
  fi
  old_source_sha=$(read_property "$RESTORE/restore-provenance.txt" SOURCE_SHA256)
  if [[ ! "$old_source_sha" =~ ^[0-9a-f]{64}$ ]]; then
    old_fingerprint=unverified
  fi
  for image in "${existing_images[@]}"; do
    name=${image##*/}
    recorded_sha=$(read_property "$RESTORE/restore-provenance.txt" "IMAGE_SHA256_${name%.img}")
    actual_sha=$(sha256 "$image")
    if [ "$recorded_sha" != "$actual_sha" ]; then
      old_fingerprint=unverified
    fi
  done
  # Unknown provenance can only be associated with a package when all bytes agree.
  if [ -z "$old_fingerprint" ] || [ "$old_fingerprint" = unverified ]; then
    for image in "${existing_images[@]}"; do
      cmp -s "$image" "$WORK/stock/${image##*/}" || fail "unverified existing image differs from source: ${image##*/}"
    done
  fi
fi

STAGE=$(mktemp -d "$ROOT/releases/.restore-stage.XXXXXXXX")
if [ -d "$RESTORE" ]; then
  find "$RESTORE" -maxdepth 1 -mindepth 1 ! -name '*.img' ! -name restore-provenance.txt \
    ! -name RESTORE_FASTBOOT.txt -exec cp -a -t "$STAGE" -- {} +
  chmod --reference="$RESTORE" "$STAGE"
fi
{
  printf 'SOURCE_SHA256=%s\nBUILD_FINGERPRINT=%s\nBUILD_INCREMENTAL=%s\n' "$SOURCE_SHA256" "$BUILD_FINGERPRINT" "$BUILD_INCREMENTAL"
  for image in "${new_images[@]}"; do
    name=${image##*/}
    if [[ ! "$name" =~ ^[a-zA-Z0-9_.-]+\.img$ || ! -f "$image" || -L "$image" ]]; then
      fail "invalid partition image: $name"
    fi
    cp "$image" "$STAGE/$name"
    digest=$(sha256 "$STAGE/$name")
    printf 'IMAGE_SHA256_%s=%s\n' "${name%.img}" "$digest"
  done
} > "$STAGE/restore-provenance.txt"
# flash script
cat > "$STAGE/RESTORE_FASTBOOT.txt" << 'EOF'
一加13 救砖 / 恢复开机 (Fastboot)
================================

前提: 手机已进 Fastboot, 电脑能识别:
  fastboot devices

刷写前查看 restore-provenance.txt，核对镜像 SHA-256 和当前固件的构建指纹、构建号。
例如用 sha256sum boot.img 对照 IMAGE_SHA256_boot。若来源不明或标为 unverified，先核实再刷写。

【方案 A — 恢复当前槽位的 boot】
  cd 到本目录 releases/restore 后，查询当前槽位:
  fastboot getvar current-slot

  读不到 a 或 b 时停止。保留另一槽作为回退，只执行当前槽位对应的一条命令:
  当前槽位为 a: fastboot flash boot_a boot.img
  当前槽位为 b: fastboot flash boot_b boot.img

  确认刷写成功后:
  fastboot reboot

【方案 B — 用你确认能刷的 AK3 恢复】
  关机/进系统前, 用 ReSukiSU 管理器:
  刷写 AnyKernel3 -> 选:
  AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip

  或 Fastboot 下若你已用 magiskboot 打好 boot，先确认当前槽位，
  再只刷入对应的 boot_a 或 boot_b。

【本目录文件】
  boot.img       - boot 镜像
  init_boot.img  - init_boot 镜像
  recovery.img
  dtbo.img

【重要结论】
  你能正常用的核是 6.6.144 (Oplus sun GKI)
  我们之前编的是 6.6.89 — 版本线不对, 所以卡 Logo+黄字
  下一步自定义核必须基于 6.6.144 / 16.0.9.401 对齐重编

【一般不需要先动 init_boot】
  只刷坏 boot 时, 只恢复 boot.img 即可
  确认 init_boot 也需要恢复时，只执行当前槽位对应的一条命令:
  当前槽位为 a: fastboot flash init_boot_a init_boot.img
  当前槽位为 b: fastboot flash init_boot_b init_boot.img
  其他镜像也只在确认需要恢复时刷入当前槽位的对应分区。
EOF

if [ -d "$RESTORE" ]; then
  mv -T "$RESTORE" "$BACKUP"
fi
mv -T "$STAGE" "$RESTORE"
STAGE=
rm -rf "$BACKUP"
BACKUP=
cp -f "$AK3_ZIP" "$ROOT/releases/" 2>/dev/null || true
cp -f "$WORK/source.zip" "$ROOT/releases/${STOCK_ZIP##*/}" 2>/dev/null || true

# Keep the extracted reference trees available at their original WSL paths.
exec 8< "$REF"
flock -x 8
rm -rf "$REF/stock" "$REF/working_ak3"
mv "$WORK/stock" "$WORK/working_ak3" "$REF/"
echo "=== restore ready ==="
ls -lah "$ROOT/releases/restore/"
echo "DONE"
