# OnePlus 13（sun / SM8750）自定义内核工程

面向 **OnePlus 13 国行 PJZ110（设备代号 `sun`）/ ColorOS 16** 的内核构建、补丁集成、AnyKernel3 打包与验证工程。

> 当前状态：**Experimental**。完整 OnePlus OKI 源码已经能够完成官方路径构建并生成 6.6.118 内核产物，但尚未完成稳定的真机启动与运行时验收。仓库中的任何 ZIP、Image 或实验性 CI 产物都不能直接视为 Stable。

## 项目边界

本仓库不是完整 Linux 内核源码镜像，而是项目控制仓库，负责：

- 完整 OnePlus OKI 源码同步说明与构建入口
- 自定义补丁、配置和策略的组织
- AnyKernel3 打包与刷写逻辑
- 静态测试、真机验收脚本和发布记录
- 官方上游版本、提交 SHA 与本地基线追踪

相关仓库：

| 角色 | 仓库 | 默认分支 | 说明 |
|---|---|---|---|
| 项目控制仓库 | [`Zhanfg/OnePlus13-kernel`](https://github.com/Zhanfg/OnePlus13-kernel) | `main` | 构建、补丁、AK3、测试和文档 |
| 自定义 common 源码镜像 | [`Zhanfg/android_kernel_common_oneplus_sm8750`](https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750) | `6.6-final` | 自定义 common 内核补丁承载；不等于完整 OKI 工程 |
| 官方 OKI manifest | [`OnePlusOSS/kernel_manifest`](https://github.com/OnePlusOSS/kernel_manifest) | `oneplus/sm8750` | 完整工程清单，使用 `oneplus_13_b.xml` |
| 官方 common | [`OnePlusOSS/android_kernel_common_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750) | `oneplus/sm8750_b_16.0.0_oneplus_13` | Android 15 / Linux 6.6 common 树 |
| 官方 msm-kernel | [`OnePlusOSS/android_kernel_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750) | `oneplus/sm8750_b_16.0.0_oneplus_13` | OnePlus / Qualcomm 平台内核树 |
| 官方模块与设备树 | [`OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750) | `oneplus/sm8750_b_16.0.0_oneplus_13` | vendor modules、设备树及完整 OKI 所需组件 |

## 当前官方上游

最后核对：**2026-07-29**。

| 项目 | 当前值 |
|---|---|
| 设备版本 | `PJZ110_16.0.9.401(CN01)` |
| Manifest 分支 | `oneplus/sm8750` |
| Manifest 文件 | `oneplus_13_b.xml` |
| common 分支 | `oneplus/sm8750_b_16.0.0_oneplus_13` |
| common 提交 | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` |
| msm-kernel 分支 | `oneplus/sm8750_b_16.0.0_oneplus_13` |
| msm-kernel 提交 | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| 当前内核版本 | Linux `6.6.118` / Android 15 GKI 基线 |

更完整的同步规则、链接与检查方法见 [`docs/UPSTREAM.md`](docs/UPSTREAM.md)。

## 当前真实状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| 完整 OKI `repo sync` | 已完成 | 使用 `oneplus/sm8750` 和 `oneplus_13_b.xml` |
| 官方构建脚本 | 已完成 | `oplus_build_kernel.sh sun perf` 可生成产物 |
| 静态检查 | 已完成 | 已确认 Android Clang 与 6.6.118 Image |
| AK3 打包 | 已完成 | 已生成测试包，不能视为稳定发布 |
| 真机启动 | 待验证 | 未完成前不得标记 Boot Verified |
| 蜂窝、Wi-Fi、相机、指纹、充电、休眠 | 待验证 | 需要同一系统与 vendor 基线 |
| Root、SuSFS、调度、网络等自定义功能 | 待验证 | 必须在稳定启动后逐项启用和回归 |

## 正确构建路径

### 1. 同步完整 OnePlus OKI 工程

不要只克隆单个 `android_kernel_oneplus_sm8750` 仓库。完整构建至少需要 common、msm-kernel、modules/devicetree、构建工具与 manifest 中固定的依赖。

```bash
mkdir -p op13-oki
cd op13-oki

repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)"
```

同步完成后保存可复现 manifest：

```bash
repo manifest -r -o manifest-pinned.xml
```

`manifest-pinned.xml` 应随构建记录保存，但提交前需要检查其中是否包含本机路径、账号或其他隐私信息。

### 2. 使用官方 OnePlus 构建入口

```bash
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

仓库中的 [`scripts/wsl_build_oki.sh`](scripts/wsl_build_oki.sh) 用于辅助 WSL / Linux 环境下的同步、构建、验证与打包。以脚本实际参数和 `--help` 输出为准。

### 3. 保存构建证据

每次可发布构建至少记录：

- Manifest 仓库、分支和固定 revision 文件
- common、msm-kernel、modules/devicetree 的提交 SHA
- Android Clang / Bazel / Kleaf 版本
- 构建命令与目标 `sun perf`
- Image、vendor_boot 相关产物及 SHA256
- 应用的自定义补丁清单
- 设备、系统版本、固件版本和验证等级

## 实验性 GitHub Actions

`.github/workflows/build.yml` 当前是**单仓库实验性构建**：它只克隆 `android_kernel_oneplus_sm8750`，并通过创建空 Kconfig / Makefile stub 绕过缺失组件。

该工作流：

- 不等价于完整 OnePlus OKI 构建
- 不保证 vendor modules、设备树、ABI 与设备当前系统匹配
- 只能用于语法、配置或早期实验
- 产物不得直接标记为可刷写稳定版

完整构建应以 manifest + 官方构建脚本为主。CI 在完成完整 manifest 同步、固定 revision、禁止 stub 绕过和真机验证前，不作为推荐发布路径。

## 旧版脚本

以下内容来自早期“单仓库 + 逐项补丁”设计：

- `build.sh`
- `scripts/patch.sh`
- `configs/base_defconfig_fragment`

这些文件仍可用于研究补丁来源和配置，但与完整 OKI 路径存在结构差异。除非后续重构完成，否则不要将其作为正式发布入口。

## 计划集成的功能

下表表示项目目标或源码中已有相关实现，不代表已完成真机验证。

| 类别 | 目标 |
|---|---|
| Root / 隐藏 | ReSukiSU、SuSFS、KPM 兼容路径 |
| 调度 | 默认 wait；HMBIRD / 风驰、SCX 作为可选路径 |
| I/O / ZRAM | ADIOS、LZ4/LZ4KD/ZSTD、多压缩与 writeback |
| 网络 | BBRv3、fq、fq_codel、cake、IP_SET、TPROXY、WireGuard |
| 通信安全 | Baseband Guard；不修改基带固件 |
| 省电 | Re:Kernel、Wakelock Blocker 与小型休眠优化 |
| 兼容 | Droidspaces、NTSYNC、OverlayFS、TMPFS xattr/ACL |
| 编译 | ThinLTO、O2、工具链支持时的 Oryon 优化 |

明确不包含：

- 杜比解码器、杜比音效 blob 或其他受许可限制的用户态文件
- 基带固件修改
- 未验证的激进充电、温控、亮度或电压修改
- 未经来源与许可证核对的闭源二进制

## 刷写与回滚

在完成 Boot Verified 之前，只允许在具备完整救砖条件的测试设备上进行。

刷写前至少准备：

1. 与当前系统版本一致的原版 `boot.img`、`vendor_boot.img` 和必要回退资料。
2. 可用的 Fastboot / Fastbootd、Recovery 或其他恢复路径。
3. 当前数据备份。
4. 与构建相同的系统、固件和 vendor modules 基线。
5. 构建产物 SHA256 与来源记录。

不要把裸 `Image` 当作完整 `boot.img` 直接写入 boot 分区。Image、ramdisk、DTB/DTBO、vendor modules 与 vendor_boot 必须保持同一构建和 ABI 基线。

## 验证等级

| 等级 | 定义 |
|---|---|
| Experimental | 仅完成编译、静态检查或打包 |
| Boot Verified | 指定 PJZ110 / ColorOS 版本可以重复启动，并确认可回退 |
| Runtime Verified | 蜂窝、Wi-Fi、蓝牙、相机、指纹、充电、休眠、Root 等完成测试 |
| Stable | 在 Runtime Verified 基础上完成重复刷写、重启、待机和基础回归 |

构建成功不能自动升级为 Boot Verified 或 Stable。

## 目录说明

```text
OnePlus13-kernel/
├── .github/workflows/       # 自动化；当前构建工作流仍属实验性
├── anykernel/               # AK3 模板与刷写脚本
├── configs/                 # 早期配置碎片
├── docs/                    # 对外工程文档、上游与状态说明
├── releases/                # 基线、构建和回退记录；禁止保存本机隐私
├── scripts/                 # OKI/WSL 构建、验证、打包及旧版补丁脚本
├── tests/                   # 静态、策略与真机验收脚本
├── build.sh                 # 早期单仓库构建入口
└── README.md
```

## 上游同步原则

1. 先同步官方 manifest，再同步 manifest 指向的全部仓库。
2. 每次同步保存固定 revision 的 manifest，不以浮动分支名称代替版本记录。
3. 自定义 common 镜像只承载明确拆分的本地补丁，不替代完整 OKI 工程。
4. 官方更新先进入独立 `sync/upstream-*` 分支或 PR，不直接覆盖自定义主分支。
5. 冲突按功能组处理：设备/ABI → 构建 → Root/SuSFS → 调度 → 网络 → 省电与兼容。
6. 不使用 `ours`、空 stub 或删除冲突代码来伪造同步成功。
7. 每次上游更新后重新执行完整构建和真机验收。

## 安全与隐私

- 不提交 Token、Cookie、密钥、账号、设备序列号或未脱敏日志。
- 不提交本机绝对路径、磁盘布局、用户名或个人目录。
- 公开仓库中的测试记录必须使用通用占位路径。
- 发现真实密钥时应立即吊销；普通删除文件不能清除 Git 历史中的秘密。
- 内核、启动、基带接口、充电、温控和文件系统改动必须单独说明风险与回退方式。

## 文档

- [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md)：当前工程状态与优先级
- [`docs/UPSTREAM.md`](docs/UPSTREAM.md)：官方上游、版本锁定和同步流程
- [`releases/BASELINE_CURRENT.txt`](releases/BASELINE_CURRENT.txt)：当前脱敏基线记录

## 许可证与致谢

Linux 内核源码遵循 GPL-2.0。各第三方补丁、脚本和工具遵循其各自许可证。

感谢 OnePlusOSS、Qualcomm / CodeLinaro、Android Common Kernel、ReSukiSU、SuSFS、WildKernels、SukiSU、Baseband Guard、Re:Kernel、AnyKernel3 及相关社区维护者。