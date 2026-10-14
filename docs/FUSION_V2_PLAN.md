# OnePlus 13 Fusion Kernel V2

## 核心架构

- Root Core: **ReSukiSU**
- 隐藏层: **SUSFS 2.3.x**
- KPM / KernelPatch 支持: **KPatch-Next**
- 不切换到 KernelSU Next 作为 Root Core

## 集成原则

1. 继续使用现有 OnePlus 13 / sun / SM8750 官方同步基线。
2. ReSukiSU 保持唯一 Root Core。
3. SUSFS 升级到 2.3.x，并单独验证与 ReSukiSU 的 AVC / mount / zygote 相关协调。
4. KPatch-Next 作为 KPM 支持层接入，不替代 ReSukiSU。
5. KPM 不再采用旧版“刷机时临时二次 patch”的混乱模式，改为构建阶段固定、可审计的 KPatch-Next 集成。
6. 每个上游来源固定 commit，并记录来源与 digest。

## 首发目标

- HMBIRD / slim_walt / EEVDF
- ReSukiSU
- SUSFS 2.3.x
- KPatch-Next / KPM
- TTL / IPv6 HL
- namespaces
- NTSYNC
- BBR / FQ / FQ_CODEL
- ADIOS（先编译，可不设默认）

## 暂缓

- Baseband Guard
- Lindroid EVDI
- 额外激进电源 / 温控补丁

## 上游回推

若发现 OnePlusOSS、ReSukiSU、SUSFS、KPatch-Next 本身存在通用错误，拆成最小复现和独立提交后回推对应上游。仅因本项目组合产生的冲突保留在本仓库，不伪装成上游缺陷。
