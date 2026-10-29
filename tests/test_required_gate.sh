#!/bin/bash
# Issue #10: manifest required=true must stop apply. Optional entries still continue.
# shellcheck disable=SC2030,SC2031,SC2317
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# shellcheck disable=SC1091
source "$ROOT/scripts/patch.sh"
eval "$(declare -f get_manifest | sed '1s/get_manifest/get_manifest_real/')"

if manifest_is_required resukisu; then
    pass "manifest: resukisu is required"
else
    fail "manifest: resukisu was not required"
fi
if manifest_is_required bbrv3 && manifest_is_required ntsync && manifest_is_required baseband-guard; then
    pass "manifest: bbrv3, ntsync and baseband-guard are required"
else
    fail "manifest: a required entry parsed as optional"
fi
if manifest_is_required adios-iosched || manifest_is_required f2fs-optimizations; then
    fail "manifest: an optional entry parsed as required"
fi
pass "manifest: adios-iosched and f2fs-optimizations are not required"

set +e
( manifest_is_required not-a-real-entry >/dev/null 2>&1 )
unknown_rc=$?
set -e
if [ "$unknown_rc" -eq 0 ]; then
    fail "manifest: unknown name was accepted"
fi
pass "manifest: unknown name fails closed"

# Bash functions are not closures, so bake the filtered manifest to a file.
override_required() {
    local only="${1:-}"
    get_manifest_real | python3 -c '
import json, sys
only = sys.argv[1]
data = json.load(sys.stdin)
for item in data:
    if isinstance(item, dict):
        item["required"] = bool(only) and item.get("name") == only
json.dump(data, sys.stdout)
' "$only" > "$TMP/manifest.json"
    get_manifest() { cat "$TMP/manifest.json"; }
}

apply_in() {
    local logfile="$1"
    local kdir="$2"
    local pdir="$3"
    local rdir="$4"
    local only="$5"
    set +e
    (
        set -euo pipefail
        export KERNEL_DIR="$kdir"
        export PATCHES_DIR="$pdir"
        export ROOT_DIR="$rdir"
        if [ "$only" = "none" ]; then
            override_required ""
        elif [ -n "$only" ]; then
            override_required "$only"
        fi
        cmd_apply
    ) >"$logfile" 2>&1
    local rc=$?
    set -e
    echo "$rc"
}

write_patch() {
    local path="$1"
    local file="$2"
    local old="$3"
    local new="$4"
    mkdir -p "$(dirname "$path")"
    cat > "$path" << EOF
--- a/${file}
+++ b/${file}
@@ -1 +1 @@
-${old}
+${new}
EOF
}

prepare_root() {
    local dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir/kernel_source" "$dir/patches/cache"
    printf 'old\n' > "$dir/kernel_source/foo.txt"
}

prepare_root "$TMP/real"
rc="$(apply_in "$TMP/real.log" "$TMP/real/kernel_source" "$TMP/real/patches" "$ROOT" "")"
if [ "$rc" -eq 0 ]; then
    cat "$TMP/real.log" >&2
    fail "missing required dir: apply exited 0"
fi
grep -q "required 补丁缺失: resukisu: ReSukiSU kernel dir 不存在" "$TMP/real.log" \
    || fail "missing required dir: resukisu error not found"
if grep -q "补丁合入完成" "$TMP/real.log"; then
    fail "missing required dir: apply reported success"
fi
pass "missing required dir: apply exits nonzero"

prepare_root "$TMP/optional"
write_patch "$TMP/optional/patches/cache/WildKernels/common/f2fs_bad.patch" \
    foo.txt nope applied-bad
rc="$(apply_in "$TMP/optional.log" "$TMP/optional/kernel_source" "$TMP/optional/patches" "$TMP/optional" "none")"
if [ "$rc" -ne 0 ]; then
    cat "$TMP/optional.log" >&2
    fail "all optional: apply exited $rc"
fi
grep -q "补丁合入完成" "$TMP/optional.log" || fail "all optional: success was not reported"
[ "$(cat "$TMP/optional/kernel_source/foo.txt")" = "old" ] \
    || fail "all optional: a failed optional patch changed the tree"
pass "all required=false: missing dirs and a failed optional patch still finish"

prepare_root "$TMP/bbg-fail"
mkdir -p "$TMP/bbg-fail/patches/cache/Baseband-guard"
cat > "$TMP/bbg-fail/patches/cache/Baseband-guard/setup.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$TMP/bbg-fail/patches/cache/Baseband-guard/setup.sh"
rc="$(apply_in "$TMP/bbg-fail.log" "$TMP/bbg-fail/kernel_source" "$TMP/bbg-fail/patches" "$TMP/bbg-fail" "baseband-guard")"
if [ "$rc" -eq 0 ]; then
    cat "$TMP/bbg-fail.log" >&2
    fail "BBG required failure: apply exited 0"
fi
grep -q "Baseband Guard setup.sh 失败" "$TMP/bbg-fail.log" \
    || fail "BBG required failure: error message not found"
if grep -q "补丁合入完成" "$TMP/bbg-fail.log"; then
    fail "BBG required failure: apply reported success"
fi
pass "BBG setup failure: required=true exits nonzero"

prepare_root "$TMP/bbg-opt"
mkdir -p "$TMP/bbg-opt/patches/cache/Baseband-guard"
cp "$TMP/bbg-fail/patches/cache/Baseband-guard/setup.sh" \
    "$TMP/bbg-opt/patches/cache/Baseband-guard/setup.sh"
rc="$(apply_in "$TMP/bbg-opt.log" "$TMP/bbg-opt/kernel_source" "$TMP/bbg-opt/patches" "$TMP/bbg-opt" "none")"
if [ "$rc" -ne 0 ]; then
    cat "$TMP/bbg-opt.log" >&2
    fail "BBG optional failure: apply exited $rc"
fi
grep -q "BBG setup.sh 执行有警告" "$TMP/bbg-opt.log" \
    || fail "BBG optional failure: warning not found"
grep -q "补丁合入完成" "$TMP/bbg-opt.log" || fail "BBG optional failure: did not finish"
pass "BBG setup failure: required=false stays a warning"

prepare_root "$TMP/hunk-fail"
write_patch "$TMP/hunk-fail/patches/cache/Re-Kernel/bad.patch" missing.txt nope applied
rc="$(apply_in "$TMP/hunk-fail.log" "$TMP/hunk-fail/kernel_source" "$TMP/hunk-fail/patches" "$TMP/hunk-fail" "re-kernel")"
if [ "$rc" -eq 0 ]; then
    cat "$TMP/hunk-fail.log" >&2
    fail "required hunk failure: apply exited 0"
fi
grep -q "required 补丁合入失败: re-kernel" "$TMP/hunk-fail.log" \
    || fail "required hunk failure: error message not found"
if grep -q "补丁合入完成" "$TMP/hunk-fail.log"; then
    fail "required hunk failure: apply reported success"
fi
[ "$(cat "$TMP/hunk-fail/kernel_source/foo.txt")" = "old" ] \
    || fail "required hunk failure: tree changed"
pass "required hunk failure: apply exits nonzero and does not finish"

prepare_root "$TMP/hunk-ok"
write_patch "$TMP/hunk-ok/patches/cache/Re-Kernel/good.patch" foo.txt old applied-rekernel
rc="$(apply_in "$TMP/hunk-ok.log" "$TMP/hunk-ok/kernel_source" "$TMP/hunk-ok/patches" "$TMP/hunk-ok" "re-kernel")"
if [ "$rc" -ne 0 ]; then
    cat "$TMP/hunk-ok.log" >&2
    fail "required hunk success: apply exited $rc"
fi
grep -q "补丁合入完成" "$TMP/hunk-ok.log" || fail "required hunk success: did not finish"
[ "$(cat "$TMP/hunk-ok/kernel_source/foo.txt")" = "applied-rekernel" ] \
    || fail "required hunk success: patch was not applied"
pass "required patch that applies: apply still succeeds"

prepare_root "$TMP/base-ok"
mkdir -p "$TMP/base-ok/kernel_source/arch/arm64/configs"
printf 'CONFIG_BASE=y\n' > "$TMP/base-ok/kernel_source/arch/arm64/configs/sun_defconfig"
rc="$(apply_in "$TMP/base-ok.log" "$TMP/base-ok/kernel_source" "$TMP/base-ok/patches" "$ROOT" "base-config")"
if [ "$rc" -ne 0 ]; then
    cat "$TMP/base-ok.log" >&2
    fail "base-config present: apply exited $rc"
fi
grep -q 'CONFIG_LOCALVERSION="-sun-custom"' \
    "$TMP/base-ok/kernel_source/arch/arm64/configs/sun_defconfig" \
    || fail "base-config present: fragment was not appended"
pass "base-config present: fragment is still appended"

prepare_root "$TMP/ntsync"
rc="$(apply_in "$TMP/ntsync.log" "$TMP/ntsync/kernel_source" "$TMP/ntsync/patches" "$TMP/ntsync" "ntsync")"
if [ "$rc" -eq 0 ]; then
    cat "$TMP/ntsync.log" >&2
    fail "missing ntsync: apply exited 0"
fi
grep -q "required 补丁缺失: ntsync:" "$TMP/ntsync.log" \
    || fail "missing ntsync: error message not found"
pass "missing ntsync directory: required=true exits nonzero"

good_cfg="$TMP/good.config"
cat > "$good_cfg" << 'EOF'
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_OVERLAY_FS=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_TCP_CONG_BBR=y
CONFIG_NET_SCH_FQ=y
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_NET_SCH_CAKE=y
CONFIG_NETFILTER=y
CONFIG_NF_TPROXY=y
CONFIG_IP_SET=y
CONFIG_WIREGUARD=y
CONFIG_ZRAM=y
CONFIG_ZRAM_MULTI_COMP=y
CONFIG_ZRAM_WRITEBACK=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
EOF

verify_in() {
    local logfile="$1"
    local kdir="$2"
    set +e
    (
        set -euo pipefail
        export KERNEL_DIR="$kdir"
        export ROOT_DIR="$ROOT"
        cmd_verify
    ) >"$logfile" 2>&1
    local rc=$?
    set -e
    echo "$rc"
}

mkdir -p "$TMP/verify-bad"
printf 'old\n' > "$TMP/verify-bad/foo.txt"
printf '%s\n' '# CONFIG_KALLSYMS is not set' > "$TMP/verify-bad/.config"
git -C "$TMP/verify-bad" init -q
git -C "$TMP/verify-bad" add foo.txt .config
git -C "$TMP/verify-bad" -c user.email="test@example.com" -c user.name="test" commit -qm init
rc="$(verify_in "$TMP/verify-bad.log" "$TMP/verify-bad")"
if [ "$rc" -eq 0 ]; then
    cat "$TMP/verify-bad.log" >&2
    fail "verify bad config: exited 0"
fi
grep -q "CONFIG 验证失败" "$TMP/verify-bad.log" || fail "verify bad config: error message not found"
if grep -q "验证完成" "$TMP/verify-bad.log"; then
    fail "verify bad config: reported success"
fi
pass "verify: failed CONFIG check exits nonzero"

mkdir -p "$TMP/verify-good"
cp "$good_cfg" "$TMP/verify-good/.config"
printf 'old\n' > "$TMP/verify-good/foo.txt"
git -C "$TMP/verify-good" init -q
git -C "$TMP/verify-good" add foo.txt .config
git -C "$TMP/verify-good" -c user.email="test@example.com" -c user.name="test" commit -qm init
rc="$(verify_in "$TMP/verify-good.log" "$TMP/verify-good")"
if [ "$rc" -ne 0 ]; then
    cat "$TMP/verify-good.log" >&2
    fail "verify good config: exited $rc"
fi
grep -q "验证完成" "$TMP/verify-good.log" || fail "verify good config: did not finish"
pass "verify: passing CONFIG check still succeeds"
