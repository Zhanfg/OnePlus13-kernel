# OnePlus 13 内核项目状态

更新时间：2026-07-29

## 1. 仓库关系

| 角色 | 仓库 | 默认分支 | 用途 |
|---|---|---|---|
| 主项目 | `Zhanfg/OnePlus13-kernel` | `main` | 构建脚本、AK3、测试、发布基线和项目文档 |
| 自定义 common 源码镜像 | `Zhanfg/android_kernel_common_oneplus_sm8750` | `6.6-final` | common 层自定义补丁承载，不等于完整 OKI 工程 |
| 官方 manifest | `OnePlusOSS/kernel_manifest` | `oneplus/sm8750` | 完整 OnePlus 13 OKI 工程入口 |

## 2. 目标设备与边界

- 设备：OnePlus 13 国行
- 代号：`sun`
- 型号：PJZ110
- SoC：Qualcomm SM8750
- 系统：ColorOS 16
- 当前公开上游：`PJZ110_16.0.9.401(CN01)`
- 官方完整 OKI 构建基线：Linux 6.6.118
- 自定义 common 开发分支：Linux 6.6.126
- 正确源码路径：OnePlusOSS 完整 OKI manifest
- 发布产物必须保持 Image、vendor_boot、vendor modules、DT/DTBO 与 ABI 基线一致

旧的 6.6.89 构建不属于当前有效基线，不应继续刷写或作为新构建起点。

## 3. 当前官方上游

| 组件 | 仓库 / 分支 | 2026-07-29 核对提交 |
|---|---|---|
| Manifest | `OnePlusOSS/kernel_manifest:oneplus/sm8750`，文件 `oneplus_13_b.xml` | 以固定 manifest 为准 |
| common | `OnePlusOSS/android_kernel_common_oneplus_sm8750:oneplus/sm8750_b_16.0.0_oneplus_13` | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` |
| msm-kernel | `OnePlusOSS/android_kernel_oneplus_sm8750:oneplus/sm8750_b_16.0.0_oneplus_13` | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| modules / devicetree | `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750:oneplus/sm8750_b_16.0.0_oneplus_13` | `d50b305f7da9e14715a25120a4ac7b1a4b8b97c3` |

详细同步流程见 [`UPSTREAM.md`](UPSTREAM.md)。

## 4. 两套内核版本的含义

### 官方完整 OKI 基线：6.6.118

此前成功执行的完整 OnePlus OKI 构建使用官方 manifest 与 `sun perf` 目标，产物 Makefile 版本为 Linux 6.6.118。这是当前已留有构建证据的完整工程基线。

### 自定义 common 分支：6.6.126

`Zhanfg/android_kernel_common_oneplus_sm8750:6.6-final` 当前 Makefile 为 Linux 6.6.126，并包含大量本地和社区补丁。它只是完整 OKI 工程中的 common 部分，不能单独替代官方 manifest 基线。

这两套版本不得混写：

- 不能把自定义 common 的 6.6.126 直接称为已经完成的 OnePlus 13 完整构建基线。
- 不能用官方 6.6.118 整树覆盖本地 6.6.126。
- 正确做法是将官方 OnePlus/OPlus、ABI 和 Android common 更新移植到自定义 common，并重新完成完整 OKI 构建。

## 5. common 上游同步状态

| 项目 | 当前结果 |
|---|---|
| 本地分支 | `6.6-final` / Linux 6.6.126 |
| 官方 common | `e1b346b6...` / Linux 6.6.118 |
| 共同祖先 | `5a0ffb447c1dbd82e8e3af7a98c4a629f4b6d143` |
| 本地领先 | 8,947 commits |
| 本地落后 | 5 official commits |
| 官方镜像分支 | `upstream/oneplus-sm8750-b-16.0.0-oneplus-13`，已与官方 tip 一致 |
| 同步候选 | `Zhanfg/android_kernel_common_oneplus_sm8750#6` |
| 候选状态 | Draft / 有冲突 / 未合并 |
| 冲突路径 | 80 个 |

冲突主要分布于：

- 驱动：29
- 文件系统：17
- 内核头文件与 hooks：13
- ABI/KMI/AFDO：10
- 架构与配置：8
- 其他：3

其中 `gki_defconfig`、ABI 列表、F2FS、调度/内存结构、vendor hooks、USB/Type-C/IOMMU 和电源路径属于高风险区域。完整清单保存在 common 仓库的 `docs/UPSTREAM_SYNC_16.0.9.401.md`。

## 6. 当前真实状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| 完整 OKI 源码同步 | 已完成 | 使用 `oneplus/sm8750` + `oneplus_13_b.xml` |
| 官方构建脚本编译 | 已完成 | `oplus_build_kernel.sh sun perf` 曾生成 6.6.118 产物 |
| 静态检查 | 已完成 | 工具链和 6.6.118 Image 已确认 |
| AK3 打包 | 已完成 | 已生成测试包，不能视为稳定发布 |
| 官方 16.0.9.401 三个核心仓库 SHA 核对 | 已完成 | common、msm-kernel、modules/DT 已记录 |
| common 官方镜像分支 | 已完成 | 已精确镜像官方 common tip |
| common 同步候选 | 已建立 | PR #6，含 80 个冲突，保持 Draft |
| common 冲突解决 | 待完成 | 必须逐文件审核，禁止整树 ours/theirs |
| 16.0.9.401 固定 manifest 构建 | 待完成 | 合并前必须保存 `repo manifest -r` 输出并 clean build |
| 真机启动验证 | 待完成 | 未完成前不得标记 Boot Verified |
| Root / SuSFS / 调度 / 网络等功能验证 | 待完成 | 需要在稳定启动后逐项启用和验证 |

## 7. 构建路径分级

### A. 主构建路径

完整 OnePlus OKI 源码树 + 官方构建脚本：

```bash
repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml
repo sync -c --force-sync --no-tags -j"$(nproc)"
repo manifest -r -o manifest-pinned.xml
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

仓库中的 `scripts/wsl_build_oki.sh` 用于辅助完整构建、增量构建和打包。这条路径是主要工程路径。

### B. 实验性 GitHub Actions

`.github/workflows/build.yml` 当前只克隆单个 `android_kernel_oneplus_sm8750` 仓库，并通过创建空 Kconfig / Makefile stub 绕过缺失组件。

这种方式：

- 不等价于完整 OKI 构建
- 不能保证 ABI、vendor modules 和设备树匹配
- 不作为稳定发布依据
- 产物只可用于早期实验或静态检查

在完成完整 manifest 同步、固定 revision、禁止 stub 绕过和真机验证前，该工作流必须保持 Experimental。

### C. 旧版脚本路径

`build.sh`、`scripts/patch.sh` 和 `configs/base_defconfig_fragment` 属于早期单仓库设计。它们可以作为补丁来源和配置研究资料，但不作为正式发布入口。

## 8. 目录职责

| 路径 | 职责 |
|---|---|
| `scripts/` | WSL / OKI 构建、验证、打包及旧版补丁脚本 |
| `anykernel/` | AK3 模板和刷写逻辑 |
| `tests/` | 静态、策略和真机运行时测试 |
| `docs/` | 对外工程说明、上游与状态文档 |
| `releases/` | 脱敏后的基线、测试产物记录和回退资料 |
| `.work/memory/` | 临时工程记录，不应作为公开事实来源 |
| `.github/workflows/` | 自动化；当前 build 工作流仍属实验性 |

## 9. 文档事实来源

1. `docs/PROJECT_STATUS.md`：公开项目状态和仓库边界。
2. `docs/UPSTREAM.md`：官方上游、版本锁定和同步流程。
3. `releases/BASELINE_CURRENT.txt`：当前脱敏基线。
4. common 仓库 `docs/UPSTREAM_SYNC_16.0.9.401.md`：实际冲突清单。
5. `README.md`：面向使用者的构建、刷写和功能说明。
6. `.work/memory/`：内部过程记录，不作为发布依据。

## 10. 当前最高优先级

1. 固定 16.0.9.401 的完整 `manifest-pinned.xml` 和构建证据。
2. 逐文件解决 common PR #6 的 80 个冲突，优先 ABI/KMI、配置、调度/内存、F2FS 和设备接口。
3. 用同一完整 OKI 基线重新生成 Image、vendor_boot 与 vendor modules。
4. 完成 ABI/KMI、OPlus symbol list、AFDO 和 vermagic 检查。
5. 保持 GitHub Actions 为 Experimental，避免误刷单仓库 stub 产物。
6. 完成真机启动后再验证蜂窝、Wi-Fi、相机、指纹、充电、休眠、Root、SuSFS 和调度。
7. 通过验证后发布带 manifest、源码 SHA、工具链、SHA256 和回退说明的正式 Release。

## 11. 隐私与仓库卫生

公开仓库不得保存本机绝对路径、磁盘布局、本地用户名、临时会话记录、未脱敏日志、账号、Token、Cookie、密钥或设备序列号。

## 12. 发布状态定义

- **Experimental**：可编译、可静态检查或可打包，但未完成真机启动。
- **Boot Verified**：指定 PJZ110 / ColorOS 版本可以重复启动，并确认可回退。
- **Runtime Verified**：关键硬件与内核功能完成测试。
- **Stable**：完成重复刷写、重启、待机和基础功能回归后才可使用。
