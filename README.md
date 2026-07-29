# OnePlus 13（sun / SM8750）自定义内核工程

面向 **OnePlus 13 国行 PJZ110（设备代号 `sun`）/ ColorOS 16** 的内核构建、上游同步、自定义补丁、AnyKernel3 打包与验证工程。

> 当前状态：**Experimental**。完整 OnePlus OKI 官方路径曾成功构建 Linux 6.6.118 产物；自定义 common 分支当前为 Linux 6.6.126。两者尚未完成安全合并和真机运行时验收，仓库中的任何 ZIP、Image 或实验性 CI 产物都不能直接视为 Stable。

## 项目边界

本仓库是项目控制仓库，不是完整 Linux 内核源码镜像。主要负责：

- 完整 OnePlus OKI 源码同步、构建和版本锁定
- 自定义补丁、配置和策略的组织
- AnyKernel3 打包与刷写逻辑
- 静态测试、真机验收脚本和发布记录
- 官方上游、自定义 common 与完整构建基线的关系维护

## 仓库关系

| 角色 | 仓库 | 默认分支 | 说明 |
|---|---|---|---|
| 项目控制仓库 | [`Zhanfg/OnePlus13-kernel`](https://github.com/Zhanfg/OnePlus13-kernel) | `main` | 构建、补丁、AK3、测试、发布和文档 |
| 自定义 common | [`Zhanfg/android_kernel_common_oneplus_sm8750`](https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750) | `6.6-final` | common 层自定义补丁；不是完整 OKI 工程 |
| 官方 manifest | [`OnePlusOSS/kernel_manifest`](https://github.com/OnePlusOSS/kernel_manifest) | `oneplus/sm8750` | 完整工程入口，使用 `oneplus_13_b.xml` |
| 官方 common | [`OnePlusOSS/android_kernel_common_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750) | `oneplus/sm8750_b_16.0.0_oneplus_13` | Android common 内核 |
| 官方 msm-kernel | [`OnePlusOSS/android_kernel_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750) | `oneplus/sm8750_b_16.0.0_oneplus_13` | Qualcomm / OnePlus 平台代码 |
| 官方 modules / DT | [`OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750) | `oneplus/sm8750_b_16.0.0_oneplus_13` | vendor modules、设备树和工程根组件 |

## 当前官方上游

最后核对：**2026-07-29**。

| 项目 | 当前值 |
|---|---|
| 设备版本 | `PJZ110_16.0.9.401(CN01)` |
| Manifest | `OnePlusOSS/kernel_manifest:oneplus/sm8750` |
| Manifest 文件 | `oneplus_13_b.xml` |
| 官方 common 提交 | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` |
| 官方 common 版本 | Linux `6.6.118` |
| Android common tag | `android15-6.6-2026-01_r22` |
| 官方 msm-kernel 提交 | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| 官方 modules / DT 提交 | `d50b305f7da9e14715a25120a4ac7b1a4b8b97c3` |
| msm-kernel QCOM tag | `AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111` |

这些 SHA 是核对时的浮动分支 tip。正式构建仍必须保存：

```bash
repo manifest -r -o manifest-pinned.xml
```

## 两套内核基线

### 完整 OKI 官方构建基线

此前完成的完整 OnePlus OKI 构建使用官方 manifest 和 `sun perf` 目标：

```text
Kernel: Linux 6.6.118
Build: ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
Status: build/static/package evidence available
Boot: not verified
```

该基线包含 common、msm-kernel、modules/devicetree、Kleaf/Bazel、工具链和 vendor 侧依赖。

### 自定义 common 开发基线

```text
Repository: Zhanfg/android_kernel_common_oneplus_sm8750
Branch: 6.6-final
Kernel: Linux 6.6.126
```

该分支包含大量本地和社区改动，但只对应完整工程中的 `kernel_platform/common`。它不能单独代表 OnePlus 13 完整内核，也不能因为版本号更高就视为已经包含最新 OnePlus 官方设备改动。

## common 上游同步状态

官方镜像分支已经同步到最新官方 common：

```text
upstream/oneplus-sm8750-b-16.0.0-oneplus-13
e1b346b6b4f4096eb342ae3684838a942fd6f6c4
```

自定义 `6.6-final` 与官方 tip 的关系：

| 项目 | 结果 |
|---|---|
| 共同祖先 | `5a0ffb447c1dbd82e8e3af7a98c4a629f4b6d143` |
| 本地领先 | 8,947 commits |
| 本地落后 | 5 official commits |
| 同步候选 | [`android_kernel_common_oneplus_sm8750#6`](https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750/pull/6) |
| 候选状态 | Draft / conflicts / not merged |
| 冲突路径 | 80 个 |

虽然只落后 5 个官方同步提交，但这些提交覆盖约 3,830 个文件。实际非破坏性 `merge-tree` 检查发现 80 个冲突路径：

| 类别 | 数量 |
|---|---:|
| 驱动 | 29 |
| 文件系统 | 17 |
| 内核头文件与 hooks | 13 |
| ABI / KMI / AFDO | 10 |
| 架构与配置 | 8 |
| 其他 | 3 |

高风险区域包括：

- `Makefile`：本地 6.6.126 与官方 6.6.118 的版本语义
- `arch/arm64/configs/gki_defconfig`
- ABI `.stg`、OPlus symbol list、protected exports 和 AFDO
- `sched.h`、`mm.h`、`mm_types.h` 与 vendor hooks
- F2FS、EXT4
- USB、Type-C、IOMMU、电源和设备接口

完整冲突清单见 common 仓库：

```text
docs/UPSTREAM_SYNC_16.0.9.401.md
```

PR #6 在逐文件解决冲突、完整 OKI clean build、ABI/KMI 和真机验证完成前必须保持 Draft。

## 当前工程状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| 完整 OKI `repo sync` | 已完成 | 使用 `oneplus/sm8750` + `oneplus_13_b.xml` |
| 官方构建脚本 | 已完成 | 曾生成 Linux 6.6.118 产物 |
| 静态检查 | 已完成 | Android Clang 与 Image 已核对 |
| AK3 打包 | 已完成 | 仅为测试包 |
| 官方核心仓库 SHA 核对 | 已完成 | common、msm-kernel、modules/DT 已记录 |
| 官方 common 镜像 | 已完成 | 跟踪分支与官方 tip 一致 |
| common 同步候选 | 已建立 | PR #6，存在 80 个冲突 |
| common 冲突解决 | 待完成 | 禁止批量 ours/theirs |
| 16.0.9.401 固定 manifest clean build | 待完成 | 合并前必须完成 |
| 真机启动 | 待验证 | 未达到 Boot Verified |
| 关键硬件与自定义功能 | 待验证 | 需在稳定启动后逐项测试 |

## 正确构建路径

### 1. 同步完整 OnePlus OKI 工程

```bash
mkdir -p op13-oki
cd op13-oki

repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)"
repo manifest -r -o manifest-pinned.xml
```

### 2. 使用官方 OnePlus 构建入口

```bash
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

仓库中的 [`scripts/wsl_build_oki.sh`](scripts/wsl_build_oki.sh) 用于辅助 WSL / Linux 环境下的同步、构建、验证与打包。以脚本实际参数和 `--help` 输出为准。

### 3. 测试自定义 common

需要在固定 manifest 的完整 OKI 工作区中，将 `kernel_platform/common` 指向经过审核的自定义提交，再执行 clean build。禁止只编译 common 后直接作为正式刷写包。

### 4. 保存构建证据

每次构建至少记录：

- 固定 revision 的 `manifest-pinned.xml` 及 SHA256
- common、msm-kernel、modules/devicetree SHA
- 官方与自定义 common 的版本和提交
- Android Clang、Bazel、Kleaf 版本
- 构建命令与目标 `sun perf`
- Image、vendor_boot、vendor modules、vermagic 和 SHA256
- 应用的补丁与冲突解决提交范围
- 设备、系统、固件、验证等级和回退包

## common 同步处理顺序

1. `Makefile`、版本号和 Android common tag
2. ABI/KMI、OPlus symbol list、AFDO
3. `gki_defconfig`、Kleaf/Bazel 和工具链
4. common 与 msm-kernel / vendor modules 接口
5. 调度、内存和 vendor hooks
6. F2FS、EXT4、ZRAM 和文件系统 hook
7. USB、Type-C、IOMMU、电源和设备驱动
8. 网络与其他通用驱动
9. 完整 OKI clean build
10. 真机启动和运行时回归

每组冲突应形成独立提交，便于构建、审查和回退。

## 实验性 GitHub Actions

`.github/workflows/build.yml` 是**单仓库实验性构建**。它只克隆 `android_kernel_oneplus_sm8750`，并通过空 Kconfig / Makefile stub 绕过缺失组件。

该工作流：

- 不等价于完整 OnePlus OKI 构建
- 不保证 vendor modules、设备树、ABI 和当前系统匹配
- 只能用于早期语法、配置或构建实验
- 产物不得直接标记为可刷写稳定版

完整构建必须以 manifest + 官方构建脚本为主。

## 旧版脚本

以下内容来自早期“单仓库 + 逐项补丁”设计：

- `build.sh`
- `scripts/patch.sh`
- `configs/base_defconfig_fragment`

这些文件可用于研究补丁来源和配置，但除非完成 OKI 重构，不作为正式发布入口。

## 计划集成的功能

下表表示项目目标或已有相关实现，不代表已经通过真机验证。

| 类别 | 目标 |
|---|---|
| Root / 隐藏 | ReSukiSU、SuSFS、KPM 兼容路径 |
| 调度 | 默认 wait；HMBIRD / 风驰、SCX 可选 |
| I/O / ZRAM | ADIOS、LZ4/LZ4KD/ZSTD、多压缩、writeback |
| 网络 | BBRv3、fq、fq_codel、cake、IP_SET、TPROXY、WireGuard |
| 通信安全 | Baseband Guard；不修改基带固件 |
| 省电 | Re:Kernel、Wakelock Blocker、休眠优化 |
| 兼容 | Droidspaces、NTSYNC、OverlayFS、TMPFS xattr/ACL |
| 编译 | ThinLTO、O2、工具链支持时的 Oryon 优化 |

明确不包含：

- 杜比解码器、杜比音效 blob 或受许可限制的用户态文件
- 基带固件修改
- 未验证的激进充电、温控、亮度或电压修改
- 未经来源和许可证核对的闭源二进制

## 刷写与回滚

完成 Boot Verified 前，只允许在具备完整救砖条件的测试设备上进行。

刷写前至少准备：

1. 与当前系统一致的原版 `boot.img`、`vendor_boot.img` 和必要回退资料。
2. 可用的 Fastboot / Fastbootd、Recovery 或其他恢复路径。
3. 当前重要数据备份。
4. 与构建相同的系统、固件、vendor modules 和 ABI 基线。
5. 构建产物 SHA256 与来源记录。

不要把裸 `Image` 当作完整 `boot.img` 直接写入 boot 分区。Image、ramdisk、DTB/DTBO、vendor modules 与 vendor_boot 必须来自同一构建基线。

## 合并与发布检查

- [ ] 80 个 common 冲突逐文件解决并记录理由
- [ ] 固定完整 `manifest-pinned.xml`
- [ ] common、msm-kernel、modules / DT revision 匹配
- [ ] ABI/KMI、OPlus symbol list、AFDO 通过
- [ ] `oplus_build_kernel.sh sun perf` clean build 成功
- [ ] Image、vendor_boot、vendor modules 与 vermagic 匹配
- [ ] AK3 静态检查和回退包完成
- [ ] OnePlus 13 可重复启动、重启和回退
- [ ] 蜂窝、Wi-Fi、蓝牙、相机、指纹正常
- [ ] 充电、电池状态、温控、灭屏和深度休眠正常
- [ ] Root、SuSFS、KPM、wait/HMBIRD/SCX、网络栈通过验证

## 验证等级

| 等级 | 定义 |
|---|---|
| Experimental | 仅完成编译、静态检查或打包 |
| Boot Verified | 指定 PJZ110 / ColorOS 可以重复启动并可回退 |
| Runtime Verified | 关键硬件和内核功能完成测试 |
| Stable | 完成重复刷写、重启、待机和基础回归 |

构建成功不能自动升级为 Boot Verified 或 Stable。

## 目录说明

```text
OnePlus13-kernel/
├── .github/workflows/       # 自动化；build 仍属实验性
├── anykernel/               # AK3 模板和刷写脚本
├── configs/                 # 早期配置碎片
├── docs/                    # 工程状态、上游和同步说明
├── releases/                # 脱敏基线、构建和回退记录
├── scripts/                 # OKI/WSL 构建、验证和打包脚本
├── tests/                   # 静态、策略和真机测试
├── build.sh                 # 早期单仓库构建入口
└── README.md
```

## 安全与隐私

- 不提交 Token、Cookie、密钥、账号、设备序列号或未脱敏日志。
- 不提交本机绝对路径、磁盘布局、用户名或个人目录。
- 发现真实密钥时立即吊销；普通删除不能清除 Git 历史中的秘密。
- 内核、启动、基带接口、充电、温控和文件系统改动必须单独说明风险与回退方式。
- 不使用 `ours`、整树覆盖、批量 theirs 或删除冲突代码伪造同步成功。

## 文档

- [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md)：当前工程状态和优先级
- [`docs/UPSTREAM.md`](docs/UPSTREAM.md)：官方上游、真实差异和同步流程
- [`releases/BASELINE_CURRENT.txt`](releases/BASELINE_CURRENT.txt)：当前脱敏基线
- [common 同步 PR #6](https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750/pull/6)：16.0.9.401 Draft 候选

## 许可证与致谢

Linux 内核源码遵循 GPL-2.0。各第三方补丁、脚本和工具遵循其各自许可证。

感谢 OnePlusOSS、Qualcomm / CodeLinaro、Android Common Kernel、ReSukiSU、SuSFS、WildKernels、SukiSU、Baseband Guard、Re:Kernel、AnyKernel3 及相关社区维护者。
