# 真正的 GKI / OKI 与 AK3 是什么样（基于真机与能刷包）

日期：2026-07-21  
目的：在继续编译前，先把**欧加设备上的 GKI/OKI** 和**能开机的 AK3** 说清楚。  
结论先行：**之前在没摸清 OKI 形态的情况下，用「Ubuntu clang + 破星 common 树 + make Image」盲编，路线本身就不对。**

---

## 1. 名词：GKI / OKI / OGKI

| 词 | 含义（结合本机证据 + 社区约定） |
|----|--------------------------------|
| **GKI** | Google Generic Kernel Image：通用内核镜像，放在 `boot`，与 vendor 模块按 **KMI** 协作 |
| **OKI / OGKI** | 欧加（Oppo/OnePlus/Realme）在 GKI 上的厂商扩展形态；版本串与符号里大量 `OKI` / `ogki` / `abogki…` |
| **KMI** | Kernel Module Interface；本机可见形态为 `android15-8` 这一代 |
| **4k** | 页大小后缀；本机 stock / 能刷包均为 **4K pages** Image |

社区（如 Numbersf/Action-Build）仓库 topic 同时标 `gki` / `oki` / `ogki`；设备树还有 `HMBIRD_OGKI` → `HMBIRD_GKI` 一类替换，说明**欧加树不是裸 Google common**。

---

## 2. 真机三个 Image 对照（本机文件实测）

### 2.1 官方 stock（`releases/restore/boot.img` 解出）

```
Linux version 6.6.118-android15-8-g93e223c276e7-abogki500782043-4k
  (kleaf@build-host)
  (Android ... based on r510928) clang 18.0.0 / LLD 18
vermagic: 6.6.118-android15-8-g93e223c276e7-abogki500782043-4k SMP preempt mod_unload modversions aarch64
```

- 体积约 **36MB**  
- 构建系统痕迹：**kleaf**  
- 工具链：**Android clang r510928**  
- 大量 `android_rvh_ogki_*` / `android_vh_ogki_*` 符号（欧加 vendor hook）

### 2.2 能刷自定义（`AK3_6_6_144_..._comm.zip` 内 Image）

```
Linux version 6.6.144-android15-8-g4de260df0fc2-abogki500782043-4k
  (emira@Lotus)
  (Android ... based on r510928) clang 18.0.0 / LLD 18
vermagic: 6.6.144-android15-8-g4de260df0fc2-abogki500782043-4k SMP preempt mod_unload modversions aarch64
```

- 体积约 **36MB**  
- **同一 `android15-8` + 同一 `abogki500782043` + 同一 clang 18**  
- 同样是完整 **OGKI hook 集合**  
- 与 stock **同族**，只是 sublevel 更高（118 → 144）

### 2.3 我们失败的 M1（破星盲编）

```
Linux version 6.6.126-OKI-Brokestar
  (Ubuntu clang 21.1.8 / Ubuntu LLD 21)
vermagic: 6.6.126-OKI-Brokestar SMP preempt mod_unload modversions aarch64
```

- 体积约 **30MB**  
- **没有** `android15-8`  
- **没有** `abogki500782043`  
- **没有** r510928 / kleaf  
- 名字里写了 OKI，但**不是**官方/能刷包那种 OKI 版本串与构建体系  

| 项 | stock | 能刷 144 | 我们 M1 |
|----|-------|----------|---------|
| 版本族 | android15-8 + abogki…-4k | **同族** | 自造 `-OKI-Brokestar` |
| 工具链 | Android clang 18 r510928 | **同** | Ubuntu clang 21 |
| 构建 | kleaf | 类官方/社区正式流 | `make Image` 野路子 |
| OGKI hooks | 完整 | 完整 | 残缺/不一致 |
| 体积 | ~36MB | ~36MB | ~30MB |

---

## 3. 真正的 `boot` / 分区角色（本机 boot.img）

从 `restore/boot.img` 解析：

| 字段 | 值 | 含义 |
|------|-----|------|
| magic | `ANDROID!` | 标准 boot 镜像 |
| header_version | **4** | A13+ 常见 |
| kernel_size | ~36MB | 整包就是内核 Image |
| **ramdisk_size** | **0** | **boot 内没有 ramdisk** |
| kernel 内容 | ARM64 `Image`，`ARMd`，4K pages | 纯内核 |

因此在这台 PJZ110 / ColorOS 16 上：

```
boot      → 只装 GKI/OKI 的 kernel Image
init_boot → 一阶段 ramdisk（Root 的 LKM 路线才动它）
```

这与 Google 文档一致：Android 13+ generic boot **只有 GKI 内核**；欧加在此基础上做成 **OKI**。

**ReSukiSU Manager 刷「内核/AK3」= 换 boot 里的 Image。**  
**LKM 5_15+ 路线 = 动 init_boot。**  
二者不要混。

---

## 4. 真正能刷的 AK3 长什么样（完整拆包）

`AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip`：

```
Image                          ← 唯一内核载荷（~36MB）
anykernel.sh
META-INF/.../update-binary
tools/
  ak3-core.sh
  magiskboot / magiskpolicy / busybox
  patch_android                ← 可选 KPM（音量键，默认否）
  …其它 helper
```

**没有：**

- `module.prop` / Magisk 模块壳  
- `vendor_dlkm` / `*.ko` 批量模块  
- `dtbo` / `dtb`（本包不做设备树替换）

`anykernel.sh` 关键逻辑：

```bash
block=boot
is_slot_device=1
do.modules=0

# 有 init_boot_a 时：
split_boot   # 只拆 boot 镜像，不碰 init_boot ramdisk
flash_boot   # 只把新 Image 写回 boot

# 无 init_boot 时才 dump_boot/write_boot（动 ramdisk）
```

**真正的 AK3 =「用 magiskboot 把 boot 里的 kernel 换成这份 OKI Image」的脚本包。**  
不是「随便一个 zip + 自编 Image」。

---

## 5. 真正的构建方式（官方 / 成熟社区）

### 5.1 官方 OnePlusOSS

- 清单：`OnePlusOSS/kernel_manifest`（按机型/Android 代号 `_b`=A16 等）  
- common 树分支示例：`oneplus/sm8750_b_16.0.0_oneplus_13`  
- 构建入口形态（以清单 README 为例）：  
  `./kernel_platform/oplus/build/oplus_build_kernel.sh <platform> gki`  
- 产物应对齐 **kleaf + Android 预编译 clang**，版本串带 `androidXX-Y` / 厂商 id  

### 5.2 成熟社区（如 Numbersf/Action-Build）

- 走 **repo + kernel_manifest**（官方或动态清单）  
- 6.1–6.12 用**官方脚本**动辄 1h 级；另有「极速构建」  
- 产出标准 **AnyKernel3**，并处理 ZRAM 模块、风驰 DT 类型、`setlocalversion` 伪官方后缀等  
- 明确区分 **GKI2.0 / OKI** 设备，而不是「任意 common 树 make 一下」

### 5.3 我们之前的错误路径

```
破星 common 单仓
  → Ubuntu clang 21
  → make gki_defconfig && make Image
  → 抄一个 AK3 壳 zip
```

问题：

1. **不是 OKI 正式构建体系**（无 kleaf / 无 r510928 / 无 abogki 版本契约）  
2. 破星默认 **Polly / oryon / ThinLTO / BORE** 与能刷 OKI 配置不一致  
3. 版本串伪装成 OKI，**ABI/符号族与 stock/能刷包不对齐**  
4. 在没拆清 stock boot / 能刷 AK3 前就叠 M2/M3，放大失败成本  

---

## 6. 正确路线（下一步只做这些，先不盲编）

1. **以 stock + 能刷 144 为黄金样本**  
   - 版本族：`android15-8` + `abogki500782043` + `-4k`  
   - 工具链：Android clang **r510928**  
   - 构建：kleaf / oplus_build / 或成熟 Action 工作流  

2. **AK3 只负责替换 boot 中 Image**  
   - 继续沿用能刷包的 `split_boot`/`flash_boot` 脚本  
   - 不塞 modules，不乱改 init_boot（除非明确走 LKM）  

3. **源码选择优先级**  
   - A. 与能刷作者同策略的树 + 同工具链（优先）  
   - B. OnePlusOSS `sm8750_b_16.0.0_oneplus_13` + 官方脚本  
   - C. 破星仅可作参考，必须先「去性能魔改 + 换官方工具链 + 对齐版本串」，不能再裸 `make Image`  

4. **验证顺序**  
   - 先复现「官方脚本编出的、版本串像 abogki 的 Image」能开机  
   - 再合 ReSukiSU  
   - 再加功能  

---

## 7. 本地样本路径

| 样本 | 路径 |
|------|------|
| 官方 boot | `releases/restore/boot.img` |
| 能刷 AK3 | `releases/AK3_6_6_144_..._comm.zip` |
| 失败 M1–M3 | `releases/v6.6.126-*BROKESTAR-M*.zip` |
| 救砖 | `fastboot flash boot releases/restore/boot.img` |

---

## 8. 一句话

> **欧加这台机的「真内核」是：boot 分区里那份 ~36MB、版本串为  
> `6.6.x-android15-8-g…-abogki…-4k`、用 Android clang r510928 / kleaf 编出来的 OKI Image。  
> 真 AK3 只是安全替换这份 Image 的脚本壳。  
> 我们之前编的是另一物种。**
