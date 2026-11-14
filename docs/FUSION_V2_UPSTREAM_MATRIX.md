# Fusion V2 上游兼容矩阵

## 固定来源

| 层 | 上游 | 固定版本 |
|---|---|---|
| Root Core | `ReSukiSU/ReSukiSU` | `f7829ddf548a18b851d653feb76b4a569b8fd2a4` |
| SUSFS | `simonpunk/susfs4ksu` `gki-android15-6.6` | `eba2a88a5ba303e3d79d08e0717b956e9cf784a1` |
| KPM Runtime | `KernelSU-Next/KPatch-Next` | `456744b29efb9989445463ab29e368fa59a103c4` |

发布构建禁止直接跟踪 `main` 或其他可变 branch。

## 为什么 ReSukiSU 不再内建 KPM

ReSukiSU 上游 PR #226 `Remove KPM Support` 已合并。其维护方向已经明确把 KPM 从 ReSukiSU 下游中移除，避免继续维护一套容易与 Root Core、Hook 路径耦合的 KPM 实现。

Fusion V2 因此采用：

```text
ReSukiSU = Root Core
KPatch-Next = 独立 KernelPatch/KPM Runtime
```

不会把旧 KPM 代码重新塞回 ReSukiSU。

## ReSukiSU 与 KPatch-Next 的共存基础

ReSukiSU 历史提交 `7c7a5d1fc286e9a6e1ee18bb0efd1d92f592597b` 已明确把 ksud execve 处理迁到 syscall hook manager，提交说明直接指出目标之一是减少与其他 kernel module（例如 KPatch-Next）的冲突。

当前固定的 `f7829ddf...` 晚于该提交，因此已经包含这条架构调整。

## SUSFS 2.2.0 -> 2.3.0 不是只改版本号

基准：

- 2.2.0 milestone: `e7b28525f69ca5864bed7db51f77663f5adfe218`
- 2.3.0 milestone: `eba2a88a5ba303e3d79d08e0717b956e9cf784a1`

需要重点验证的实际变化：

1. 新增 `TIF_PROC_NO_SU`，sucompat 不再复用 `TIF_PROC_UMOUNTED` 表示无 Root 进程。
2. 新增 `TIF_PROC_UMOUNTED_FOR_ZYGOTE_NEXT`。
3. 增加 zygote_next 的 mount 隐藏处理，包含 `__lookup_mnt()` 临时兼容路径。
4. `ksu_handle_faccessat()` / `ksu_handle_stat()` 接口与路径处理优化，减少额外 `copy_from_user()`。
5. OPEN_REDIRECT 从较高层的 `do_sys_openat2()` 路径进一步下沉到 `path_openat()` / `do_tmpfile()` / `do_o_path()`。
6. OPEN_REDIRECT 使用正确的 SRCU 域进行同步，修复潜在 UAF。
7. 修复 OPEN_REDIRECT 可能的内存泄漏与死锁。
8. `hide_sus_mnts_for_non_su_procs` 改为 static key，关闭时降低热路径开销。
9. Root 权限在 Manager 中撤销后，修复旧进程仍可能继续取得 Root session 的逻辑问题。
10. 修复 input hook 原子上下文中关闭 static key 可能触发 kernel warning 的问题。
11. 多处字符串复制改用 `strscpy` / `memcpy`，移除旧 `strncpy` 路径。

因此 Fusion V2 的 2.3.0 验证不能只检查：

```text
SUSFS_VERSION == v2.3.0
```

还必须检查上述 Hook / flag / SRCU / zygote_next 行为是否真实存在。

## ReSukiSU 对新 SUSFS 的适配

ReSukiSU PR #361 / commit `03b60f260cce36f23efbd26c9c334edfdc9ce7eb` 已完成一轮关键适配，包括：

- `susfs_is_current_proc_no_su` 路径；
- 新的 `ksu_handle_stat/faccessat` 函数签名；
- zygote_next 处理。

随后 commit `4a3785025a920e4f52584f14c663eea4850dc919` 又处理了 input hook 中可能在原子上下文执行 sleepable 操作的问题。

固定的 `f7829ddf...` 已包含这些提交。

## 为什么不应用 SUSFS 的官方 KernelSU patch

SUSFS 仓库中的：

```text
kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch
```

目标是官方 KernelSU 源码布局和 Hook 体系。

Fusion V2 使用 ReSukiSU。ReSukiSU 自己已经维护：

- `CONFIG_KSU_SUSFS` Hook choice；
- sucompat；
- setuid / zygote / zygote_next；
- syscall hook manager；
- SELinux / mount 协调。

因此 Fusion V2 只应用 SUSFS 的 **common/kernel-side patch**，不直接把官方 KernelSU patch 套到 ReSukiSU 上。若两边出现接口差异，单独形成 `ReSukiSU <-> SUSFS 2.3` 适配 commit。

## KPatch-Next 的位置

KPatch-Next 不作为普通源码目录加入 common。

正确顺序：

```text
完整 OnePlus OKI 源码
  -> ReSukiSU + SUSFS
  -> sun perf 编译
  -> 原始 Image
  -> kptools -p -i Image -k kpimg -o Image.kpatch-next
  -> 校验 patch metadata / SHA256
  -> AnyKernel3
```

KPatch-Next 上游说明要求 `CONFIG_KALLSYMS=y`；Fusion V2 同时保留 `CONFIG_KALLSYMS_ALL=y`，提高符号解析兼容性。

## 上游问题归属

### 可以回推上游

- 干净 OnePlus OSS 上即可复现的 OnePlus bug；
- 干净 ReSukiSU + 标准 6.6 环境即可复现的 ReSukiSU bug；
- 标准 Android 15 6.6 上即可复现的 SUSFS 2.3 bug；
- 任意符合 KPatch-Next 支持条件的标准 arm64 Image 上即可复现的 KPatch-Next bug。

### 只留在 Fusion V2

- ReSukiSU 与 SUSFS 都正常，但两者组合在 OnePlus 13 上产生的适配冲突；
- HMBIRD / OPlus vendor hooks 导致的特定冲突；
- 本项目的 config、打包、CI、默认策略问题；
- 只为 OnePlus 13 / ColorOS 做的兼容修改。
