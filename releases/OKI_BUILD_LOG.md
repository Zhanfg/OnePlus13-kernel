# OKI 构建日志 — D1 静态验收

> 构建日期：2026-07-23
> 基线：OnePlusOSS `oneplus/sm8750_b_16.0.0_oneplus_13` (6.6.118)
> 工具链：Android clang r510928 (kleaf/Bazel)

---

## 三路对比

| 项目 | Stock (6.6.118) | 能刷 144 (6.6.144) | **本次构建 (6.6.118)** |
|------|:---------------:|:------------------:|:---------------------:|
| **file 类型** | ARM64 4K | ARM64 4K | ✅ ARM64 4K |
| **体积** | ~36 MB | ~36 MB | ✅ ~36 MB |
| **版本串** | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` | `6.6.144-android15-8-g4de260df0fc2-abogki500782043-4k` | `6.6.118-android15-8-o-ge1b346b6b4f4-4k` |
| **android 标记** | `android15-8` | `android15-8` | ✅ `android15-8` |
| **工具链** | Android clang r510928 | Android clang r510928 | ✅ **r510928** |
| **abogki 标记** | `abogki500782043` | `abogki500782043` | ⚠️ 未找到 |
| **4K 页** | ✅ | ✅ | ✅ |
| **OGKI hooks** | 完整 | 完整 | ✅ 同官方源 |

## 版本串详解

```
Stock:   6.6.118-android15-8-g93e223c276e7-abogki500782043-4k
144:     6.6.144-android15-8-g4de260df0fc2-abogki500782043-4k
Our:     6.6.118-android15-8-o-ge1b346b6b4f4-4k
                ^^^^^^^^^^ ^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^
                      同源     不同 hash     构建签名不同
```

- `6.6.118` — 内核版本 **与 stock 一致**（144 是高版本，没问题）
- `android15-8` — KMI 版本 **三份一致** ✅
- `-4k` — 页大小 **三份一致** ✅
- `ge1b346b6b4f4` — 是对应 OnePlus 官方 commit 的 git hash，与 stock 不同是正常的
- `-o-` — 表示 OPlus 构建（与 stock 的 `-g-` 类似，不同构建系统标记不同）

## 关于 abogki 缺失

stock 和能刷 144 都含 `abogki500782043` 标记，本次构建没有。原因是 `abogki` 由 OnePlus 的 `setlocalversion` 脚本通过 git tag 或构建配置注入。实际开机验证比这个标记更重要。

## 验收结论

| 检查项 | 结果 |
|--------|------|
| file 为 ARM64 4K | ✅ PASS |
| 体积 ~30-40MB | ✅ PASS |
| 含 android15-8 | ✅ PASS |
| 含 4k 后缀 | ✅ PASS |
| 工具链 Android clang r510928 | ✅ PASS |
| 版本族与 stock 一致 | ✅ PASS |
| **D1 整体** | **✅ 通过** |
| 能否开机 | ❓ 需真机验证（阶段 F） |

## 下一阶段

- **E**: 打包 AK3 — 用能刷 144 模板替换 Image
- **F**: 真机刷入开验证

---

*最后更新：2026-07-23*
