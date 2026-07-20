#!/usr/bin/env python3
"""
单元测试 - AK3 刷写策略逻辑验证
验证 anykernel.sh 中的默认策略与规格 §3 一致

用法: python3 tests/test_policies.py
"""

import os
import sys
import re
import unittest

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_file(path):
    with open(path, 'r', errors='ignore') as f:
        return f.read()


class TestDefaultPolicies(unittest.TestCase):
    """测试默认策略 (规格 §3)"""

    def setUp(self):
        self.ak3 = read_file(os.path.join(PROJECT_DIR, "anykernel", "anykernel.sh"))
        self.config = read_file(os.path.join(PROJECT_DIR, "configs", "base_defconfig_fragment"))
        self.build = read_file(os.path.join(PROJECT_DIR, "build.sh"))

    def test_default_scheduler_wait(self):
        """默认 CPU 调度 = wait"""
        self.assertIn('SCHED_CHOICE="wait"', self.ak3)
        self.assertIn("wait", self.ak3)

    def test_default_tcp_bbr3(self):
        """默认 TCP 拥塞控制 = bbr3"""
        self.assertIn('TCP_CHOICE="bbr3"', self.ak3)
        self.assertIn("bbr3", self.config)

    def test_default_qdisc_fq(self):
        """默认 qdisc = fq"""
        self.assertIn('QDISC_CHOICE="fq"', self.ak3)
        self.assertIn("CONFIG_NET_SCH_FQ=y", self.config)

    def test_default_zram_lz4(self):
        """默认 ZRAM 压缩 = lz4"""
        self.assertIn('ZRAM_CHOICE="lz4"', self.ak3)
        self.assertIn("CONFIG_ZRAM=y", self.config)

    def test_bbg_default_on(self):
        """BBG 默认开启"""
        self.assertIn('BBG_CHOICE="on"', self.ak3)

    def test_kpm_default_no(self):
        """KPM 默认不应用"""
        self.assertIn('KPM_CHOICE="no"', self.ak3)

    def test_backup_default_yes(self):
        """备份默认为是"""
        self.assertIn('BACKUP_CHOICE="yes"', self.ak3)


class TestKallsyms(unittest.TestCase):
    """测试 KALLSYMS 配置 (规格 §4.1)"""

    def test_kallsyms_enabled(self):
        config = read_file(os.path.join(PROJECT_DIR, "configs", "base_defconfig_fragment"))
        self.assertIn("CONFIG_KALLSYMS=y", config)
        self.assertIn("CONFIG_KALLSYMS_ALL=y", config)


class TestAK3Menu(unittest.TestCase):
    """测试 AK3 交互菜单 (规格 §7.1)"""

    def setUp(self):
        self.ak3 = read_file(os.path.join(PROJECT_DIR, "anykernel", "anykernel.sh"))

    def test_slot_device(self):
        self.assertIn("is_slot_device=1", self.ak3)

    def test_init_boot_path(self):
        self.assertIn("init_boot", self.ak3)
        self.assertIn("split_boot", self.ak3)
        self.assertIn("flash_boot", self.ak3)

    def test_seven_questions(self):
        for i in range(1, 8):
            self.assertIn(f"【{i}/7】", self.ak3, f"缺少交互菜单第 {i} 题")

    def test_volume_key_meaning_fixed(self):
        """音量键含义全程固定 (规格 §7.1.1)"""
        self.assertIn("音量+", self.ak3)
        self.assertIn("音量-", self.ak3)
        self.assertIn("第一项", self.ak3)
        self.assertIn("第二项", self.ak3)

    def test_timeout_default(self):
        """超时使用默认 (规格 §7.1.1)"""
        self.assertIn("超时", self.ak3)

    def test_summary_output(self):
        """结束汇总 (规格 §7.1.2)"""
        self.assertIn("调度=", self.ak3)
        self.assertIn("TCP=", self.ak3)
        self.assertIn("qdisc=", self.ak3)
        self.assertIn("ZRAM=", self.ak3)
        self.assertIn("BBG=", self.ak3)
        self.assertIn("KPM=", self.ak3)
        self.assertIn("备份=", self.ak3)

    def test_choices_logged(self):
        """选择写入 ak3-choices.log"""
        self.assertIn("ak3-choices.log", self.ak3)


class TestNetworkStack(unittest.TestCase):
    """测试网络栈配置 (规格 §4.4)"""

    def setUp(self):
        self.config = read_file(os.path.join(PROJECT_DIR, "configs", "base_defconfig_fragment"))

    def test_bbr(self):
        self.assertIn("CONFIG_TCP_CONG_BBR=y", self.config)

    def test_fq(self):
        self.assertIn("CONFIG_NET_SCH_FQ=y", self.config)

    def test_cake(self):
        self.assertIn("CONFIG_NET_SCH_CAKE=y", self.config)

    def test_fq_codel(self):
        self.assertIn("CONFIG_NET_SCH_FQ_CODEL=y", self.config)

    def test_ip_set(self):
        self.assertIn("CONFIG_IP_SET=y", self.config)

    def test_wireguard(self):
        self.assertIn("CONFIG_WIREGUARD=y", self.config)

    def test_tproxy(self):
        self.assertIn("CONFIG_NF_TPROXY=y", self.config)


class TestContainers(unittest.TestCase):
    """测试容器/兼容配置 (规格 §4.7)"""

    def setUp(self):
        self.config = read_file(os.path.join(PROJECT_DIR, "configs", "base_defconfig_fragment"))

    def test_pid_ns(self):
        self.assertIn("CONFIG_PID_NS=y", self.config)

    def test_ipc_ns(self):
        self.assertIn("CONFIG_IPC_NS=y", self.config)

    def test_user_ns(self):
        self.assertIn("CONFIG_USER_NS=y", self.config)

    def test_sysvipc(self):
        self.assertIn("CONFIG_SYSVIPC=y", self.config)

    def test_posix_mqueue(self):
        self.assertIn("CONFIG_POSIX_MQUEUE=y", self.config)

    def test_ntsync(self):
        self.assertIn("CONFIG_NTSYNC=y", self.config)


class TestZram(unittest.TestCase):
    """测试 ZRAM 配置 (规格 §4.3)"""

    def setUp(self):
        self.config = read_file(os.path.join(PROJECT_DIR, "configs", "base_defconfig_fragment"))

    def test_zram_enabled(self):
        self.assertIn("CONFIG_ZRAM=y", self.config)

    def test_multi_comp(self):
        self.assertIn("CONFIG_ZRAM_MULTI_COMP=y", self.config)

    def test_writeback(self):
        self.assertIn("CONFIG_ZRAM_WRITEBACK=y", self.config)


class TestExclusions(unittest.TestCase):
    """测试明确不进默认包的项目 (规格 §4.9)"""

    def test_no_dolby_in_config(self):
        """杜比不进内核 Image"""
        config = read_file(os.path.join(PROJECT_DIR, "configs", "base_defconfig_fragment"))
        self.assertNotIn("CONFIG_DOLBY", config)

    def test_changelog_documents_exclusions(self):
        """changelog 文档应说明不包含项"""
        build = read_file(os.path.join(PROJECT_DIR, "build.sh"))
        self.assertIn("杜比", build)
        self.assertIn("不包含", build)


class TestBuildScript(unittest.TestCase):
    """测试构建脚本"""

    def test_error_handling(self):
        build = read_file(os.path.join(PROJECT_DIR, "build.sh"))
        self.assertIn("set -euo pipefail", build)

    def test_lto_thin(self):
        build = read_file(os.path.join(PROJECT_DIR, "build.sh"))
        self.assertIn("LTO", build)

    def test_changelog_generation(self):
        build = read_file(os.path.join(PROJECT_DIR, "build.sh"))
        self.assertIn("generate_changelog", build)

    def test_sha256_generation(self):
        build = read_file(os.path.join(PROJECT_DIR, "build.sh"))
        self.assertIn("sha256sum", build)


class TestCIWorkflow(unittest.TestCase):
    """测试 CI 工作流 (规格 §7.4)"""

    def setUp(self):
        self.workflow = read_file(
            os.path.join(PROJECT_DIR, ".github", "workflows", "build.yml")
        )

    def test_workflow_dispatch(self):
        self.assertIn("workflow_dispatch", self.workflow)

    def test_ak3_output(self):
        self.assertIn("zip", self.workflow.lower())

    def test_sha256(self):
        self.assertIn("sha256", self.workflow.lower())

    def test_traceability(self):
        self.assertIn("KERNEL_COMMIT", self.workflow)

    def test_changelog(self):
        self.assertIn("changelog", self.workflow.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
