# Fusion V2 上游回馈规则

本项目在融合 OnePlus OSS、ReSukiSU、SUSFS 与 KPatch-Next 时，发现通用问题应优先整理成最小修复并回馈对应上游。

## 归属规则

### OnePlusOSS
仅提交能够在干净 OnePlus 官方基线上复现的问题，例如：
- 编译错误；
- Kconfig/Kleaf/ABI 定义错误；
- 设备树或 vendor hook 的确定性错误；
- 官方 common 与 msm-kernel/modules 明确不匹配。

### ReSukiSU
仅提交脱离 OnePlus 私有改动后仍可复现的问题，例如：
- 6.6 通用 Hook/LSM/manager 兼容错误；
- 与当前 SUSFS API 的通用适配错误；
- ReSukiSU 自身 build/Kconfig/接口错误。

### SUSFS
仅提交 SUSFS 2.3.x 自身在 6.6 上的通用问题，例如：
- 公开 patch 与当前 6.6 API 明确不匹配；
- SUSFS 自身死锁/UAF/内存泄漏/Kconfig 依赖错误；
- 与 root core 无关的内核侧回归。

### KPatch-Next
仅提交 KPatch-Next 自身可复现的问题，例如：
- Image parser/patcher 对标准 arm64 GKI 误判；
- kpimg/kptools 通用 build 或 runtime 错误；
- stop_machine、符号解析或 KPM 生命周期问题。

## 不向上游提交

以下问题属于 Fusion 自己：
- ReSukiSU + SUSFS + OnePlus 三方组合冲突；
- 我们自己选择的 CONFIG 默认值；
- AnyKernel3、CI、打包、版本命名错误；
- 只在 PJZ110/ColorOS 特定版本出现、且无法证明是上游通用错误的问题；
- 因补丁应用顺序错误导致的问题。

## 提交格式

每个上游问题必须具备：
1. 干净基线 SHA；
2. 最小复现步骤；
3. 预期行为与实际行为；
4. 最小补丁；
5. 编译/运行验证；
6. 明确说明 OnePlus/Fusion 私有改动是否参与复现。

禁止把整套 Fusion diff 直接推给上游。
