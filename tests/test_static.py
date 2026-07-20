#!/usr/bin/env python3
"""
静态验收测试 - 一加13 (sun/SM8750) 自定义内核
规格 §4.2.3-A + §6

在编译后、刷机前执行的静态检查:
1. 调度补丁 diff 检查 (非空壳)
2. CONFIG 验证
3. Image 符号检查
4. AK3 脚本完整性检查
5. 默认策略一致性检查
6. 构建脚本完整性
7. CI 工作流检查

用法: python3 tests/test_static.py [kernel_source_dir] [out_dir]
"""

import os
import sys
import re
import subprocess

# 颜色输出
GREEN = '\033[32m'
RED = '\033[31m'
YELLOW = '\033[33m'
BLUE = '\033[34m'
NC = '\033[0m'

PASS_COUNT = 0
FAIL_COUNT = 0
WARN_COUNT = 0


def ok(msg):
    global PASS_COUNT
    print(f"{GREEN}[PASS]{NC} {msg}")
    PASS_COUNT += 1


def fail(msg):
    global FAIL_COUNT
    print(f"{RED}[FAIL]{NC} {msg}")
    FAIL_COUNT += 1


def warn(msg):
    global WARN_COUNT
    print(f"{YELLOW}[WARN]{NC} {msg}")
    WARN_COUNT += 1


def info(msg):
    print(f"{BLUE}[INFO]{NC} {msg}")


def run_cmd(cmd, cwd=None):
    """运行 shell 命令并返回输出"""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, cwd=cwd
        )
        return result.stdout.strip(), result.returncode
    except Exception as e:
        return str(e), 1


def test_sched_patch_diff(kernel_dir):
    """测试1: 调度补丁 diff 检查 (规格 §4.2.3-A.1)"""
    print("\n=== 测试1: 调度补丁 diff 检查 ===")

    if not kernel_dir or not os.path.isdir(kernel_dir):
        warn(f"内核源码目录不存在: {kernel_dir}")
        return

    output, _ = run_cmd(
        "git diff --stat HEAD 2>/dev/null | grep -E 'kernel/sched|hmbird|fengchi|scx'",
        cwd=kernel_dir
    )

    if output:
        lines = output.strip().split('\n')
        file_count = len(lines)
        info(f"调度相关变更文件数: {file_count}")

        if file_count > 2:
            ok(f"调度补丁已合入 ({file_count} 个文件有变更, 非空壳)")
        else:
            fail(f"调度变更较少 ({file_count} 个文件), 疑似空壳")

        info("变更文件 (前10):")
        for line in lines[:10]:
            print(f"  {line}")
    else:
        warn("未找到调度相关 diff (可能未应用补丁或已 commit)")


def test_config(out_dir):
    """测试2: CONFIG 验证 (规格 §6.2)"""
    print("\n=== 测试2: CONFIG 验证 ===")

    config_file = os.path.join(out_dir, ".config")
    if not os.path.isfile(config_file):
        fail(f".config 不存在: {config_file}")
        return

    required_configs = {
        "CONFIG_KALLSYMS": "y",
        "CONFIG_KALLSYMS_ALL": "y",
        "CONFIG_OVERLAY_FS": "y",
        "CONFIG_TMPFS_XATTR": "y",
        "CONFIG_TMPFS_POSIX_ACL": "y",
        "CONFIG_TCP_CONG_BBR": "y",
        "CONFIG_NET_SCH_FQ": "y",
        "CONFIG_NET_SCH_FQ_CODEL": "y",
        "CONFIG_NET_SCH_CAKE": "y",
        "CONFIG_NETFILTER": "y",
        "CONFIG_IP_SET": "y",
        "CONFIG_WIREGUARD": "y",
        "CONFIG_ZRAM": "y",
        "CONFIG_PID_NS": "y",
        "CONFIG_IPC_NS": "y",
        "CONFIG_USER_NS": "y",
        "CONFIG_SYSVIPC": "y",
        "CONFIG_POSIX_MQUEUE": "y",
    }

    with open(config_file, 'r', errors='ignore') as f:
        config_content = f.read()

    for cfg, expected in required_configs.items():
        pattern = f"^{cfg}={expected}"
        not_set_pattern = f"^# {cfg} is not set"

        if re.search(pattern, config_content, re.MULTILINE):
            ok(f"{cfg}={expected}")
        elif re.search(not_set_pattern, config_content, re.MULTILINE):
            fail(f"{cfg} is not set (应为 =y)")
        else:
            mod_pattern = f"^{cfg}=m"
            if re.search(mod_pattern, config_content, re.MULTILINE):
                warn(f"{cfg}=m (模块, 非 =y)")
            else:
                fail(f"{cfg} 未找到")

    tcp_default_match = re.search(r'^CONFIG_DEFAULT_TCP_CONG="([^"]+)"', config_content, re.MULTILINE)
    if tcp_default_match:
        tcp_default = tcp_default_match.group(1)
        info(f"默认 TCP: {tcp_default}")
        if tcp_default == "bbr3":
            ok("默认 TCP = bbr3")
        else:
            warn(f"默认 TCP = {tcp_default} (实际默认由 sysctl 设置)")

    if re.search(r'^CONFIG_TCP_CONG_BBR3=y', config_content, re.MULTILINE):
        ok("CONFIG_TCP_CONG_BBR3=y (BBRv3)")
    else:
        warn("CONFIG_TCP_CONG_BBR3 未找到 (可能由补丁动态提供)")


def test_image_symbols(out_dir):
    """测试3: Image 符号检查 (规格 §4.2.3-A.3)"""
    print("\n=== 测试3: Image 符号检查 ===")

    image_path = os.path.join(out_dir, "arch", "arm64", "boot", "Image")
    if not os.path.isfile(image_path):
        fail(f"内核 Image 不存在: {image_path}")
        return

    info(f"Image 大小: {os.path.getsize(image_path) / 1024 / 1024:.1f} MB")

    expected_symbols = [
        "bbr3", "bbr", "wireguard", "overlay",
        "zram", "fq_codel", "cake", "ntsync",
    ]

    output, _ = run_cmd(f"strings {image_path} 2>/dev/null")

    for sym in expected_symbols:
        if sym.lower() in output.lower():
            ok(f"Image 含符号: {sym}")
        else:
            warn(f"Image 未找到符号: {sym}")

    hmbird_found = "hmbird" in output.lower() or "fengchi" in output.lower()
    if hmbird_found:
        info("Image 含 hmbird/fengchi 字符串 (需运行时验证非空壳)")
    else:
        warn("Image 未找到 hmbird/fengchi 字符串")


def test_ak3_integrity(project_dir):
    """测试4: AK3 脚本完整性检查"""
    print("\n=== 测试4: AK3 脚本完整性检查 ===")

    ak3_dir = os.path.join(project_dir, "anykernel")

    required_files = [
        "anykernel.sh",
        "META-INF/com/google/android/update-binary",
        "META-INF/com/google/android/updater-script",
        "service.sh",
        "module.prop",
    ]

    for f in required_files:
        path = os.path.join(ak3_dir, f)
        if os.path.isfile(path):
            ok(f"AK3 文件存在: {f}")
        else:
            fail(f"AK3 文件缺失: {f}")

    anykernel_sh = os.path.join(ak3_dir, "anykernel.sh")
    if os.path.isfile(anykernel_sh):
        with open(anykernel_sh, 'r', errors='ignore') as f:
            content = f.read()

        if re.search(r'is_slot_device\s*=\s*1', content):
            ok("anykernel.sh: is_slot_device=1")
        else:
            fail("anykernel.sh: 缺少 is_slot_device=1")

        if "init_boot" in content:
            ok("anykernel.sh: 使用 init_boot 刷写路径")
        else:
            fail("anykernel.sh: 未使用 init_boot")

        if "split_boot" in content and "flash_boot" in content:
            ok("anykernel.sh: split_boot + flash_boot")
        else:
            fail("anykernel.sh: 缺少 split_boot/flash_boot")

        for i in range(1, 8):
            if f"[{i}/7]" in content or f"【{i}/7】" in content:
                ok(f"anykernel.sh: 交互菜单 [{i}/7] 存在")
            else:
                fail(f"anykernel.sh: 交互菜单 [{i}/7] 缺失")

        if "音量+" in content and "音量-" in content:
            ok("anykernel.sh: 音量键选择逻辑存在")
        else:
            fail("anykernel.sh: 缺少音量键选择逻辑")

        if "超时" in content:
            ok("anykernel.sh: 超时默认逻辑存在")
        else:
            fail("anykernel.sh: 缺少超时默认逻辑")

        if "KPM" in content or "kpm" in content:
            ok("anykernel.sh: KPM 选项存在")
        else:
            fail("anykernel.sh: 缺少 KPM 选项")

        if "备份" in content or "backup" in content.lower():
            ok("anykernel.sh: 备份逻辑存在")
        else:
            fail("anykernel.sh: 缺少备份逻辑")


def test_default_policies(project_dir):
    """测试5: 默认策略一致性检查 (规格 §3)"""
    print("\n=== 测试5: 默认策略一致性检查 ===")

    ak3_sh = os.path.join(project_dir, "anykernel", "anykernel.sh")
    config_frag = os.path.join(project_dir, "configs", "base_defconfig_fragment")

    if os.path.isfile(ak3_sh):
        with open(ak3_sh, 'r', errors='ignore') as f:
            ak3_content = f.read()

        if 'SCHED_CHOICE="wait"' in ak3_content:
            ok("默认调度 = wait (anykernel.sh)")
        else:
            fail("默认调度未设为 wait")

        if 'TCP_CHOICE="bbr3"' in ak3_content:
            ok("默认 TCP = bbr3 (anykernel.sh)")
        else:
            fail("默认 TCP 未设为 bbr3")

        if 'QDISC_CHOICE="fq"' in ak3_content:
            ok("默认 qdisc = fq (anykernel.sh)")
        else:
            fail("默认 qdisc 未设为 fq")

        if 'ZRAM_CHOICE="lz4"' in ak3_content:
            ok("默认 ZRAM = lz4 (anykernel.sh)")
        else:
            fail("默认 ZRAM 未设为 lz4")

        if 'BBG_CHOICE="on"' in ak3_content:
            ok("默认 BBG = on (anykernel.sh)")
        else:
            fail("默认 BBG 未设为 on")

        if 'KPM_CHOICE="no"' in ak3_content:
            ok("默认 KPM = no/不应用 (anykernel.sh)")
        else:
            fail("默认 KPM 未设为 no")

    if os.path.isfile(config_frag):
        with open(config_frag, 'r', errors='ignore') as f:
            cfg_content = f.read()

        if "CONFIG_KALLSYMS=y" in cfg_content and "CONFIG_KALLSYMS_ALL=y" in cfg_content:
            ok("KALLSYMS + KALLSYMS_ALL = y (config fragment)")
        else:
            fail("KALLSYMS 配置缺失")

        if "CONFIG_OVERLAY_FS=y" in cfg_content:
            ok("OVERLAY_FS = y (config fragment)")
        else:
            fail("OVERLAY_FS 配置缺失")

        if "CONFIG_ZRAM=y" in cfg_content:
            ok("ZRAM = y (config fragment)")
        else:
            fail("ZRAM 配置缺失")

        if "CONFIG_WIREGUARD=y" in cfg_content:
            ok("WIREGUARD = y (config fragment)")
        else:
            fail("WIREGUARD 配置缺失")


def test_build_scripts(project_dir):
    """测试6: 构建脚本完整性"""
    print("\n=== 测试6: 构建脚本完整性 ===")

    scripts = [
        (os.path.join(project_dir, "build.sh"), "build.sh"),
        (os.path.join(project_dir, "scripts", "patch.sh"), "scripts/patch.sh"),
    ]

    for script, name in scripts:
        if os.path.isfile(script):
            ok(f"{name} 存在")

            if os.access(script, os.X_OK):
                ok(f"{name} 可执行")
            else:
                warn(f"{name} 不可执行 (chmod +x)")

            with open(script, 'r', errors='ignore') as f:
                content = f.read()
            if "set -euo pipefail" in content:
                ok(f"{name}: set -euo pipefail (错误处理)")
            else:
                warn(f"{name}: 缺少 set -euo pipefail")
        else:
            fail(f"{name} 不存在")


def test_ci_workflow(project_dir):
    """测试7: CI 工作流检查"""
    print("\n=== 测试7: CI 工作流检查 ===")

    workflow = os.path.join(project_dir, ".github", "workflows", "build.yml")
    if not os.path.isfile(workflow):
        fail("CI 工作流不存在")
        return

    with open(workflow, 'r', errors='ignore') as f:
        content = f.read()

    if "workflow_dispatch" in content:
        ok("CI: 支持手动触发 (workflow_dispatch)")
    else:
        fail("CI: 不支持手动触发")

    if "sha256" in content.lower():
        ok("CI: 生成 sha256 校验")
    else:
        fail("CI: 未生成 sha256")

    if "upload-artifact" in content:
        ok("CI: 上传构建产物")
    else:
        fail("CI: 未上传构建产物")

    if "KERNEL_COMMIT" in content or "git rev-parse" in content:
        ok("CI: 构建日志可追溯 (commit)")
    else:
        fail("CI: 缺少可追溯性")

    if "changelog" in content.lower():
        ok("CI: 生成 changelog")
    else:
        fail("CI: 未生成 changelog")


def main():
    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    kernel_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(project_dir, "kernel_source")
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(project_dir, "out")

    print(f"{BLUE}{'='*50}{NC}")
    print(f"{BLUE} 一加13 自定义内核 - 静态验收测试{NC}")
    print(f"{BLUE} 规格 §4.2.3-A + §6{NC}")
    print(f"{BLUE}{'='*50}{NC}")
    print(f"项目目录: {project_dir}")
    print(f"内核源码: {kernel_dir}")
    print(f"输出目录: {out_dir}")
    print()

    test_sched_patch_diff(kernel_dir)
    test_config(out_dir)
    test_image_symbols(out_dir)
    test_ak3_integrity(project_dir)
    test_default_policies(project_dir)
    test_build_scripts(project_dir)
    test_ci_workflow(project_dir)

    print(f"\n{BLUE}{'='*50}{NC}")
    print(f"{BLUE} 测试汇总{NC}")
    print(f"{BLUE}{'='*50}{NC}")
    print(f" {GREEN}PASS{NC}: {PASS_COUNT}")
    print(f" {RED}FAIL{NC}: {FAIL_COUNT}")
    print(f" {YELLOW}WARN{NC}: {WARN_COUNT}")
    print(f" 总计: {PASS_COUNT + FAIL_COUNT + WARN_COUNT}")
    print(f"{BLUE}{'='*50}{NC}")

    if FAIL_COUNT > 0:
        print(f"\n{RED}存在 FAIL 项, 请检查上方详情{NC}")
        sys.exit(1)
    print(f"\n{GREEN}所有测试通过!{NC}")
    sys.exit(0)


if __name__ == "__main__":
    main()
