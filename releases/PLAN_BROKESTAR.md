# 破星基线 — 自主决策方案

## 决策结论（2026-07-20）

| 项 | 决定 |
|----|------|
| 源码 | **破星** upstream；开发在 **fork** `Zhanfg/android_kernel_common_oneplus_sm8750` |
| 分支 | 主用 **`6.6-final`（6.6.126）**；`dev` 仅作 zram 等热修参考，不默认整支跟 |
| 推送 | 只推 fork；不同步改动到破星 upstream |
| 产物 | 仅 **GKI `Image` + 标准 AK3**（与能刷包一致） |
| 刷写 | `block=boot` + 有 init_boot 时 `split_boot`/`flash_boot` |
| 工具链 | 优先 **系统 clang/LLVM make 出 Image**（快、先验证能开机）；完整 Kleaf/bazel 作备选 |
| 功能节奏 | **分阶段**，禁止一次叠齐所有补丁 |

## 推理要点

1. **真机证明「比官方新」可开机**：官方 118，能刷包 144 → 126 落在中间，版本风险可接受。  
2. **精确官方 118-9 源码不存在** → 纠结 hash 无意义；要的是可维护、较新、能编 Image。  
3. **破星提交活跃**（7 月）且含 BORE；`6.6-final` 比 `dev` 更适合当「发布基线」，避免 dev 半成品。  
4. **上次翻车主因是 6.6.89 + 错误基线**，不是「AK3 格式」本身；打包必须抄能刷包。  
5. **common-only 足够做 Image 替换**（能刷 AK3 也只带 Image）；先不强制整仓 modules。  
6. **一次合满 ReSukiSU+SuSFS+HMBIRD+… 无法定位锅** → 必须：干净 Image 能开 → 再合 Root → 再合其它。

## 分阶段里程碑

### M1 — 干净破星 Image 能开机
- [x] 编出 `Image` + AK3（树内 BORE/HMBIRD）
- [ ] **真机验证**
- 产物：`v6.6.126-OnePlus13-sun-AK3-BROKESTAR-M1-VANILLA-20260721-0003.zip`

### M2 — 合入 ReSukiSU + SuSFS
- [x] symlink 接入 ReSukiSU；SuSFS GKI 6.6 补丁；编包
- [ ] **真机验证 Root/Manager**
- 产物：`v6.6.126-OnePlus13-sun-AK3-BROKESTAR-M2-RESUKISU-20260721-0020.zip`

### M3 — 全功能
- [x] BBG（CONFIG_LSM 含 baseband_guard）+ Re:Kernel + BBR/FQ/CAKE/IP_SET + NTSYNC
- [ ] **真机验证**
- 产物：`v6.6.126-OnePlus13-sun-AK3-BROKESTAR-M3-FULL-20260721-0038.zip`
- 注：树内无独立 BBR3 源码，默认 **BBR**（非 cubic）；HMBIRD 树内已有未再叠大补丁

### 明确不做（本阶段）
- 不再用 6.6.89 任何产物  
- 不在未开机验证前合入大补丁全家桶  
- 不把 init_boot 当内核 Image 目标分区  

## 风险与接受

| 风险 | 接受方式 |
|------|----------|
| 126 ≠ 官方 118 | 接受；以能开机为准 |
| BORE 默认行为 | 先保留树内默认，M1 不关 BORE |
| clang 版本非 r510928 | 先本机 clang 试；失败再锁 Android clang |
| GKI ABI/模块 | 仅换 Image；异常再查 vendor_dlkm |

## 本地路径

- 源码：`/home/axymorrsen/op13-kernel/brokestar-6.6`
- fork：https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750
- 成品：`D:\OnePlus13-kernel\releases\`
- 参考 AK3：`releases/AK3_6_6_144_..._comm.zip`
- 救砖：`releases/restore/boot.img`
- 注意：WSL 里若 `http_proxy=127.0.0.1:7890` 失效，git 需 `unset` 代理后再 fetch
