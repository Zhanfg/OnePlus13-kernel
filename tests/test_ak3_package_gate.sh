#!/bin/bash
# Issue #7: packaging must not emit a flashable ZIP without an AnyKernel3 template.
# Uses a fake Image only. This does not boot or flash anything.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP"
    rm -f "$ROOT"/OnePlus13-sun-custom-*.zip "$ROOT"/OnePlus13-sun-custom-*.zip.sha256
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

mkdir -p "$TMP/out/arch/arm64/boot"
printf 'stub-image\n' > "$TMP/out/arch/arm64/boot/Image"

assert_no_zip() {
    if compgen -G "$ROOT/OnePlus13-sun-custom-*.zip" >/dev/null; then
        fail "$*: a zip was produced"
    fi
}

run_package() {
    local ak3="$1"
    local logfile="$2"
    OUT_DIR="$TMP/out" AK3_DIR="$ak3" bash "$ROOT/build.sh" package >"$logfile" 2>&1
}

# Missing template directory.
rm -rf "$TMP/out/anykernel"
set +e
run_package "$TMP/no-such-anykernel" "$TMP/missing.log"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    fail "missing template: package exited 0"
fi
grep -q "AnyKernel3 模板目录不存在" "$TMP/missing.log" \
    || fail "missing template: error message not found"
if grep -q "AK3 打包完成" "$TMP/missing.log"; then
    fail "missing template: reported AK3 success"
fi
assert_no_zip "missing template"
pass "missing template: package exits nonzero and writes no zip"

# Empty template directory.
mkdir -p "$TMP/empty-ak3"
rm -rf "$TMP/out/anykernel"
set +e
run_package "$TMP/empty-ak3" "$TMP/empty.log"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    fail "empty template: package exited 0"
fi
grep -q "AnyKernel3 模板目录为空" "$TMP/empty.log" \
    || fail "empty template: error message not found"
assert_no_zip "empty template"
pass "empty template: package exits nonzero and writes no zip"

# Template missing one required installer file.
mkdir -p "$TMP/partial-ak3/META-INF/com/google/android"
printf 'anykernel\n' > "$TMP/partial-ak3/anykernel.sh"
printf 'service\n' > "$TMP/partial-ak3/service.sh"
printf 'prop\n' > "$TMP/partial-ak3/module.prop"
printf 'updater-script\n' > "$TMP/partial-ak3/META-INF/com/google/android/updater-script"
rm -rf "$TMP/out/anykernel"
set +e
run_package "$TMP/partial-ak3" "$TMP/partial.log"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    fail "incomplete template: package exited 0"
fi
grep -q "AK3 模板缺少必需文件: META-INF/com/google/android/update-binary" "$TMP/partial.log" \
    || fail "incomplete template: missing-file error not found"
if grep -q "AK3 打包完成" "$TMP/partial.log"; then
    fail "incomplete template: reported AK3 success"
fi
assert_no_zip "incomplete template"
pass "incomplete template: missing required file rejects the zip"

# Complete template still packages.
mkdir -p "$TMP/full-ak3/META-INF/com/google/android" "$TMP/full-ak3/extra"
printf 'anykernel-ok\n' > "$TMP/full-ak3/anykernel.sh"
printf 'service-ok\n' > "$TMP/full-ak3/service.sh"
printf 'prop-ok\n' > "$TMP/full-ak3/module.prop"
printf 'update-binary-ok\n' > "$TMP/full-ak3/META-INF/com/google/android/update-binary"
printf 'updater-script-ok\n' > "$TMP/full-ak3/META-INF/com/google/android/updater-script"
printf 'extra\n' > "$TMP/full-ak3/extra/note.txt"
rm -rf "$TMP/out/anykernel"
set +e
run_package "$TMP/full-ak3" "$TMP/full.log"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    cat "$TMP/full.log" >&2
    fail "complete template: package exited $rc"
fi
grep -q "AK3 打包完成" "$TMP/full.log" || fail "complete template: success was not reported"
zip_line="$(grep -E 'ZIP: ' "$TMP/full.log" | tail -1)"
zip_path="${zip_line#*ZIP: }"
zip_path="${zip_path//$'\r'/}"
[ -f "$zip_path" ] || fail "complete template: zip path not found ($zip_path)"
unzip -l "$zip_path" > "$TMP/ziplist.txt"
grep -q "anykernel.sh" "$TMP/ziplist.txt" || fail "complete template: zip lacks anykernel.sh"
grep -q "update-binary" "$TMP/ziplist.txt" || fail "complete template: zip lacks update-binary"
grep -q "updater-script" "$TMP/ziplist.txt" || fail "complete template: zip lacks updater-script"
grep -q " Image$" "$TMP/ziplist.txt" || grep -q "Image" "$TMP/ziplist.txt" || fail "complete template: zip lacks Image"
pass "complete template: package still produces a zip"
