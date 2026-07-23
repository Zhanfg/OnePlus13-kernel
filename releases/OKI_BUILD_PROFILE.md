# OnePlus 13 OKI 内核编译内容总结

> 日期：2026-07-23
> 源码路径：`/home/axymorrsen/op13-oki`（Arch WSL ext4）
> 构建模式：浅同步 `--depth=1 -c --no-tags`，~11 GB

---

## 1. 目标机型与系统

| 项 | 值 |
|----|-----|
| 设备 | OnePlus 13 / **PJZ110** |
| 平台代号 | **sun** / **SM8750** |
| 系统版本 | ColorOS **16.0.9.401(CN01)** |
| 内核分区 | **boot**（纯 kernel Image，无 ramdisk） |
| Image 形态 | ARM64 Image，4K pages，~36 MB |
| 刷入方式 | AK3（`block=boot; split_boot; flash_boot`） |
| 版本串金样 | `6.6.118-android15-8-g…-abogki500782043-4k` |

---

## 2. 源码构成

### 2.1 清单

**Manifest**：`OnePlusOSS/kernel_manifest` → `oneplus/sm8750` 分支 → `oneplus_13_b.xml`

### 2.2 核心三仓

| 路径 | 仓库 | 分支 |
|------|------|------|
| `kernel_platform/common` | [`android_kernel_common_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750) | `oneplus/sm8750_b_16.0.0_oneplus_13` |
| `kernel_platform/msm-kernel` | [`android_kernel_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750) | 同上 |
| `./` (modules+dt) | [`android_kernel_modules_and_devicetree_oneplus_sm8750`](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750) | 同上 |

### 2.3 当前 tip

```
common:    e1b346b6b "Synchronize code for OnePlus ... PJZ110_16.0.9.401(CN01)
           Based on QCOM release TAG: android15-6.6-2026-01_r22"

msm-kernel: 6028f47fa "Synchronize code for OnePlus ... PJZ110_16.0.9.401(CN01)
           Based on QCOM release TAG: AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111"
```

**内核版本：Linux 6.6.118**（与 stock 完全一致！）

### 2.4 预编译工具链

| 路径 | 内容 |
|------|------|
| `prebuilts/clang/host/linux-x86/clang-r510928` | **Android clang 18.0.0**（r510928） |
| `prebuilts/clang/host/linux-x86/clang-3289846` | 旧版 clang |
| `prebuilts/clang/host/linux-x86/clang-stable` | 稳定版软链接 |

**为什么重要：** stock 和 能刷 144 的 clang 也是 **r510928**，完全对齐。

### 2.5 其他关键目录

| 目录 | 内容 |
|------|------|
| `kernel_platform/build/` | Bazel / kleaf 构建规则 |
| `kernel_platform/oplus/` | OPPO 定制层（LSM、调度、健康检查等） |
| `kernel_platform/external/` | 第三方模块（如 zram、加密） |
| `kernel_platform/qcom/` | Qualcomm 平台代码 |
| `vendor/` | 厂商预编译闭源组件 |

---

## 3. 构建命令

```bash
cd /home/axymorrsen/op13-oki
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

| 参数 | 含义 |
|------|------|
| `sun` | 目标平台（即 OnePlus 13 / PJZ110 代号） |
| `perf` | 构建类型 = **user build**（正式发行版）；`consolidate` = userdebug |

### 构建流程

```
oplus_build_kernel.sh
  ├─ oplus_setup.sh sun perf    ← 设置环境变量、TOPDIR、变体
  ├─ prepare_vendor.sh          ← 准备 vendor 模块、设备树
  └─ Bazel / kleaf 编译
       ├─ common/       → GKI 通用内核
       ├─ msm-kernel/   → 高通平台内核 + 设备树
       └─ 输出 → out/msm-kernel-sun-perf/dist/Image
```

### 产物路径预期

```
kernel_platform/out/msm-kernel-sun-perf/dist/
  ├─ Image          ← 主内核镜像（~36MB，ARM64）
  ├─ *.ko           ← 内核模块（部分场景）
  └─ *.dtb / *.img  ← 设备树（可选）
```

---

## 4. 与黄金样本对照

| 检查项 | stock (6.6.118) | 能刷包 (6.6.144) | **本次预期** |
|--------|----------------|-------------------|-------------|
| 内核版本 | 6.6.118 | 6.6.144 | **6.6.118**（同 stock） |
| 版本族 | `android15-8` | `android15-8` | ✅ 同源 |
| 厂商后缀 | `abogki500782043` | `abogki500782043` | ✅ 同源 |
| 页大小 | `-4k` | `-4k` | ✅ 同源 |
| 工具链 | clang r510928 | clang r510928 | ✅ **r510928** |
| 构建系统 | kleaf | kleaf/类官方 | ✅ Bazel/kleaf |
| 体积 | ~36 MB | ~36 MB | ~36 MB |
| OGKI hooks | 完整 | 完整 | ✅ 同官方树 |

**预期版本串形态：**
```
6.6.118-android15-8-g<短哈希>-abogki<数字>-4k
```

---

## 5. 不包含的内容

此编译阶段是 **Vanilla OKI**，不做任何修改：

| 不包含 | 原因 |
|--------|------|
| ReSukiSU / KernelSU | 阶段 G 再加，先验证 vanilla 开机 |
| HMBIRD / BORE 调度 | 与官方 OKI 默认调度不同，后续再说 |
| BBG (Baseband Guard) | 阶段 G3 再加 |
| BBR3 / CAKE | 默认 BBR，后续可改 |
| KPM 嵌入 | 默认不嵌入，用 KPatch-Next 模块 |
| 任何自定义 defconfig 碎片 | 纯官方 `sun_perf_defconfig` |

---

## 6. 打包计划

用能刷 144 的 AK3 作模板，只替换 `Image`：

```
AK3_6_6_144_..._comm.zip 模板
       ↓
    解压 → 替换 Image → 改 kernel.string
       ↓
v6.6.118-OnePlus13-sun-AK3-OKI-VANILLA-<stamp>.zip
```

刷入方式：Recovery 刷 AK3 或 Manager 刷 zip

---

## 7. 后续阶段

```
┌─ 当前 ─────────────────────────────┐
│ C1: oplus_build_kernel.sh sun perf  │ ← 你在这里
│ C2: 定位产物 Image                   │
│ C3: strings+file 验证版本串           │
│ D1: 静态验收对比金样                   │
│ E:  打包 AK3                         │
│ F:  真机开机验证                       │
├─ 通过后才进行 ───────────────────────┤
│ G1: + ReSukiSU                       │
│ G2: 再编 → 再验 Root                 │
│ G3: + BBG / 网络功能 / 逐批加        │
└──────────────────────────────────────┘
```

---

## 8. 速查

```bash
# 产物定位
find /home/axymorrsen/op13-oki -name "Image" -type f 2>/dev/null

# 版本串验证
strings <Image> | grep -E 'Linux version 6\.6' | head -2
file <Image>

# 与 stock toolchain 对比
strings <Image> | grep "r510928" | head -2
```
