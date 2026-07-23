# M1/M2/M3 全部失败（反复重启）分析

日期：2026-07-21  
现象：三个包均无法开机，失败时**反复重启**（bootloop）。  
含义：**M1 干净包也挂** → 根因在「破星基线 + 本机编译方式」，**不是** ReSukiSU / BBG / 打包格式。

## 对照：能刷包 vs 我们的 M1

能刷参考：`AK3_6_6_144_..._comm.zip`  
`Linux version 6.6.144-android15-8-g4de260df0fc2-...-4k`  
工具链：**Android clang 18.0.0 (r510928)** + LLD 18

我们的 M1：  
`Linux version 6.6.126-OKI-Brokestar`  
工具链：**Ubuntu clang 21.1.8** + LLD 21

| 配置/特性 | 能刷 6.6.144 | 我们的 M1 | 风险 |
|-----------|--------------|-----------|------|
| ThinLTO (`CONFIG_LTO_CLANG_THIN`) | **关** | **开** | 高：codegen/CFI 行为不同 |
| LLVM Polly | **关** | **开**（Makefile 注入大量 `-mllvm -polly`） | 高：易错误优化 |
| `CONFIG_ARCH_ORYON` → `-mcpu=oryon-1` | **关** | **开** | 高：与官方 GKI 不一致 |
| `CONFIG_SCHED_BORE` | **关** | **开** | 中：调度路径差异 |
| `CONFIG_HMBIRD_SCHED` | 开 | 开 | 两边一致 |
| `CONFIG_CFI_CLANG` | 开 | 开 | 需匹配工具链 |
| Image 体积 | ~36MB | ~30MB | 侧面说明优化/裁剪不同 |
| 打包 AK3 | `block=boot` | 同模板 | 低：格式不是主因 |

## 推断

反复重启 ≈ 内核早期起来后 panic 再被 watchdog/重启策略拉起，常见于：

1. **错误机器码**（Polly + 过新 clang + oryon 调度）  
2. **CFI / LTO** 与 vendor 侧期望不一致  
3. 调度魔改（BORE）在部分机型上的边界问题（优先级低于 1/2）

**不是**「版本 126 一定不能开」——你机上 144 能开已证明略新于官方 118 的 GKI 路线可行；是**这棵树默认的性能补丁 + 错误工具链**把 Image 编坏了。

## 已采取的下一步：M4-SAFE

脚本：`scripts/wsl_build_brokestar_m4_safe.sh`

在破星 6.6-final 干净树上：

- 关 Polly / ARCH_ORYON / BORE / ThinLTO  
- 保留 HMBIRD（与能刷包一致）  
- `LOCALVERSION=-4k-safe`  
- 仍用系统 clang（本机尚无 r510928 时的最小修复）

若 **M4-SAFE 能开**：再逐步加回 Root（M2）和功能（M3），并评估换 Android clang。  
若 **M4-SAFE 仍挂**：必须上 **Android clang r510928**，或换与能刷包同源的构建树/流程。

## 救砖

```text
fastboot flash boot D:\OnePlus13-kernel\releases\restore\boot.img
```

（需要时可同时恢复 `init_boot` / `dtbo`）

## 若方便补充的信息

- 失败时是 **Logo 后重启** 还是 **振动后黑屏重启**  
- 能否进 fastboot / recovery  
- 若有 `last_kmsg` / pstore / 串口 log，可精确到 panic 函数  
