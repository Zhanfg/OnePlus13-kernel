#!/bin/bash
# Issue #9: a patch pattern that matches nothing must not apply every .patch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

write_patch() {
    local path="$1"
    local file="$2"
    local new_text="$3"
    cat > "$path" << EOF
--- a/${file}
+++ b/${file}
@@ -1 +1 @@
-old
+${new_text}
EOF
}

prepare_tree() {
    local dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    printf 'old\n' > "$dir/foo.txt"
    printf 'old\n' > "$dir/bar.txt"
}

# shellcheck disable=SC1091
source "$ROOT/scripts/patch.sh"

prepare_tree "$TMP/k-miss"
mkdir -p "$TMP/patches-miss"
write_patch "$TMP/patches-miss/unrelated.patch" bar.txt applied-unrelated
write_patch "$TMP/patches-miss/also-unrelated.patch" foo.txt applied-other
export KERNEL_DIR="$TMP/k-miss"
set +e
apply_patch_files "$TMP/patches-miss" "fengchi_oneplus_13*.patch" >"$TMP/miss.log" 2>&1
miss_rc=$?
set -e
if [ "$miss_rc" -eq 0 ]; then
    fail "no match: apply_patch_files exited 0"
fi
grep -q "指定模式无匹配，拒绝回退为应用全部 .patch" "$TMP/miss.log" \
    || fail "no match: missing fail-closed error"
if grep -q "应用: unrelated.patch" "$TMP/miss.log"; then
    fail "no match: unrelated patch was selected"
fi
[ "$(cat "$TMP/k-miss/foo.txt")" = "old" ] || fail "no match: foo.txt changed"
[ "$(cat "$TMP/k-miss/bar.txt")" = "old" ] || fail "no match: bar.txt changed"
pass "no match: command fails and applies zero patches"

prepare_tree "$TMP/k-hit"
mkdir -p "$TMP/patches-hit/nested"
write_patch "$TMP/patches-hit/fengchi_oneplus_13_sched.patch" foo.txt applied-target
write_patch "$TMP/patches-hit/nested/unrelated.patch" bar.txt applied-unrelated
export KERNEL_DIR="$TMP/k-hit"
set +e
apply_patch_files "$TMP/patches-hit" "fengchi_oneplus_13*.patch" >"$TMP/hit.log" 2>&1
hit_rc=$?
set -e
if [ "$hit_rc" -ne 0 ]; then
    cat "$TMP/hit.log" >&2
    fail "matching pattern: apply_patch_files exited $hit_rc"
fi
[ "$(cat "$TMP/k-hit/foo.txt")" = "applied-target" ] || fail "matching pattern: target patch was not applied"
[ "$(cat "$TMP/k-hit/bar.txt")" = "old" ] || fail "matching pattern: unrelated patch was applied"
if grep -q "unrelated.patch" "$TMP/hit.log"; then
    fail "matching pattern: unrelated patch was selected"
fi
pass "matching pattern: only the named patch is applied"

prepare_tree "$TMP/k-star"
mkdir -p "$TMP/patches-star"
write_patch "$TMP/patches-star/one.patch" foo.txt applied-one
export KERNEL_DIR="$TMP/k-star"
set +e
apply_patch_files "$TMP/patches-star" "*.patch" >"$TMP/star.log" 2>&1
star_rc=$?
set -e
if [ "$star_rc" -ne 0 ]; then
    cat "$TMP/star.log" >&2
    fail "explicit *.patch: exited $star_rc"
fi
[ "$(cat "$TMP/k-star/foo.txt")" = "applied-one" ] || fail "explicit *.patch: matching patch was not applied"
pass "explicit *.patch: an actual match still applies"
