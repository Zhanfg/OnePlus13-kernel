# 社区仓库检索报告（方案 A：对齐 6.6.118）

检索目标：与真机 `6.6.118-android15-9-g690101101069` / `PJZ110_16.0.9.401(CN01)` 接近的 **sun/sm8750** 内核源码（不限 OnePlusOSS）。

## 真机基线

| 项 | 值 |
|----|-----|
| 系统 | PJZ110_16.0.9.401(CN01) |
| uname -r | 6.6.118-android15-9-g690101101069 |
| stock zip 内 boot.img | 6.6.118-android15-8-g93e223c276e7（同主版本 118，子串 8≠9） |

## 检索结果摘要

### 1. 最有价值：schqiushui（你能刷的 AK3 作者）

| 仓库 | 分支 | Makefile 版本 | 备注 |
|------|------|---------------|------|
| [schqiushui/android_kernel_oneplus_sm8750](https://github.com/schqiushui/android_kernel_oneplus_sm8750) | **`kernel.lnx.6.6.r1-rel`** | **6.6.118** | **命中主版本** |
| 同上 | clo-rebase | 6.6.89 | 偏旧 |
| 同上 | clo-base | 6.6.66 | 更旧 |
| [schqiushui/android_kernel_common_oneplus_sm8750](https://github.com/schqiushui/android_kernel_common_oneplus_sm8750) | android15-6.6 | 6.6.111 | 接近 118 但未到 |
| 同上 | clo-rebase / v_16.0.0_oneplus_13 | 6.6.89 | ColorOS16 早期 |
| [schqiushui/kernel_manifest](https://github.com/schqiushui/kernel_manifest) `oneplus/sm8750` | oneplus_sm8750_b.xml 等 | — | 完整 repo 同步清单（common+msm+modules+CLO） |
| 可用 AK3 作者串 | Image 内 `schqiushui@github.com` / emira@Lotus | **6.6.144** | 成品核比 118 新，源码分支未必以 144 公开 |

**推荐基线树：**  
`schqiushui/android_kernel_oneplus_sm8750` @ **`kernel.lnx.6.6.r1-rel`（6.6.118）**  
配合其 `kernel_manifest` + common/modules 做完整 GKI/Kleaf 构建（与社区 AK3 同作者体系）。

### 2. 其它社区

| 仓库 | 版本 | 评价 |
|------|------|------|
| LineageOS/android_kernel_oneplus_sm8750 @ lineage-23.2 | **6.6.139** | 新于官方 118，Lineage 用，可作备选 |
| brokestar233/android_kernel_common_oneplus_sm8750 @ 6.6-final | **6.6.126** | 有 BORE 等魔改，非原样 118 |
| AOSP kernel/common tag `android15-6.6.118_r00` | **6.6.118** | 纯 Google GKI，无一加 vendor |
| OnePlusOSS common/oneplus_13 | 6.6.89 / 16.0.7.201 | 公开仍旧，不够 16.0.9.401 |
| WildKernels/OnePlus_KernelSU_SUSFS | 构建脚本仓库 | 无单独 6.6.118 源码树 |

### 3. 未找到（公开）

- 精确 commit **`g690101101069`** 的完整一加树  
- 标注 **16.0.9.401** 的完整开源同步  
- 与可用 AK3 完全一致的 **6.6.144-android15-8-g4de260df0fc2** 源码分支名（成品有，源码未以该 tag 明示）

## 方案 A 可执行路径（社区）

1. **主推**：以 **schqiushui `kernel.lnx.6.6.r1-rel`（6.6.118）** + manifest 同步 common/modules，Android/Kleaf 方式编 Image。  
2. **打包**：照抄可用 AK3 的 `anykernel.sh`（`block=boot`、init_boot 判断、`patch_vbmeta_flag=0` 等）。  
3. **补丁**：ReSukiSU / SuSFS 等在 6.6.118 上重合（不能直接用 6.6.89 产物）。  
4. **预期**：`uname -r` 应接近 `6.6.118-...`，而非 6.6.89；与真机 android15-9 子串可能仍有差异（官方未开源该精确 commit）。

## 结论

社区里**已经有 6.6.118 的 sm8750 相关树**（schqiushui），不必死等 OnePlusOSS。  
下一步应 **同步 schqiushui 6.6.118 线并建立构建**，而不是再动 6.6.89。
