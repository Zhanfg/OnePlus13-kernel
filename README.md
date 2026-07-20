# 一加 13 (sun / SM8750) 自定义内核

> 基于 **官方 OnePlusOSS OOS SM8750 内核树**，为 **一加 13（sun）+ ColorOS 16 国行** 构建的自定义内核。
> 产物：**仅 AnyKernel3 (AK3) zip**，通过 GitHub Actions 可复现构建。

---

## 目录

- [项目简介](#项目简介)
- [功能特性](#功能特性)
- [项目结构](#项目结构)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [本地构建](#本地构建)
- [GitHub Actions 构建](#github-actions-构建)
- [刷写方法](#刷写方法)
- [AK3 交互菜单说明](#ak3-交互菜单说明)
- [验收检查](#验收检查)
- [配置说明](#配置说明)
- [常见问题 (FAQ)](#常见问题-faq)
- [注意事项](#注意事项)
- [技术规格对照](#技术规格对照)

---

## 项目简介

本项目在官方 OnePlusOSS OOS SM8750 内核树上，为一加 13（sun）+ ColorOS 16 国行构建带完整功能与默认策略的自定义内核，产出可刷写的 AK3 zip。

### 核心原则

- **保留官方行为**：充电、蜂窝信号、指纹、相机、完整音频通路
- **不修改基带镜像**
- **不把杜比解码器编进内核**（由用户自行安装用户态 KSU 模块）
- **默认策略**：wait 调度 + bbr3 + fq + lz4 + BBG 默认开

---

## 功能特性

### Root / 隐藏 / 挂载 / KPM

| 功能 | 说明 |
|------|------|
| ReSukiSU | 主 Root 方案，多管理器兼容 |
| SuSFS v2.2.0 | 全功能：SUS_PATH/MOUNT/KSTAT/MAP、OPEN_REDIRECT、AVC spoof、uname/cmdline spoof |
| KALLSYMS(+ALL) | 始终启用，便于 KPatch-Next 模块加载 `.kpm` |
| KPM | 刷写时可选（音量键），默认不应用 |
| hy / Mountify | OVERLAY_FS + TMPFS_XATTR + TMPFS_POSIX_ACL |

### 调度

| 功能 | 说明 |
|------|------|
| **默认 wait** | 优化后的 wait，开机默认 |
| HMBIRD / 风驰 | 合入 Numbersf/WildKernels 全量补丁（非官方，非空壳），可选启用 |
| SCX | 编入，与 HMBIRD 共存，可回退 wait |

### I/O / 存储 / ZRAM

| 功能 | 说明 |
|------|------|
| ADIOS | I/O 调度器（可选） |
| F2FS 微优化 | 不加重「必须清 data 才能开机」类问题 |
| ZRAM 全栈 | LZ4 1.10.0、ZSTD 1.5.7、LZ4KD、Multi-Comp、Writeback；**默认 lz4** |

### 网络（完整栈）

| 功能 | 说明 |
|------|------|
| **BBRv3** | 默认拥塞控制（bbr3，非仅 bbr） |
| **fq** | 默认 qdisc |
| cake / fq_codel | 可用 |
| IP_SET | 完整可用 |
| TPROXY / REDIRECT / NAT | IPv4/IPv6 路由、隐私扩展、TTL/HL |
| WireGuard | 内核接口可建、可跑流量 |

### 通信 / 安全

| 功能 | 说明 |
|------|------|
| **Baseband Guard (BBG)** | 默认开启，运行时可关闭，不改基带镜像 |
| WiFi 6GHz | 协议栈兼容；区域解锁用模块 |

### 省电

| 功能 | 说明 |
|------|------|
| Re:Kernel | 内核侧完整；配合用户态 NoActive/Freezer |
| Wakelock Blocker | 补丁完整合入 |
| 省电小补丁 | reduce_freeze_timeout、avoid_extra_s2idle、minimise_wakeup_time 等 |

### 容器 / 兼容

| 功能 | 说明 |
|------|------|
| Droidspaces | PID_NS、IPC_NS、SYSVIPC、POSIX_MQUEUE 真实启用 |
| NTSYNC | `/dev/ntsync` |
| Unicode Bypass | 完整补丁 |
| XUS Error Fix | 完整补丁 |

### 编译优化

| 功能 | 说明 |
|------|------|
| LTO Thin + O2 | 固定编译策略 |
| Oryon 优化 | `-mcpu=oryon-1`（工具链支持时） |
| LRNG | Linux Random Number Generator |

### 明确不包含

- 杜比解码器 / 杜比音效 blob（用户态 KSU 模块）
- SuSFS 用户态模块（不进 AK3）
- KPatch-Next 模块本体（不进 AK3）
- 解容 / 激进充电曲线
- 强改最高亮度 / Improved Haptics
- 内核强解 WiFi 国家码
- 基带固件修改

---

## 项目结构

```
OnePlus13-kernel/
├── build.sh                          # 内核构建主脚本
├── .gitignore
├── README.md                         # 本文档
│
├── configs/                          # 内核配置
│   ├── base_defconfig_fragment       # 基础 defconfig 碎片（所有 CONFIG 项）
│   └── verify_config.sh              # CONFIG 验证脚本
│
├── scripts/                          # 辅助脚本
│   └── patch.sh                      # 补丁管理（获取/合入/验证）
│
├── anykernel/                        # AnyKernel3 刷写包
│   ├── anykernel.sh                  # AK3 主脚本（含7题交互菜单）
│   ├── service.sh                    # 开机策略应用脚本
│   ├── module.prop                    # 模块信息
│   └── META-INF/com/google/android/
│       ├── update-binary             # AK3 入口
│       └── updater-script            # 占位脚本
│
├── .github/workflows/
│   └── build.yml                     # GitHub Actions CI/CD 工作流
│
├── tests/                            # 测试
│   ├── test_static.py                # 静态验收测试（Python）
│   ├── test_policies.py              # 策略单元测试（Python unittest）
│   └── verify_runtime.sh             # 运行时验收脚本（真机执行）
│
└── docs/                             # 文档目录
```

---

## 环境要求

### 本地构建

- **OS**: Ubuntu 22.04 / 24.04（或 WSL2）
- **工具链**: Android Clang (r498229b 或更新) + GCC aarch64 交叉编译器
- **依赖**: bc, bison, build-essential, ccache, flex, libelf-dev, libssl-dev, python3
- **磁盘空间**: 约 30 GB（内核源码 + 编译输出）
- **内存**: 建议 16 GB 以上

### GitHub Actions 构建

- 无需本地环境，直接在 GitHub Actions 上运行
- 使用 `ubuntu-24.04` runner
- 构建时间约 30-60 分钟

---

## 快速开始

### 方式一：GitHub Actions（推荐）

1. Fork 本仓库到你的 GitHub 账号
2. 进入仓库的 **Actions** 页面
3. 选择 **Build OnePlus 13 Custom Kernel (AK3)** 工作流
4. 点击 **Run workflow**
5. 选择构建参数（变体、Oryon 优化、LTO 模式）
6. 等待构建完成，下载 Artifacts 中的 AK3 zip

### 方式二：本地构建

```bash
# 1. 克隆本项目
git clone <your-repo-url>
cd OnePlus13-kernel

# 2. 安装依赖
sudo apt-get update
sudo apt-get install -y bc bison build-essential ccache cpio curl flex \
  git libelf-dev libncurses-dev libssl-dev python3 zip zlib1g-dev

# 3. 下载并合入补丁（会自动克隆官方内核树）
chmod +x scripts/patch.sh build.sh
./scripts/patch.sh fetch
./scripts/patch.sh apply

# 4. 配置工具链（设置环境变量）
export CC=clang
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# 5. 完整构建
./build.sh all

# 6. 产物
ls *.zip *.sha256
```

---

## 本地构建

### 分步执行

```bash
# 仅配置内核
./build.sh config

# 仅编译
./build.sh compile

# 仅打包 AK3
./build.sh package

# 清理输出
./build.sh clean

# 完整构建（config + compile + package）
./build.sh all
```

### 补丁管理

```bash
# 下载所有补丁到 patches/cache/
./scripts/patch.sh fetch

# 按规格顺序合入补丁到 kernel_source/
./scripts/patch.sh apply

# 验证补丁完整性
./scripts/patch.sh verify

# 查看补丁状态
./scripts/patch.sh summary
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `KERNEL_DIR` | `./kernel_source` | 内核源码目录 |
| `OUT_DIR` | `./out` | 输出目录 |
| `ARCH` | `arm64` | 架构 |
| `CC` | `clang` | Clang 路径 |
| `CROSS_COMPILE` | `aarch64-linux-gnu-` | 交叉编译前缀 |
| `JOBS` | `$(nproc)` | 编译线程数 |
| `ORYON_CPU` | (空) | Oryon CPU 优化参数 |
| `LTO` | `thin` | LTO 模式 |

---

## GitHub Actions 构建

### 触发方式

- **手动触发**：Actions → Build OnePlus 13 Custom Kernel → Run workflow
- **定时构建**：每周日凌晨 3 点 UTC 自动执行

### 构建参数

| 参数 | 选项 | 说明 |
|------|------|------|
| `build_variant` | stable / beta / experimental | 构建变体 |
| `oryon_optimize` | true / false | Oryon CPU 优化 |
| `lto_mode` | thin / full / none | LTO 模式 |

### 产物

- `OnePlus13-sun-custom-*.zip`：AK3 刷写包
- `*.sha256`：SHA256 校验文件
- `build_info.json`：构建信息（commit、分支、配置等）
- `build.log`：完整构建日志

---

## 刷写方法

### 前置条件

- 一加 13（sun / SM8750），ColorOS 16 国行
- 已解锁 Bootloader
- TWRP / OrangeFox 等自定义 Recovery
- AK3 zip 文件

### 刷写步骤

1. 将 AK3 zip 传输到手机
2. 重启进入 Recovery
3. 选择 **Install** → 找到 AK3 zip
4. **滑动刷写**，进入交互菜单
5. 按音量键选择各选项（见下方说明）
6. 等待刷写完成
7. 重启设备

### 回滚

如刷写后无法开机：

1. 重启进入 Recovery
2. 使用刷写时创建的备份（`/data/kernel_backup_*/init_boot.img`）
3. 刷回原版 init_boot
4. 重启

---

## AK3 交互菜单说明

刷写时会显示 7 道选择题，使用**音量键**选择：

| 按键 | 含义（全程固定） |
|------|------------------|
| **音量 +** | 选择第一项 / 推荐项 / 是 |
| **音量 -** | 选择第二项 / 备选项 / 否 |
| **超时未按键** | 使用规格默认并继续刷写 |

### 各题说明

| 题目 | 音量+（推荐） | 音量-（备选） |
|------|---------------|---------------|
| 【1/7】默认 CPU 调度 | wait（稳定） | 风驰/HMBIRD（性能向） |
| 【2/7】默认 TCP | bbr3（规格默认） | cubic（传统） |
| 【3/7】默认 qdisc | fq（搭配 bbr3） | fq_codel |
| 【4/7】默认 ZRAM | lz4（更快） | zstd（更高压缩率） |
| 【5/7】Baseband Guard | 开启（降低风险） | 关闭（排障用） |
| 【6/7】KPM 补丁 | 不应用（用 KPatch-Next） | 应用（嵌入 Image） |
| 【7/7】备份 init_boot | 备份（可回滚） | 跳过 |

刷写完成后会显示选择汇总并记录到 `/data/ak3-choices.log`。

---

## 验收检查

### 静态测试（编译后）

```bash
# 验证项目结构、配置、AK3 完整性
python3 tests/test_static.py

# 策略单元测试
python3 tests/test_policies.py
```

### 运行时验收（真机执行）

将 `tests/verify_runtime.sh` 传到手机后执行：

```bash
# 需要 root
su -c "sh verify_runtime.sh"
```

验收项目包括：

| 功能 | 验收标准 |
|------|----------|
| ReSukiSU | `su -c id` 返回 uid=0 |
| SuSFS v2.2.0 | 版本接口为 v2.2.0 |
| KALLSYMS | `/proc/kallsyms` 符号数 > 1000 |
| wait 默认 | 开机后调度路径为 wait |
| HMBIRD/SCX | 全量补丁实装，非壳；可启用/回退 |
| BBRv3 | `tcp_congestion_control=bbr3` |
| fq | `default_qdisc=fq` |
| ZRAM | 多算法可选，默认 lz4 |
| IP_SET/WG | 对应命令可用 |
| BBG | 默认生效，可关闭 |
| Droidspaces | `unshare -p` 成功 |
| NTSYNC | `/dev/ntsync` 存在 |
| 官方行为 | 充电/信号/指纹/音频正常 |

---

## 配置说明

### 内核配置碎片

`configs/base_defconfig_fragment` 包含所有自定义 CONFIG 项，在构建时合并到官方 defconfig。

关键配置项：

```
# Root
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y

# hy / Mountify
CONFIG_OVERLAY_FS=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y

# 网络
CONFIG_TCP_CONG_BBR=y
CONFIG_TCP_CONG_BBR3=y
CONFIG_NET_SCH_FQ=y
CONFIG_NET_SCH_CAKE=y
CONFIG_WIREGUARD=y
CONFIG_IP_SET=y
CONFIG_NF_TPROXY=y

# ZRAM
CONFIG_ZRAM=y
CONFIG_ZRAM_MULTI_COMP=y
CONFIG_ZRAM_WRITEBACK=y

# 容器
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_NTSYNC=y
```

### 默认策略

所有默认策略在 AK3 刷写时通过音量键选择，由 `anykernel.sh` 中的 `pre_checks()` 设置初始默认值：

```bash
SCHED_CHOICE="wait"     # 默认调度
TCP_CHOICE="bbr3"       # 默认 TCP
QDISC_CHOICE="fq"       # 默认 qdisc
ZRAM_CHOICE="lz4"       # 默认 ZRAM
BBG_CHOICE="on"         # 默认 BBG
KPM_CHOICE="no"         # 默认不应用 KPM
BACKUP_CHOICE="yes"     # 默认备份
```

---

## 常见问题 (FAQ)

### Q: 刷写后无法开机怎么办？

A: 重启进入 Recovery，使用刷写时创建的备份（`/data/kernel_backup_*/init_boot.img`）刷回原版 init_boot。建议刷写时选择「备份」。

### Q: 杜比音效怎么开启？

A: 杜比解码器不在内核中。请安装用户态 KSU 模块（如 dolbycodec2 / Oplus AIDL D1 系）。内核只保证音频通路不被破坏。

### Q: 风驰/HMBIRD 怎么启用？

A: 刷写时在【1/7】选择音量-。注意：风驰为非官方全量补丁，不等同于官方风驰 1:1。如启用后异常，可通过 sysfs 节点回退到 wait。

### Q: KPM 选「应用」和「不应用」有什么区别？

A:
- **不应用（推荐）**：不改 Image KPM 段，之后用 KPatch-Next 模块加载 `.kpm`
- **应用**：执行 patch_android 流程，将 KPM 嵌入内核镜像

两种路径均要求 `KALLSYMS=y` + `KALLSYMS_ALL=y`。

### Q: BBG 是什么？可以关吗？

A: Baseband Guard 是内核 LSM，拦截对关键分区/节点的违规写入，降低格机风险。默认开启，可在刷写时选择关闭（仅排障时建议）。

### Q: 构建失败怎么办？

A:
1. 检查 `out/build.log` 中的错误信息
2. 确认工具链正确安装
3. 确认补丁已正确合入（`./scripts/patch.sh verify`）
4. 尝试清理后重新构建（`./build.sh clean && ./build.sh all`）

---

## 注意事项

1. **仅适用于一加 13（sun / SM8750）+ ColorOS 16 国行**，刷入其他设备可能导致无法开机。
2. **刷写前务必备份** init_boot，以便回滚。
3. **不修改基带镜像**，基带相关功能保持官方行为。
4. **杜比不依赖内核**，由用户态模块决定。
5. **风驰为非官方补丁**，不等同于官方风驰 1:1，稳定性以真机为准。
6. 合入补丁后如导致无法开机或官方关键功能失效，应回退该步，不得强行宣称完成。

---

## 技术规格对照

| 规格 | 本项目 |
|------|--------|
| 机型 | 一加 13（sun），SoC SM8750 |
| 系统 | ColorOS 16 国行 |
| 源码基准 | OnePlusOSS OOS SM8750 内核树 |
| 产物 | 仅 AK3 zip |
| 刷写路径 | init_boot（split_boot / flash_boot） |
| 默认调度 | wait |
| 默认 TCP | bbr3 |
| 默认 qdisc | fq |
| 默认 ZRAM | lz4 |
| BBG | 默认开，可关 |
| KPM | 刷写可选，默认不应用 |
| KALLSYMS | 始终启用 (+ALL) |
| 杜比 | 不进内核，用户态模块 |
| 基带 | 不修改 |
| 构建 | GitHub Actions 可复现 |

---

## 许可证

本项目构建脚本和配置文件遵循其各自许可证。内核源码遵循 OnePlusOSS / GPL 许可证。各补丁遵循其原始仓库许可证。

---

## 致谢

- [OnePlusOSS](https://github.com/OnePlusOSS) - 官方内核源码
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) - Root 方案
- [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) - SuSFS
- [Numbersf/SCHED_PATCH](https://github.com/Numbersf/SCHED_PATCH) - HMBIRD/风驰
- [WildKernels](https://github.com/WildKernels/kernel_patches) - BBRv3、省电、NTSYNC 等
- [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) - BBG
- [Sakion-Team/Re-Kernel](https://github.com/Sakion-Team/Re-Kernel) - Re:Kernel
- [Goldzxcbug/Droidspaces](https://github.com/Goldzxcbug/Droidspaces_Kernel_patch) - Droidspaces
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU_patch) - ZRAM 等
