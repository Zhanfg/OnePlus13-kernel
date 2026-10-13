# OnePlus 13（PJZ110 / sun）Fusion V2 完整 OKI → AK3

## 2026-10-14 入口

GitHub Actions 手动工作流：`.github/workflows/build-op13-fusion-ak3.yml`。
该入口调用仍在开发分支 `integration/resukisu-susfs23-kpatchnext` 中的持久化完整构建工作流。不会自动合并/刷入内核。

### Runner 配置

在 GitHub 仓库 Settings → Actions → Runners 注册专用 Linux x86_64 自托管 Runner，并增加标签 **`op13-oki`**。
推荐至少 8 vCPU / 16 GiB RAM / 150 GiB SSD；构建工作流强制检查同一文件系统至少 **80 GiB** 可用空间，低于则立即退出。
使用隔离的、可重建的 Runner；不要在不可信 PR 上运行带凭据的自托管 Runner。

普通 GitHub Ubuntu Runner 在 2026-10-01 的 Actions 运行 `36840298287` 中执行完整 OKI 同步后耗尽了磁盘空间；日志显示克隆 ReSukiSU 时 `No space left on device`。因此**未配置足够存储空间的 Runner 不应重复点击构建**。

### 手动开始

1. 先确保 `op13-oki` Runner 在线。
2. 打开 Actions → **Build OnePlus 13 Fusion V2 AK3 candidate** → Run workflow。
3. 成功时进入本次 Run 的 Artifacts，下载 `fusion-v2-self-hosted-candidate-*`。
4. 候选档案包含原始 Image、经 KPatch-Next 处理的 Image、AK3 ZIP、SHA256、配置、manifest、构建记录。
5. 如果失败，下载 `fusion-v2-self-hosted-failure-*` 诊断，不要直接刷机。

### 可选功能怎么合并

- 官方完整 OKI `6.6.118` **基线锁定**，源 manifest 固定为 `manifests/oneplus_13_b_20261013_pinned.xml`。
- Root 路线：ReSukiSU 是唯一 Root Core；SUSFS 作为独立内核层；KPatch-Next 是构建后 Image 层。
- 每个新功能独立提交/PR、固定源 SHA、单独 Kconfig fragment 和编译回归；不得覆盖官方 vendor hooks 或 ABI/KMI 文件。
- 第一轮只做标准 Fusion V2，可选 I/O、调度、网络优化在基础版本通过后逐个引入。
- SUSFS 后续优先从自己的 `Zhanfg/susfs4ksu` 审计分支维护，但**不得在没有 ReSukiSU 兼容与 Android 真机验证前直接替换当前 pinned SUSFS**。

### Android 17 / 尾号 .103 特别限制

用户报告当前设备运行 Android 17 / 6.6.118，完整构建号及 vendor ABI 对照尚未取得。
本工具链固定的公开 OnePlusOSS 对应 `PJZ110_16.0.9.401`，不是针对 Android 17 `.103` 的完整 OEM 发布源码。

生成的 AK3 仅是 **Experimental candidate / DO NOT FLASH**。
在完成当前固件 boot/vendor_boot/vendor_dlkm、vermagic、KMI/符号表兼容性和真机可恢复测试前，
**不得作为正式日用刷机包**，也不得直接修改手机分区。编译成功与可刷写是不同验收等级。

### 状态

- 官方源码固定：已完成
- 多源 OKI Fusion V2 脚本：已有待验证集成 PR
- 2026-10-01 失败原因：普通 Actions Runner 磁盘耗尽
- 持久化 Runner 的磁盘门槛与 AK3 自动打包：已加入开发分支
- 完整构建与真机验收：尚未完成
