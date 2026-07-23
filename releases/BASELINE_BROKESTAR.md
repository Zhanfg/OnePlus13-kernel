# 构建基线：破星 brokestar233（用户确认选用）

日期：2026-07-20  
**用户最终决定：用破星（brokestar233）。**

依据：
- 公开区无精确 `6.6.118-android15-9-g6901…` 源码
- 按 **git 提交活跃度**：破星 `dev` / `6.6-final` 明显新于 schqiushui 118 分支
- 内核版本 **6.6.126**，介于官方 118 与已验证可刷 144 之间
- 真机曾跑通 6.6.144，说明「略新于官方的 GKI」路线可行

## 真机

- 系统：`PJZ110_16.0.9.401(CN01)`
- 官方 boot：`6.6.118-android15-9-g690101101069`
- 已验证可刷自定义：`6.6.144-android15-8-g4de260df0fc2`（schqiushui AK3）

## 选定源码

| 项 | 值 |
|----|-----|
| **开发 fork** | https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750 |
| upstream（只读同步） | https://github.com/brokestar233/android_kernel_common_oneplus_sm8750 |
| 分支 | `6.6-final`（主）/ `dev` 跟进 |
| 版本 | **6.6.126** |
| 类型 | Android Common GKI（含 BORE 等魔改） |
| 子模块 | `drivers/starkernel` → StarKernel |
| 本地 | `/home/axymorrsen/op13-kernel/brokestar-6.6` |
| remote 约定 | `origin` = fork（可 push）；`upstream` = 破星（只 fetch，不 push） |

## 已知差异（接受）

- 非官方精确 `g690101…`，也非 118，而是 **126**
- 比官方新 8 个小版本；真机曾跑通 144，说明「略新 GKI」路线可行
- 仅为 **common**，成品以 **替换 boot 内 Image** 为主（对齐可用 AK3 做法）

## 打包参考

- 可用包：`AK3_6_6_144_..._comm.zip`
- `block=boot` + `is_slot_device=1` + 有 init_boot 时 `split_boot`/`flash_boot`

## 禁止

- 再使用本仓库旧 **6.6.89** 产物刷机
