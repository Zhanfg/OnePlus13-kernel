#!/bin/bash
# Issue #6: config verification must fail closed after olddefconfig.
# A stub make stands in for the kernel build; this does not compile a kernel.
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

cat > "$TMP/good.config" << 'EOF'
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

bash "$ROOT/configs/verify_config.sh" "$TMP/good.config" >/dev/null
pass "fixture: complete .config passes verify_config.sh"

printf '%s\n' '# CONFIG_KALLSYMS is not set' > "$TMP/bad.config"
if bash "$ROOT/configs/verify_config.sh" "$TMP/bad.config" >/dev/null; then
    fail "fixture: broken .config was accepted"
fi
pass "fixture: broken .config fails verify_config.sh"

mkdir -p "$TMP/bin" "$TMP/ksrc/arch/arm64/configs"
printf '%s\n' 'CONFIG_DUMMY=y' > "$TMP/ksrc/arch/arm64/configs/sun_defconfig"
cat > "$TMP/bin/make" << 'EOF'
#!/bin/bash
out=""
for arg in "$@"; do
    case "$arg" in
        O=*) out="${arg#O=}" ;;
    esac
done
mkdir -p "$out"
mode="${STUB_CONFIG_MODE:-bad}"
if [ "$mode" = "good" ]; then
    cp "$STUB_GOOD_CONFIG" "$out/.config"
else
    cp "$STUB_BAD_CONFIG" "$out/.config"
fi
for arg in "$@"; do
    if [ "$arg" = "Image" ]; then
        mkdir -p "$out/arch/arm64/boot"
        echo 'stub-image' > "$out/arch/arm64/boot/Image"
    fi
done
exit 0
EOF
chmod +x "$TMP/bin/make"

run_build() {
    local mode="$1"
    local cmd="$2"
    local outdir="$3"
    local logfile="$4"
    STUB_CONFIG_MODE="$mode" \
    STUB_GOOD_CONFIG="$TMP/good.config" \
    STUB_BAD_CONFIG="$TMP/bad.config" \
    PATH="$TMP/bin:$PATH" \
    KERNEL_DIR="$TMP/ksrc" \
    OUT_DIR="$outdir" \
        bash "$ROOT/build.sh" "$cmd" >"$logfile" 2>&1
}

set +e
run_build bad config "$TMP/out-bad" "$TMP/bad-config.log"
bad_rc=$?
set -e
if [ "$bad_rc" -eq 0 ]; then
    fail "bad config: build.sh config exited 0"
fi
grep -q "配置验证失败，拒绝继续构建与打包" "$TMP/bad-config.log" \
    || fail "bad config: missing fail-closed error"
if grep -q "内核配置完成" "$TMP/bad-config.log"; then
    fail "bad config: configure reported success"
fi
pass "bad config: build.sh config exits nonzero"

set +e
run_build bad all "$TMP/out-all" "$TMP/bad-all.log"
all_rc=$?
set -e
if [ "$all_rc" -eq 0 ]; then
    fail "bad config: build.sh all exited 0"
fi
if grep -q "编译内核" "$TMP/bad-all.log"; then
    fail "bad config: compile continued after verification failure"
fi
if grep -q "打包 AnyKernel3" "$TMP/bad-all.log"; then
    fail "bad config: packaging continued after verification failure"
fi
if compgen -G "$ROOT/OnePlus13-sun-custom-*.zip" >/dev/null; then
    fail "bad config: an AK3 zip was produced"
fi
pass "bad config: build.sh all stops before compile and packaging"

set +e
run_build good config "$TMP/out-good" "$TMP/good-config.log"
good_rc=$?
set -e
if [ "$good_rc" -ne 0 ]; then
    cat "$TMP/good-config.log" >&2
    fail "good config: build.sh config exited $good_rc"
fi
grep -q "内核配置完成" "$TMP/good-config.log" \
    || fail "good config: configure did not complete"
bash "$ROOT/configs/verify_config.sh" "$TMP/out-good/.config" >/dev/null \
    || fail "good config: final .config does not verify"
pass "good config: build.sh config still succeeds"
