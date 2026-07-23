# 一加13 内核构建项目 - 长期记忆

## 项目概况
- 路径: D:\OnePlus13-kernel（仓库/规格/AK3 模板）
- WSL 实际构建: `/home/axymorrsen/op13-kernel/`（src + patches + logs）
- 目标: 一加13 (sun/SM8750) + ColorOS 16 国行自定义内核
- 源码基准: OnePlusOSS `oneplus/sm8750_b_16.0.0_oneplus_13` (6.6.89 / PJZ110 CN)
- 产物: 仅 AnyKernel3 (AK3) zip

## 默认策略 (规格§3, 不可更改)
- 调度=wait（HMBIRD 可选）, TCP=bbr3, qdisc=fq, ZRAM=lz4
- BBG=默认开可关, KPM=默认不应用, KALLSYMS+ALL=始终启用
- **生产构建关闭 KASAN**

## 关键约束
- 不修改基带镜像
- 杜比不进内核 (用户态KSU模块)
- 保留官方: 充电/信号/指纹/相机/音频
- AK3刷写路径: init_boot (split_boot/flash_boot)
- 音量键含义全程固定: +=第一项/推荐, -=第二项/备选

## 真机基线 (2026-07-20 救砖后实测，以用户为准)
- 机型: PJZ110 国行 · `PJZ110_16.0.9.401(CN01)`
- 官方 boot 内核: `6.6.118-android15-9-g690101101069`
- 用户能刷自定义 AK3: `6.6.144-android15-8-g4de260df0fc2`（schqiushui 系）
- **禁止再刷本仓库旧 6.6.89 包**（会卡 Logo+黄字）
- 救砖: `releases/restore/boot.img`（16.0.9.401 stock）

## 当前构建基线（用户确认：破星）
- 仓库: brokestar233/android_kernel_common_oneplus_sm8750
- 分支: `6.6-final`（主）/ `dev` 可跟进
- 版本: **6.6.126** + BORE 等
- 本地路径: `/home/axymorrsen/op13-kernel/brokestar-6.6`
- 打包对齐: 可用 AK3 的 `block=boot` + split_boot/flash_boot
- 文档: `releases/BASELINE_BROKESTAR.md`、`releases/BASELINE_CURRENT.txt`

## 旧产物 (6.6.89 线，已废弃)
- 曾合入 ReSukiSU/SuSFS/HMBIRD 等，基线错误


## 踩坑备忘
- HMBIRD 补丁易残留 scx_* → 需改 hmbird_* 并补 cgroup deadline 函数
- ReSukiSU/BBG 必须保持 git 父目录布局；禁用 fetch --unshallow
- BBG: CONFIG_BBG + LSM 含 baseband_guard + 完整 tracing/

## 项目结构
- build.sh: 构建主脚本（本地/CI 参考）
- scripts/: patch + WSL 修复/打包脚本
- configs/base_defconfig_fragment: CONFIG碎片
- anykernel/anykernel.sh: AK3刷写包(7题交互菜单)
- .github/workflows/build.yml: CI（曾用 stub 路径，WSL 全量编译更可靠）
- tests/: 静态测试+单元测试+运行时验收
