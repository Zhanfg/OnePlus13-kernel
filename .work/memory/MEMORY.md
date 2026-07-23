# 一加13 内核构建项目 - 长期记忆

## 项目概况
- 路径: `D:\OnePlus13-kernel`（仓库/文档/脚本/AK3 模板）
- WSL 构建: `/home/axymorrsen/op13-oki`（OKI 源码 + 构建产物）
- 目标: 一加13 (sun/SM8750) + ColorOS 16 国行自定义内核
- 源码: OnePlusOSS `oneplus/sm8750_b_16.0.0_oneplus_13` (6.6.118)
- 工具链: Android clang r510928（随 manifest prebuilts 同步）
- 产物: AnyKernel3 (AK3) zip（含 Image + vendor_boot.img）

## 真机基线
- 机型: PJZ110 国行 · `PJZ110_16.0.9.401(CN01)`
- 官方 boot 内核: `6.6.118-android15-9-g690101101069`
- 能刷的自定义 AK3: `6.6.144-android15-8-g4de260df0fc2`（schqiushui）
- 救砖: `releases/restore/boot.img`（16.0.9.401 stock）
- ❌ 禁止刷 6.6.89 旧包
- 历史: M1/M2/M3（破星 6.6.126）全部 bootloop — 根因是错误工具链+错误配置

## 版本串分析（核心发现）

| 来源 | 版本串 | abogki |
|:----|:------|:------:|
| Stock 官方 | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` | ✅ |
| schqiushui 144 | `6.6.144-android15-8-g4de260df0fc2-abogki500782043-4k` | ✅ |
| 我们的 OKI 构建 | `6.6.118-android15-8-o-ge1b346b6b4f4-4k` | ❌ 缺 |

**`abogki500782043` = OnePlus OKI ABI 代际标记**
- 作用: vendor_boot 中的模块检查此标记，决定是否加载
- 来源: OnePlus 内部 CI 系统注入，**未开源**
- 远程 OnePlusOSS 公开仓库不含此 tag
- `git tag -f abogki500782043 HEAD` **无效** — 标准 `setlocalversion` 不识别
- `scripts/setlocalversion` 中 `try_tag()` 函数只识别标准内核 tag（如 `v6.6`），不识别 `abogki*`

## 基带问题的根因
- 症状: 刷 Vanilla OKI AK3 后基带/WiFi/蓝牙失效
- 原因: AK3 只刷了 `Image`（boot 分区内核），没刷 `vendor_boot.img`
  - vendor_boot 中 75 个 .ko 模块（WiFi/蓝牙/基带驱动）vermagic 不匹配 → 拒绝加载
- 修复方案: 将 `vendor_boot.img` 也放进 AK3 zip，调用 `flash_generic vendor_boot`

## AnyKernel3 + vendor_boot 方案

参考 `osm0sis/AnyKernel3` 官方文档 + schqiushui 的 `ak3-core.sh`:

**方法一：`flash_generic vendor_boot`（推荐）**
```bash
split_boot    # 拆 boot 分区（跳过 ramdisk）
flash_boot    # 刷入新内核 Image
# 然后：
flash_generic vendor_boot   # 自动定位 vendor_boot 分区并刷入
```
- `ak3-core.sh` 已内置 `flash_generic` 函数
- 自动处理: 分区定位、A/B 槽、AVB/dm-verity、LVM/超级分区
- 需要的工具（`httools_static`、`lptools_static`）已在参考 AK3 中

**方法二：`write_boot`（自动包含 vendor_boot）**
```bash
write_boot   # 内部已调用 flash_generic vendor_boot
```
- 适用于无 init_boot 的设备
- 但我们的设备有 init_boot，所以用 `split_boot + flash_boot`

**方法三：`reset_ak` 后切换 BLOCK**
```bash
dump_boot; write_boot;           # 刷 boot
reset_ak;                         # 清理环境
BLOCK=vendor_boot; flash_generic vendor_boot;  # 刷 vendor_boot
```

### 正确改动位置
`anykernel.sh` 中 `if` 分支（init_boot 存在时）：
```bash
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" ... ]; then
    split_boot
    flash_boot
    # ← 在此处插入 flash_generic vendor_boot
    flash_generic vendor_boot
fi
```
注意: `else` 分支的 `write_boot` **已内部包含** `flash_generic vendor_boot`，不可重复添加。

## OKI 构建系统

### 目录结构
- `kernel_platform/common` — GKI 通用内核源码
- `kernel_platform/msm-kernel` — 高通平台代码
- `kernel_platform/prebuilts/` — Android clang r510928、bazel 7.1.1
- `kernel_platform/oplus/build/` — OPlus 构建脚本入口

### 构建命令
```bash
cd /home/axymorrsen/op13-oki
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

### 产物路径
- `$OKI/out/dist/Image` — ~36MB，ARM64 4K
- `$OKI/out/dist/vendor_boot.img` — ~40MB，含 75+ vendor 模块
- `$OKI/out/dist/boot.img` — ~96MB，完整 boot 镜像

### 已知问题
1. **增量缓存依赖**: `prepare_vendor.sh` 设计为增量构建，依赖 `kernel_platform/out/msm-kernel-sun-perf/dist/` 中前一次产物
2. **浅同步缺失文件**: `--depth=1 -c --no-tags` 导致 `gki_system_dlkm_modules` 等文件缺失
3. **Bazel 权限**: `output_user_root` 曾被 root 占用 → 需 `chown` 给 `axymorrsen`
4. **`mktemp` 目录**: `out/target/product/sun/` 必须存在

## 社区仓库研究

### schqiushui（能刷的 AK3 作者）
- 仓库: `schqiushui/android_kernel_oneplus_sm8750` @ `kernel.lnx.6.6.r1-rel`（6.6.118）
- 仓库: `schqiushui/android_kernel_common_oneplus_sm8750` @ `android15-6.6`（6.6.111）
- 版本串: `6.6.144-android15-8-g4de260df0fc2-abogki500782043-4k`
- AK3 方案: `block=boot; split_boot; flash_boot`（不含 vendor_boot，因为他的内核带 `abogki` tag，与 stock vendor 模块兼容）
- 工具链: Android clang r510928
- 其内核源码无特殊 `localversion` 文件，`abogki` tag 可能来自 CI 构建脚本

### Numbersf/Action-Build
- 仓库: `Numbersf/Action-Build` @ `SukiSU-Ultra`
- 全自动化 CI/CD 方案
- 自动处理:
  - 版本串替换（移除默认后缀，改为可读标识）
  - AK3 文件名动态生成
  - `vendor_boot` 需求自动检测和注入
- 动态 manifest: `Numbersf/kernel_manifest` @ `oneplus/sm8750`

### 关于 abogki 的结论
- OnePlus 内部 CI 在构建时注入 `abogki` tag
- 标准 `setlocalversion` 不识别此 tag
- 无法通过本地 git tag 复现
- 替代方案: 通过 `CONFIG_LOCALVERSION=-abogki500782043` 或 `localversion-abogki` 文件注入
- 或者: 直接不依赖 abogki，用 Image + vendor_boot.img 打包同刷

## 可用脚本

| 脚本 | 功能 |
|:----|:----|
| `scripts/wsl_build_oki.sh` | OKI 内核一键构建 + 打包（clean/full/image 三种模式） |
| `scripts/flash_with_vendor_boot.sh` | fastboot 同时刷 boot + vendor_boot |
| `scripts/pack_vendor_boot_ak3.sh` | 引导至 fastboot 刷入方案 |
| `scripts/integrate_resusfs.sh` | ReSukiSU + SusFS 集成脚本 |

### `scripts/wsl_build_oki.sh` 用法
```bash
# 在 WSL 内执行:
wsl -d arch-linux-current
bash /mnt/d/OnePlus13-kernel/scripts/wsl_build_oki.sh clean   # 完整重建
bash /mnt/d/OnePlus13-kernel/scripts/wsl_build_oki.sh full    # 增量重建
bash /mnt/d/OnePlus13-kernel/scripts/wsl_build_oki.sh image   # 仅打包现有产物
```

## 当前策略（2026-07-24 确定）

1. **不再依赖 abogki tag** — 这是 OnePlus 内部机制，无法在公开源码复现
2. **AK3 包含 vendor_boot.img** — `flash_generic vendor_boot` 解决基带问题
3. **使用第一次成功构建的产物** — `$OKI/out/dist/Image` + `vendor_boot.img` 同一套编译，vermagic 完全匹配
4. **ReSukiSU 后续加入** — 先验证 vanilla 能开机，再通过 `integrate_resusfs.sh` 集成

## WSL 配置
- 发行版: `arch-linux-current`
- CPU: 14核 i9-13900H
- 内存: 23G
- 磁盘: ~920G 可用
- `/etc/wsl.conf`: `[interop]` + `[user]`（已移除无效的 `[wsl2]` 区段）
- 工具链: Android clang r510928（预编译）+ Bazel 7.1.1（预编译）
- OKI 工作区: 共 30G（kernel_platform 源码 + prebuilts + .repo）

## 项目结构
- `build.sh` — 初始构建主脚本（已弃用，走 OKI 路线）
- `scripts/` — WSL 构建/修复/打包脚本
- `configs/base_defconfig_fragment` — 旧 CONFIG 碎片
- `.github/workflows/build.yml` — CI（不可用，WSL 更可靠）
- `tests/` — 静态/单元/运行时测试
- `releases/` — AK3 产物 + restore 救砖
- `.work/memory/` — 会话记忆
