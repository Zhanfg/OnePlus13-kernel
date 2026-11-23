#!/bin/bash
# Exercise extraction using small, synthetic archives. No device is needed.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

STOCK_NAME=oplus13-16.0.9.401-stock.zip
AK3_NAME=AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip
DEST="$TMP/root"
mkdir -p "$DEST" "$TMP/stock/META-INF/com/android" "$TMP/ak3" "$TMP/work"
printf '# test installer\n' > "$TMP/ak3/anykernel.sh"
printf 'Linux version test\n' > "$TMP/ak3/Image"
(cd "$TMP/ak3" && zip -q "$DEST/$AK3_NAME" anykernel.sh Image)

make_stock() {
    local fingerprint="$1"
    local content="$2"
    local partition
    for partition in boot init_boot dtbo recovery; do
        printf '%s %s\n' "$content" "$partition" > "$TMP/stock/$partition.img"
    done
    printf 'post-build=%s\npost-build-incremental=401\n' "$fingerprint" \
        > "$TMP/stock/META-INF/com/android/metadata"
    rm -f "$DEST/$STOCK_NAME"
    (cd "$TMP/stock" && zip -qr "$DEST/$STOCK_NAME" .)
}

run_extract() {
    ROOT="$DEST" TMPDIR="$TMP/work" bash "$REPO/scripts/wsl_extract_user_ref.sh" > "$1" 2> "$1.err"
}

make_stock 'test/device/build:1/401/release-keys' first
source_sha="$(sha256sum "$DEST/$STOCK_NAME" | awk '{print $1}')"
if EXPECTED_SOURCE_SHA256=$(printf '%064d' 0) run_extract "$TMP/digest.log"; then
    fail "incorrect expected source SHA-256 was accepted"
fi
[ ! -e "$DEST/releases/restore" ] || fail "digest mismatch published restore files"
EXPECTED_SOURCE_SHA256="$source_sha" run_extract "$TMP/first.log" \
    || { cat "$TMP/first.log" "$TMP/first.log.err" >&2; fail "initial extraction"; }
RESTORE="$DEST/releases/restore"
PROVENANCE="$RESTORE/restore-provenance.txt"
[ -f "$PROVENANCE" ] || fail "provenance manifest missing"
grep -Fx "SOURCE_SHA256=$source_sha" "$PROVENANCE" >/dev/null || fail "source SHA-256"
grep -Fx 'BUILD_FINGERPRINT=test/device/build:1/401/release-keys' "$PROVENANCE" >/dev/null || fail "fingerprint"
grep -Fx 'BUILD_INCREMENTAL=401' "$PROVENANCE" >/dev/null || fail "build incremental"
for partition in boot init_boot dtbo recovery; do
    image_sha="$(sha256sum "$RESTORE/$partition.img" | awk '{print $1}')"
    grep -Fx "IMAGE_SHA256_${partition}=$image_sha" "$PROVENANCE" >/dev/null || fail "$partition SHA-256"
    cmp "$TMP/stock/$partition.img" "$RESTORE/$partition.img" || fail "$partition content"
done
cmp "$REPO/releases/restore/RESTORE_FASTBOOT.txt" "$RESTORE/RESTORE_FASTBOOT.txt" \
    || fail "generated fastboot instructions differ from tracked version"
pass "extraction records source and image hashes and generates the tracked instructions"

mkdir "$TMP/before"
cp "$PROVENANCE" "$RESTORE/"*.img "$TMP/before/"
make_stock 'test/device/build:1/other/release-keys' second
if run_extract "$TMP/mismatch.log"; then
    fail "different fingerprint was accepted"
fi
grep -qi 'fingerprint\|指纹' "$TMP/mismatch.log.err" || fail "missing fingerprint error"
cmp "$TMP/before/restore-provenance.txt" "$PROVENANCE" || fail "manifest changed on rejection"
for partition in boot init_boot dtbo recovery; do
    cmp "$TMP/before/$partition.img" "$RESTORE/$partition.img" || fail "$partition changed on rejection"
done
pass "different fingerprint rejects overwrite without changing the images or manifest"

# A missing manifest can be reconstructed only when the existing images match.
make_stock 'test/device/build:1/401/release-keys' first
rm "$PROVENANCE"
run_extract "$TMP/migrate.log" || { cat "$TMP/migrate.log.err" >&2; fail "matching images migration"; }
grep -Fx 'BUILD_FINGERPRINT=test/device/build:1/401/release-keys' "$PROVENANCE" >/dev/null \
    || fail "matching images migration did not record fingerprint"
rm "$PROVENANCE"
make_stock 'test/device/build:1/other/release-keys' second
if run_extract "$TMP/unknown-existing.log"; then
    fail "different images with unknown provenance were accepted"
fi
[ ! -e "$PROVENANCE" ] || fail "manifest created on unknown provenance rejection"
for partition in boot init_boot dtbo recovery; do
    cmp "$TMP/before/$partition.img" "$RESTORE/$partition.img" || fail "$partition changed on unknown provenance rejection"
done
pass "unknown existing provenance permits matching images and rejects different images"

# A fresh extraction records absent source metadata as unverified and warns on stderr.
rm -rf "$RESTORE"
rm "$TMP/stock/META-INF/com/android/metadata" "$DEST/$STOCK_NAME"
(cd "$TMP/stock" && zip -qr "$DEST/$STOCK_NAME" .)
run_extract "$TMP/unverified.log" || { cat "$TMP/unverified.log.err" >&2; fail "unverified extraction"; }
grep -Fx 'BUILD_FINGERPRINT=unverified' "$PROVENANCE" >/dev/null || fail "missing unverified fingerprint"
grep -Fx 'BUILD_INCREMENTAL=unverified' "$PROVENANCE" >/dev/null || fail "missing unverified build number"
grep -qi 'WARNING.*fingerprint.*unverified' "$TMP/unverified.log.err" || fail "missing fingerprint warning on stderr"
grep -qi 'WARNING.*build number.*unverified' "$TMP/unverified.log.err" || fail "missing build number warning on stderr"
pass "missing source metadata is recorded as unverified with stderr warnings"
