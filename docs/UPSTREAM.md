# OnePlus 13 官方上游与同步策略

更新时间：2026-07-29

## 1. 唯一正确的完整源码入口

OnePlus 13（`sun` / PJZ110 / SM8750）的完整官方工程应从 OnePlusOSS manifest 同步：

```text
Manifest repository: OnePlusOSS/kernel_manifest
Manifest branch: oneplus/sm8750
Manifest file: oneplus_13_b.xml
```

```bash
repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)"
repo manifest -r -o manifest-pinned.xml
```

只克隆单个 common 或 msm-kernel 仓库不能获得完整 OKI 工程。

## 2. 官方仓库关系

| 路径 | 仓库 | 分支 | 2026-07-29 核对提交 |
|---|---|---|---|
| `kernel_platform/common` | `OnePlusOSS/android_kernel_common_oneplus_sm8750` | `oneplus/sm8750_b_16.0.0_oneplus_13` | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` |
| `kernel_platform/msm-kernel` | `OnePlusOSS/android_kernel_oneplus_sm8750` | `oneplus/sm8750_b_16.0.0_oneplus_13` | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| 工程根目录 / vendor modules / DT | `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750` | `oneplus/sm8750_b_16.0.0_oneplus_13` | `d50b305f7da9e14715a25120a4ac7b1a4b8b97c3` |

Manifest 还固定了 CodeLinaro 构建规则、工具链、Kleaf/Bazel 依赖和其他组件。同步时不得只更新上表中的一个仓库而忽略其他 revision。

## 3. 当前公开官方基线

| 项目 | 当前值 |
|---|---|
| OnePlus 13 系统 | `PJZ110_16.0.9.401(CN01)` |
| 官方 common | Linux `6.6.118` |
| common Android tag | `android15-6.6-2026-01_r22` |
| msm-kernel QCOM tag | `AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111` |
| 完整 OKI 已有构建证据 | Linux `6.6.118` / `sun perf` |

上述 SHA 是分支在核对时的 tip，不代替 `manifest-pinned.xml`。正式构建必须保存完整固定 revision manifest。

## 4. 自定义 common 与官方 common 的真实关系

自定义 common 仓库：

```text
Zhanfg/android_kernel_common_oneplus_sm8750
branch: 6.6-final
Makefile: Linux 6.6.126
```

官方 common：

```text
OnePlusOSS/android_kernel_common_oneplus_sm8750
branch: oneplus/sm8750_b_16.0.0_oneplus_13
SHA: e1b346b6b4f4096eb342ae3684838a942fd6f6c4
Makefile: Linux 6.6.118
```

已确认关系：

| 项目 | 结果 |
|---|---|
| 共同祖先 | `5a0ffb447c1dbd82e8e3af7a98c4a629f4b6d143` |
| 本地领先 | 8,947 commits |
| 本地落后 | 5 official commits |
| 官方镜像分支 | `upstream/oneplus-sm8750-b-16.0.0-oneplus-13` |
| 固定同步候选 | `sync/official-16.0.9.401-e1b346b6b` |
| 同步 PR | `Zhanfg/android_kernel_common_oneplus_sm8750#6` |
| PR 状态 | Draft / conflicts / not merged |
| 冲突路径 | 80 个 |

本地 common 的版本号比官方高，但这不表示已经包含 OnePlus 16.0.9.401 的全部设备、ABI 和厂商改动。本次工作不是普通版本升级，而是将官方更新移植到本地较新的 custom common 基线上。

完整冲突清单位于 common 仓库：

```text
docs/UPSTREAM_SYNC_16.0.9.401.md
```

## 5. 冲突范围

80 个冲突路径主要分布：

| 类别 | 数量 | 重点 |
|---|---:|---|
| 驱动 | 29 | USB、Type-C、IOMMU、蓝牙、NVMe、网络、电源 |
| 文件系统 | 17 | F2FS、EXT4、BTRFS、NTFS3、SMB、NFSD |
| 内核头文件与 hooks | 13 | 调度、内存、vendor hooks、ABI 接口 |
| ABI/KMI/AFDO | 10 | `.stg`、OPlus symbols、protected exports |
| 架构与配置 | 8 | `gki_defconfig`、BPF JIT、x86/mips/loongarch |
| 其他 | 3 | `Makefile`、`.gitignore`、F2FS ABI 文档 |

高风险冲突包括：

- `Makefile`：6.6.126 本地版本与 6.6.118 官方版本语义
- `arch/arm64/configs/gki_defconfig`
- `android/abi_gki_aarch64.stg` 与 OPlus ABI symbol list
- `include/linux/sched.h`、`include/linux/mm*.h`、vendor hooks
- F2FS / EXT4
- USB / Type-C / IOMMU / 电源路径

## 6. 同步流程

### 阶段 A：官方镜像和核对

1. 获取 manifest 最新分支和 `oneplus_13_b.xml`。
2. 获取 common、msm-kernel、modules/devicetree 当前 tip。
3. 更新只读官方镜像分支。
4. 记录共同祖先、ahead/behind 和内核版本。
5. 使用非破坏性 `git merge-tree` 输出冲突报告。

这一阶段已经完成。

### 阶段 B：逐文件解决 common 冲突

建议顺序：

1. `Makefile`、版本号和 Android common tag
2. ABI/KMI、OPlus symbol list、AFDO
3. `gki_defconfig` 和构建系统
4. common 与 msm-kernel / vendor modules 接口
5. 调度、内存与 vendor hooks
6. F2FS、EXT4、ZRAM 与文件系统 hook
7. USB、Type-C、IOMMU、电源和其他设备接口
8. 网络与其他通用驱动

不得整树选择 ours/theirs。每组应形成独立提交，便于构建和回退。

### 阶段 C：完整 OKI 更新

在固定 manifest 的完整工作区中应用已解决的 common 候选：

```bash
repo manifest -r -o manifest-pinned.xml
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

必须同时核对 msm-kernel、modules/devicetree、vendor_boot、vendor modules、ABI/KMI 和 vermagic。

### 阶段 D：真机验证

至少执行：

- 可重复启动和重启
- Fastboot / Recovery 回退
- 蜂窝、移动数据、VoLTE/IMS
- Wi-Fi、蓝牙、相机、指纹
- 充电、电池状态、温控、灭屏和深度休眠
- Root、SuSFS、KPM
- wait、HMBIRD/风驰、SCX
- BBR、Netfilter、TUN/VPN、WireGuard

## 7. 自动化

common 仓库已经建立：

```text
.github/workflows/sync-upstream.yml
.github/workflows/verify-upstream-pr.yml
```

自动化使用 blobless 历史获取和稀疏工作树，负责：

- 镜像官方 common tip
- 记录本地和官方 SHA、内核版本、共同祖先
- 执行非破坏性 merge-tree 检查
- 上传冲突报告
- 在无冲突时创建候选

自动化永不直接合并 `6.6-final`。

## 8. 禁止的同步方式

- 只更新 common，不同步 manifest 其他仓库
- 使用单仓库 CI 的空 Kconfig / Makefile stub 产物作为正式发布
- 直接覆盖整个自定义分支
- 使用 `git merge -s ours` 或删除冲突代码伪造成功
- 对 80 个冲突批量选择 ours/theirs
- 不保存上游 SHA 和固定 manifest
- 把 6.6.89 等旧产物重新标记为当前基线
- 未核对 vendor modules / vendor_boot 就刷入 Image
- 未完成完整 OKI build 和真机验证就合并同步 PR #6

## 9. 发布记录模板

```text
Device: PJZ110 / sun
ROM: ColorOS 16.x.x.xxx
Manifest repo/branch/file:
Pinned manifest SHA256:
Official common SHA/version:
Custom common SHA/version:
MSM-kernel SHA:
Modules/devicetree SHA:
Merge base:
Conflict resolution range:
Toolchain:
Build result:
ABI/KMI result:
Boot result:
Runtime result:
Artifact SHA256:
Rollback package:
Known issues:
```

## 10. 相关链接

- https://github.com/OnePlusOSS/kernel_manifest
- https://github.com/OnePlusOSS/kernel_manifest/blob/oneplus/sm8750/oneplus_13_b.xml
- https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750
- https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750
- https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750
- https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750
- https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750/pull/6
