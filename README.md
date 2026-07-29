# OnePlus 13（sun / SM8750）自定义内核工程

面向 **OnePlus 13 国行 PJZ110 / ColorOS 16** 的完整 OKI 构建、官方上游同步、自定义 common 集成、AnyKernel3 打包与真机验收工程。

> 当前状态：**Experimental**。完整 OnePlus OKI 官方路径曾成功构建 Linux 6.6.118 产物；自定义 common 当前为 Linux 6.6.126。官方 16.0.9.401 更新尚未完成全部冲突解决、完整 OKI 重建和真机验证，现有产物不能直接视为 Stable。

## 仓库与职责

| 角色 | 仓库 / 分支 | 说明 |
|---|---|---|
| 项目控制 | `Zhanfg/OnePlus13-kernel:main` | 构建、AK3、测试、发布和文档 |
| 自定义 common | `Zhanfg/android_kernel_common_oneplus_sm8750:6.6-final` | common 自定义补丁和上游移植 |
| 官方 manifest | `OnePlusOSS/kernel_manifest:oneplus/sm8750` | 完整 OKI 入口，使用 `oneplus_13_b.xml` |
| 官方 common | `OnePlusOSS/android_kernel_common_oneplus_sm8750` | Android common 内核 |
| 官方 msm-kernel | `OnePlusOSS/android_kernel_oneplus_sm8750` | Qualcomm / OnePlus 平台代码 |
| 官方 modules / DT | `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750` | vendor modules 与设备树 |

本仓库是项目控制仓库，不是完整源码镜像。只克隆 common 或 msm-kernel 不能代表完整 OnePlus 13 工程。

## 当前官方基线

最后核对：**2026-07-29**。

| 项目 | 当前值 |
|---|---|
| 设备版本 | `PJZ110_16.0.9.401(CN01)` |
| Manifest | `oneplus/sm8750` + `oneplus_13_b.xml` |
| 官方 common SHA | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` |
| 官方 common | Linux `6.6.118` / `android15-6.6-2026-01_r22` |
| 官方 msm-kernel SHA | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| 官方 modules / DT SHA | `d50b305f7da9e14715a25120a4ac7b1a4b8b97c3` |
| QCOM tag | `AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111` |

正式构建必须保存固定 manifest：

```bash
repo manifest -r -o manifest-pinned.xml
sha256sum manifest-pinned.xml
```

## 两套内核基线

### 完整官方 OKI

```text
Kernel: Linux 6.6.118
Build: ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
State: build/static/package evidence available
Boot: not verified
```

该基线包含 common、msm-kernel、modules/devicetree、Kleaf/Bazel、工具链和 vendor 侧依赖。

### 自定义 common

```text
Repository: Zhanfg/android_kernel_common_oneplus_sm8750
Branch: 6.6-final
Kernel: Linux 6.6.126
```

自定义 common 只对应 `kernel_platform/common`。版本号更高不等于已经包含最新 OnePlus 设备、ABI 和 vendor 改动，也不能单独作为正式刷写包。

本轮工作是把官方 OnePlus/OPlus、Android common 和 ABI/KMI 更新移植到较新的自定义 common 基线上，不是用官方 6.6.118 整树覆盖本地 6.6.126。

## 官方 common 同步

官方镜像分支：

```text
upstream/oneplus-sm8750-b-16.0.0-oneplus-13
e1b346b6b4f4096eb342ae3684838a942fd6f6c4
```

固定同步候选：

```text
PR: Zhanfg/android_kernel_common_oneplus_sm8750#6
branch: sync/official-16.0.9.401-e1b346b6b
state: Draft / conflicts / not merged
```

| 项目 | 结果 |
|---|---|
| 共同祖先 | `5a0ffb447c1dbd82e8e3af7a98c4a629f4b6d143` |
| 本地领先 | 8,947 commits |
| 本地落后 | 5 official commits |
| 官方候选范围 | 约 3,830 个文件 |
| 真实 Git merge 冲突 | **116 个路径** |

早期记录的 80 个冲突来自截断的 merge-tree 报告。真实 `git merge --no-commit --no-ff` 并检查 unmerged index 后，权威结果为 **116**。

### 冲突分布

| 类别 | 数量 |
|---|---:|
| 驱动 | 29 |
| 文件系统 | 17 |
| 内核核心 | 15 |
| 头文件与 hooks | 13 |
| 网络 | 12 |
| ABI/KMI/AFDO | 10 |
| 架构与配置 | 8 |
| 音频 | 6 |
| 其他 | 6 |
| **合计** | **116** |

完整路径见 common 仓库的 `docs/UPSTREAM_SYNC_16.0.9.401.md`。

## 第一轮解决结果

common 仓库已经合并第一轮可审计规则：

```text
sync/resolutions/16.0.9.401/pass1-ours.txt
scripts/resolve_merge_markers.py
.github/workflows/test-upstream-resolution-pass.yml
```

规则不是整文件选择本地版本，而是：

1. 执行真实官方 merge。
2. 保留 Git 自动合入的官方无冲突 hunk。
3. 仅替换 31 个已核验文件中的冲突块。
4. 检查 marker 与 unmerged index。
5. 强制验证冲突数量。

实际结果：

```text
Initial conflicts: 116
Resolved paths: 31
Remaining conflicts: 85
Resolution checks: passed
Source integration: intentionally blocked
```

工作流最终显示失败是预期安全门：仍有 85 个冲突时，禁止把源码候选视为可合并。

## 调度架构阻塞

官方 16.0.9.401：

```text
CONFIG_SLIM_SCHED=y
CONFIG_SCHED_CLASS_EXT=y
SCHED_EXT=7
```

本地：

```text
CONFIG_HMBIRD_SCHED=y
SCHED_HMBIRD=7
```

HMBIRD 与官方 SCX 使用相同调度策略编号 `7`，并共同修改 fork、tick、pick-next、setscheduler、cgroup 和 idle 接口。`kernel/sched/core.c` 单文件有 28 个冲突块。

因此当前不能声明 HMBIRD 与官方 SCX 已完成共存。现阶段更稳妥的迁移方向是：

- 保留默认 wait / fair 路径；
- 保留 HMBIRD / 风驰作为当前自定义路径；
- 先移植官方非 SCX 修复；
- SCX 恢复与策略编号重构另开独立架构任务；
- SLIM_SCHED 单独核对依赖和运行时行为。

## 当前状态

| 阶段 | 状态 |
|---|---|
| 完整官方 OKI 同步 | 已完成 |
| 官方 6.6.118 构建 | 已完成 |
| 官方三个核心仓库 SHA 核对 | 已完成 |
| 官方 common 镜像 | 已完成 |
| 固定同步 PR #6 | 已建立，保持 Draft |
| 四方冲突文件导出 | 已完成 |
| 第一轮 31 路径规则 | 已完成并验证 |
| 剩余冲突 | 85 个，处理中 |
| 固定 manifest clean build | 待完成 |
| ABI/KMI / AFDO | 待完成 |
| 真机启动与运行时验证 | 待完成 |

## 正确构建路径

```bash
mkdir -p op13-oki
cd op13-oki

repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)"
repo manifest -r -o manifest-pinned.xml
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

测试自定义 common 时，应在固定 manifest 的完整 OKI 工作区中，将 `kernel_platform/common` 指向经过审核的提交，再执行 clean build。

每次候选构建至少记录：

- 固定 manifest 与 SHA256
- common、msm-kernel、modules/devicetree SHA
- 冲突解决 Pass 和提交范围
- Android Clang、Bazel、Kleaf 版本
- Image、vendor_boot、vendor modules、vermagic 和 SHA256
- 设备、系统、固件、验证等级和回退包

## 后续处理顺序

1. HMBIRD / SCX / SLIM 架构和策略编号
2. ABI/KMI、OPlus symbols、protected exports、AFDO
3. `gki_defconfig`、Kleaf/Bazel 和工具链
4. task/fork/tick、内存和 vendor hooks
5. common 与 msm-kernel / vendor modules 接口
6. F2FS、EXT4、ZRAM 和文件系统 hooks
7. USB、Type-C、IOMMU、电源和设备驱动
8. 网络与音频
9. 完整 OKI clean build
10. ABI/KMI 和真机回归

每一轮必须有明确路径清单、三方证据、可重复工作流和解决前后冲突计数。

## 实验性 CI

`.github/workflows/build.yml` 是单仓库实验性构建，只能用于早期语法、配置或构建检查。它不等价于完整 OnePlus OKI 构建，不保证 vendor modules、设备树、ABI 和系统匹配，产物不得直接标记为稳定刷写包。

## 目标功能

| 类别 | 目标 |
|---|---|
| Root / 隐藏 | ReSukiSU、SuSFS、KPM 兼容路径 |
| 调度 | 默认 wait；HMBIRD / 风驰为当前自定义路径；SCX 待独立处理 |
| I/O / ZRAM | ADIOS、LZ4/LZ4KD/ZSTD、多压缩、writeback |
| 网络 | BBRv3、fq、fq_codel、cake、IP_SET、TPROXY、WireGuard |
| 通信安全 | Baseband Guard；不修改基带固件 |
| 省电 | Re:Kernel、Wakelock Blocker、休眠优化 |
| 兼容 | Droidspaces、NTSYNC、OverlayFS、TMPFS xattr/ACL |
| 编译 | ThinLTO、O2、工具链支持时的 Oryon 优化 |

明确不包含杜比用户态文件、基带固件修改、未经验证的激进电源策略或来源不明的闭源组件。

## 刷写与回滚

完成 Boot Verified 前，只允许在具备完整救砖条件的测试设备上进行。至少准备：

1. 与当前系统一致的原版 `boot.img`、`vendor_boot.img` 和回退资料。
2. 可用的 Fastboot / Fastbootd、Recovery 或其他恢复路径。
3. 重要数据备份。
4. 与构建相同的系统、固件、vendor modules 和 ABI 基线。
5. 构建产物 SHA256 与来源记录。

不要把裸 `Image` 当作完整 `boot.img` 直接写入 boot 分区。

## 合并与发布检查

- [ ] 剩余 85 个冲突逐文件解决并记录理由
- [ ] HMBIRD / SCX / SLIM 架构和策略编号解决
- [ ] 固定完整 manifest
- [ ] common、msm-kernel、modules / DT revision 匹配
- [ ] ABI/KMI、OPlus symbols、AFDO 通过
- [ ] 完整 `sun perf` clean build 成功
- [ ] Image、vendor_boot、vendor modules 与 vermagic 匹配
- [ ] OnePlus 13 可重复启动、重启和回退
- [ ] 蜂窝、Wi-Fi、蓝牙、相机、指纹、充电、温控和休眠正常
- [ ] Root、SuSFS、KPM、wait/HMBIRD 和网络栈完成验证
- [ ] SCX 若恢复，单独完成启用与回退验证

## 验证等级

| 等级 | 定义 |
|---|---|
| Experimental | 仅完成编译、静态检查或打包 |
| Boot Verified | 指定 PJZ110 / ColorOS 可以重复启动并可回退 |
| Runtime Verified | 关键硬件和内核功能完成测试 |
| Stable | 完成重复刷写、重启、待机和基础回归 |

构建成功不能自动升级为 Boot Verified 或 Stable。

## 文档

- [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md)：工程状态和优先级
- [`docs/UPSTREAM.md`](docs/UPSTREAM.md)：官方上游和同步流程
- [`releases/BASELINE_CURRENT.txt`](releases/BASELINE_CURRENT.txt)：当前脱敏基线
- [common 同步 PR #6](https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750/pull/6)
- [common 第一轮规则 PR #11](https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750/pull/11)

## 许可证

Linux 内核源码遵循 GPL-2.0。第三方补丁、脚本和工具遵循各自许可证。
