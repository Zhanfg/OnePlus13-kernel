# OnePlus 13 内核项目状态

更新时间：2026-07-29

## 1. 项目范围

| 角色 | 仓库 / 分支 | 用途 |
|---|---|---|
| 项目控制仓库 | `Zhanfg/OnePlus13-kernel:main` | 构建、AK3、测试、发布和文档 |
| 自定义 common | `Zhanfg/android_kernel_common_oneplus_sm8750:6.6-final` | common 自定义补丁和上游移植 |
| 官方 manifest | `OnePlusOSS/kernel_manifest:oneplus/sm8750` | 完整 OKI 入口，文件 `oneplus_13_b.xml` |

目标设备：OnePlus 13 国行 `PJZ110`，代号 `sun`，SoC `SM8750`，系统基线 `PJZ110_16.0.9.401(CN01)`。

## 2. 官方组件基线

| 组件 | SHA / 版本 |
|---|---|
| common | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` / Linux 6.6.118 |
| msm-kernel | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| modules / devicetree | `d50b305f7da9e14715a25120a4ac7b1a4b8b97c3` |
| Android common tag | `android15-6.6-2026-01_r22` |
| QCOM tag | `AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111` |

正式构建必须保存 `repo manifest -r -o manifest-pinned.xml` 的固定结果。

## 3. 两套内核基线

### 完整 OKI 官方构建

- Linux 6.6.118
- `./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf`
- 已有构建、静态检查和测试包记录
- 未完成真机启动验证

### 自定义 common

- 仓库：`Zhanfg/android_kernel_common_oneplus_sm8750`
- 分支：`6.6-final`
- Linux 6.6.126
- 只对应 `kernel_platform/common`，不等于完整 OKI 工程

不能用官方 6.6.118 整树覆盖自定义 6.6.126，也不能因为本地版本号更高就宣称已包含最新 OnePlus 设备改动。

## 4. 官方 common 同步

| 项目 | 结果 |
|---|---|
| 共同祖先 | `5a0ffb447c1dbd82e8e3af7a98c4a629f4b6d143` |
| 本地领先 | 8,947 commits |
| 本地落后 | 5 official commits |
| 固定候选 | `android_kernel_common_oneplus_sm8750#6` |
| 初始真实冲突 | **116 个路径** |
| 第一轮已处理 | 31 个路径 |
| 第一轮后剩余 | **85 个路径** |

早期 80 个数字来自截断的 merge-tree 报告，已经废止。116 是真实 `git merge` 后检查 unmerged index 的权威结果。

第一轮规则已通过 Actions 重放验证：

```text
Initial conflicts: 116
Resolved paths: 31
Remaining conflicts: 85
```

该工作流最后主动失败，用于阻止仍有冲突的源码候选进入默认分支。

## 5. 调度架构阻塞

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

HMBIRD 与官方 SCX 占用相同策略编号，并修改同一批 fork、tick、pick-next、setscheduler、cgroup 和 idle 接口。`kernel/sched/core.c` 单文件有 28 个冲突块。

当前不能声明 HMBIRD 与 SCX 已完成共存。稳妥方向是先保留 wait + HMBIRD/风驰主路径，移植官方非 SCX 修复；完整 SCX 恢复应作为独立架构任务处理。

## 6. 当前进度

| 阶段 | 状态 |
|---|---|
| 完整官方 OKI 同步 | 已完成 |
| 官方 6.6.118 构建 | 已完成 |
| 官方三个核心仓库 SHA 核对 | 已完成 |
| 官方 common 镜像分支 | 已完成 |
| 固定官方同步 PR #6 | 已建立，保持 Draft |
| 四方冲突文件导出 | 已完成 |
| 第一轮 31 路径解决规则 | 已完成并验证 |
| 剩余 85 个冲突 | 处理中 |
| 固定 manifest clean build | 待完成 |
| ABI/KMI / AFDO | 待完成 |
| 真机启动与运行时验证 | 待完成 |

## 7. 后续处理顺序

1. HMBIRD / SCX / SLIM 架构和策略编号
2. ABI/KMI、OPlus symbol list、protected exports、AFDO
3. `gki_defconfig`、Kleaf/Bazel 和工具链
4. task/fork/tick、内存和 vendor hooks
5. common 与 msm-kernel / vendor modules 接口
6. F2FS、EXT4、ZRAM 和文件系统 hooks
7. USB、Type-C、IOMMU、电源和设备驱动
8. 网络与音频
9. 完整 OKI clean build
10. ABI/KMI 和真机回归

每一轮必须有明确路径清单、三方证据、可重复工作流和解决前后冲突计数。

## 8. 正确构建路径

```bash
repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)"
repo manifest -r -o manifest-pinned.xml
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

单仓库 stub CI 仍属于 Experimental，不作为正式发布依据。

## 9. 发布门槛

- 85 个剩余冲突全部解决
- 调度架构明确
- 完整固定 manifest clean build
- ABI/KMI、OPlus symbol list、AFDO 通过
- Image、vendor_boot、vendor modules 与 vermagic 匹配
- 可重复启动、重启和回退
- 蜂窝、Wi-Fi、蓝牙、相机、指纹、充电、温控、休眠通过
- Root、SuSFS、KPM、wait/HMBIRD 和网络栈通过
- SCX 若恢复，另做完整启用与回退验证

未达到上述条件前，状态保持 **Experimental**。
