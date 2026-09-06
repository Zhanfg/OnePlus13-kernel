#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_LOCK="$ROOT_DIR/configs/fusion_v2_sources.lock"
BASE_LOCK="$ROOT_DIR/configs/oneplus_13_16.0.9.401.lock"
IMAGE="${1:-}"
TEMPLATE="${2:-$ROOT_DIR/releases/v6.6.118-OnePlus13-sun-AK3-OKI-VANILLA-20260723_2120.zip}"
OUT_DIR="${3:-$ROOT_DIR/releases/fusion-v2}"

log() { printf '[fusion-v2-ak3] %s\n' "$*"; }
die() { printf '[fusion-v2-ak3][ERROR] %s\n' "$*" >&2; exit 1; }

[[ -n "$IMAGE" ]] || die "usage: $0 <Image.kpatch-next> [safe-template.zip] [output-dir]"
[[ -s "$IMAGE" ]] || die "patched Image missing/empty: $IMAGE"
[[ -s "$TEMPLATE" ]] || die "AK3 template missing/empty: $TEMPLATE"
[[ -f "$SOURCE_LOCK" && -f "$BASE_LOCK" ]] || die "source/base lock file missing"

for tool in unzip zip sha256sum strings grep sed stat mktemp; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool missing: $tool"
done

# shellcheck disable=SC1090
source "$SOURCE_LOCK"
# shellcheck disable=SC1090
source "$BASE_LOCK"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
unzip -q "$TEMPLATE" -d "$stage"

[[ -f "$stage/anykernel.sh" ]] || die "template does not contain anykernel.sh"
[[ -f "$stage/META-INF/com/google/android/update-binary" ]] || die "template lacks AnyKernel3 update-binary"

# Fusion V2 first-stage package is strictly Image-only. Refuse a template that carries
# vendor_boot flashing logic rather than silently rewriting unknown installer semantics.
if [[ -e "$stage/vendor_boot.img" ]] || grep -Eiq 'flash_(generic|boot).*vendor_boot|vendor_boot\.img' "$stage/anykernel.sh"; then
  die "template contains vendor_boot payload/flashing logic; use an Image-only verified AK3 template"
fi

rm -f "$stage/Image" "$stage/Image.gz" "$stage/Image.lz4" "$stage/Image-dtb"
cp "$IMAGE" "$stage/Image"

image_sha="$(sha256sum "$IMAGE" | awk '{print $1}')"
image_size="$(stat -c '%s' "$IMAGE")"
(( image_size > 20 * 1024 * 1024 )) || die "patched Image unexpectedly small: $image_size bytes"

kernel_string='OnePlus13 Fusion V2 | ReSukiSU + SUSFS 2.3.0 + KPatch-Next | Experimental'
if grep -q '^kernel.string=' "$stage/anykernel.sh"; then
  sed -i "s|^kernel.string=.*|kernel.string=${kernel_string}|" "$stage/anykernel.sh"
else
  die "template anykernel.sh has no kernel.string field; refusing ambiguous template"
fi

# Normalize shell files without changing installer logic.
find "$stage" -type f \( -name '*.sh' -o -name 'update-binary' \) -print0 | while IFS= read -r -d '' f; do
  sed -i 's/\r$//' "$f"
done
chmod 755 "$stage/META-INF/com/google/android/update-binary" 2>/dev/null || true

cat > "$stage/FUSION_V2_PROVENANCE.txt" <<EOF
status=Experimental
flash_scope=Image-only
device=$DEVICE_MODEL/$DEVICE_CODENAME
rom_base=$ROM_BASE
oneplus_common_sha=$ONEPLUS_COMMON_SHA
oneplus_msm_sha=$ONEPLUS_MSM_SHA
oneplus_modules_sha=$ONEPLUS_MODULES_SHA
resukisu_sha=$RESUKISU_COMMIT
susfs_sha=$SUSFS_COMMIT
susfs_version=v2.3.0
kpatch_next_sha=$KPATCH_NEXT_COMMIT
image_sha256=$image_sha
image_size=$image_size

This archive is not Boot Verified or Runtime Verified until physical-device testing is recorded.
EOF

mkdir -p "$OUT_DIR"
stamp="$(date +%Y%m%d_%H%M%S)"
out="$OUT_DIR/OnePlus13-sun-FusionV2-Experimental-${stamp}.zip"
(
  cd "$stage"
  zip -q -r9 "$out" . -x '*.DS_Store' '__MACOSX/*'
)
[[ -s "$out" ]] || die "AK3 archive was not created"

# Verify that the exact patched Image is in the final archive.
packed_sha="$(unzip -p "$out" Image | sha256sum | awk '{print $1}')"
[[ "$packed_sha" == "$image_sha" ]] || die "packed Image SHA mismatch: expected $image_sha got $packed_sha"

unzip -p "$out" anykernel.sh | grep -Fq "$kernel_string" || die "kernel.string verification failed"
unzip -l "$out" | grep -q 'FUSION_V2_PROVENANCE.txt' || die "provenance file missing from final archive"

sha256sum "$out" > "$out.sha256"

cat <<EOF
Fusion V2 AK3 package: PASS
archive=$out
archive_sha256=$(awk '{print $1}' "$out.sha256")
image_sha256=$image_sha
scope=Image-only
status=Experimental
EOF
