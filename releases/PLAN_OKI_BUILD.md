# 真 OKI 构建可执行清单（OnePlus 13 / PJZ110 / ColorOS 16）

日期：2026-07-21  
前置阅读：`RESEARCH_GKI_OKI_AK3.md`  
原则：**先对齐官方 OKI 构建体系，再谈 Root/功能；禁止再破星 + 系统 clang 盲编。**

---

## 0. 目标定义（什么叫「做对了」）

| 验收项 | 必须满足 |
|--------|----------|
| 产物形态 | `boot` 用 **ARM64 Image**（~36MB 量级），非 init_boot 包 |
| 版本串形态 | 接近  
  `6.6.x-android15-8-g…-abogki…-4k`  
  （至少含 **android15-8** 或同代 KMI、**4k**；工具链痕迹为 **Android clang / r510928 族**） |
| 对照金样 | stock：`6.6.118-android15-8-…-abogki500782043-4k`（kleaf, r510928）  
  能刷：`6.6.144-android15-8-…-abogki500782043-4k`（同族） |
| 打包 | 仅 **Image + 能刷包同款 AK3 壳**（`block=boot`，有 init_boot 时 `split_boot`/`flash_boot`） |
| 真机 | 过 Logo 进桌面；`uname -r` 含 6.6.x 与合理后缀 |
| 失败 | `fastboot flash boot releases/restore/boot.img` |

**明确失败定义（不要当成功）：**  
`6.6.x-OKI-Brokestar` + Ubuntu clang、无 `android15-8` / 无 `abogki` 契约。

---

## 1. 机型与清单锁定

| 项 | 值 |
|----|-----|
| 设备 | OnePlus 13 / **PJZ110** / **sun** / **SM8750** |
| 系统 | ColorOS **16.0.9.401(CN01)** → 清单后缀 **`_b`（Android 16）** |
| 官方 manifest 仓 | https://github.com/OnePlusOSS/kernel_manifest |
| 分支 | **`oneplus/sm8750`** |
| 清单文件 | **`oneplus_13_b.xml`** |
| 构建命令（官方 README） | `./kernel_platform/oplus/build/oplus_build_kernel.sh **sun perf**` |

### 1.1 清单核心三仓（OnePlusOSS）

| path | 仓库 | revision（13_b） |
|------|------|------------------|
| `kernel_platform/common` | `android_kernel_common_oneplus_sm8750` | `oneplus/sm8750_b_16.0.0_oneplus_13` |
| `kernel_platform/msm-kernel` | `android_kernel_oneplus_sm8750` | 同上 |
| `./`（modules+dt） | `android_kernel_modules_and_devicetree_oneplus_sm8750` | 同上 |

另含 **CodeLinaro（clo-la）** 大量 prebuilts：  
`kernel_platform/prebuilts/clang/host/linux-x86`（**真正的 Android clang**）、build-tools、bazel 规则等。

> 注意：官方 README 写的是 `sun perf`，不是笼统的 `gki`。以 **sm8750 分支 README** 为准。

### 1.2 社区平行入口（备选）

| 项 | 值 |
|----|-----|
| Action-Build | https://github.com/Numbersf/Action-Build （分支 SukiSU-Ultra 等） |
| 机型代号 | **`oneplus_13_b`**（FILE.md · Android16 列表） |
| 动态清单 | https://github.com/Numbersf/kernel_manifest · 分支 `oneplus/sm8750` |

用途：官方脚本在本地难跑通时，用**同机型 manifest 的成熟 CI 逻辑**对照；不是再走破星野路子。

---

## 2. 本机资源（当前 WSL 实测）

| 项 | 现状 | 要求 |
|----|------|------|
| 磁盘 | ~938G 可用 | 建议预留 **≥80–120G** 给 repo + out |
| CPU / 内存 | 14 核 / 23G | 可编；OOM 时减 `-j` |
| `repo` | **未装** | 必装 |
| Android clang | **无**（系统 clang 21 不可用） | 随 manifest prebuilts 同步 |
| 代理 | WSL 曾有失效 `127.0.0.1:7890` | sync/build 时保证可访问 **GitHub + codelinaro** |

---

## 3. 分阶段执行（按序打勾）

### 阶段 A — 环境（不编内核）

- [ ] A1. 安装 `repo`（Google 官方 repo 脚本）
- [ ] A2. 确认 git 用户信息、`gh` 可用（可选）
- [x] A3. 工作目录：WSL 原生 ext4 **`/home/axymorrsen/op13-oki`**  
  （底层 VHDX 在 **E:\WSL\Ubuntu**，不占 C；勿用 `/mnt/e` NTFS 跑 repo）  
  D 仅放文档/小 releases/restore
- [x] A4. 文档确认：已读 `RESEARCH_GKI_OKI_AK3.md`
- [x] A5. 磁盘策略（持续遵守）：  
  - **C：不写大文件、不清理系统区**  
  - **D：空闲 ≥30GB**（项目文档 + restore + 小产物）  
  - **E：空闲 ≥50GB**（WSL VHDX / 参考包；可删废弃的 `/mnt/e/op13-oki` NTFS 半成品）
### 阶段 B — 拉齐源码（官方路径）

```bash
export REPO=/home/axymorrsen/op13-oki/tools/repo
cd /home/axymorrsen/op13-oki
python3 "$REPO" init -u https://github.com/OnePlusOSS/kernel_manifest \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml
python3 -u "$REPO" sync -j4 --force-sync --no-clone-bundle
```

- [ ] B1. `repo init` 成功  
- [ ] B2. `repo sync` 完成（允许分次；clo-la 体积大）  
- [ ] B3. 检查存在：  
  - `kernel_platform/common`  
  - `kernel_platform/msm-kernel`  
  - `kernel_platform/prebuilts/clang/host/linux-x86`  
  - `kernel_platform/oplus/build/oplus_build_kernel.sh`  
- [ ] B4. 记录 common 分支 tip：  
  `git -C kernel_platform/common log -1 --oneline`

### 阶段 C — 官方脚本编「vanilla OKI」

```bash
cd /home/axymorrsen/op13-oki
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

（若脚本参数有变，以树内 README / 脚本 `--help` 为准，**优先 `sun perf`**。）

- [ ] C1. 构建成功结束（无 Error 退出）  
- [ ] C2. 定位产物 Image（常见在 `out` / `dist` / 脚本打印路径；**以脚本 log 为准**）  
- [ ] C3. 记录：  
  ```bash
  strings <Image> | grep -E 'Linux version 6\.6' | head -2
  file <Image>
  ls -lah <Image>
  ```

### 阶段 D — 静态验收（不上机也可做）

与金样对比：

| 检查 | 金样 | 本次产物 |
|------|------|----------|
| `file` 为 ARM64 Image 4K | ✓ | □ |
| 体积 ~30–40MB 级 | ~36MB | □ |
| 含 `android15-8`（或同代） | ✓ | □ |
| 含 `4k` | ✓ | □ |
| 工具链串含 Android clang / r51xxxx | r510928 | □ |
| **不要** 仅 `OKI-Brokestar` + Ubuntu clang | 失败形态 | □ 已避免 |

- [ ] D1. 静态验收通过（写结果到 `releases/OKI_BUILD_LOG.md`）

### 阶段 E — 打真 AK3（只换 Image）

模板：**能刷包**  
`releases/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip`

- [ ] E1. 解压模板 → 替换 `Image` → 改 `kernel.string` → **保留** `split_boot`/`flash_boot` 逻辑  
- [ ] E2. **不要** 加 `module.prop` / 不要塞 modules  
- [ ] E3. 命名示例：  
  `v6.6.xxx-OnePlus13-sun-AK3-OKI-VANILLA-<stamp>.zip`  
- [ ] E4. 写入 `releases/` + sha256 + 刷机说明

### 阶段 F — 真机（仅 vanilla）

- [ ] F1. 已备份 / 可 `fastboot flash boot restore/boot.img`  
- [ ] F2. Manager → 刷 AK3 → 只验证开机  
- [ ] F3. 成功：`uname -r` 记录进 `DEVICE_BASELINE`  
- [ ] F4. **失败则停**，抓现象/last_kmsg，不叠加 Root

### 阶段 G — 仅 F 成功后

- [ ] G1. ReSukiSU（symlink，禁 unshallow 卡死）  
- [ ] G2. 再编 → 再打 AK3 → 再验 Root  
- [ ] G3. 功能（BBG / 网络等）按批加，每批可回退

---

## 4. 明确禁止

1. 再用 **Ubuntu/系统 clang** 对 common 单仓 `make Image` 当交付  
2. 破星默认 **Polly / oryon / ThinLTO / BORE** 未对齐金样前当基线  
3. 未过 **阶段 D/F** 就合全家桶  
4. 把 **init_boot** 当内核 Image 分区  
5. 刷 **6.6.89** 或已确认 bootloop 的 M1–M3 包当「再试一次」

---

## 5. 风险与备选

| 风险 | 处理 |
|------|------|
| `repo sync` clo-la 失败/极慢 | 换网络/代理；分批 sync；对照 Numbersf 动态清单 |
| 官方 16.0 源与实机 16.0.9 小版本差 | 先以 **能开机** 为准；SUBLEVEL 可后续按社区做法调整 |
| 磁盘不足 | 删旧 `brokestar` 中间产物；out 换大盘 |
| 官方脚本参数变更 | 以树内脚本为准，更新本清单 §1 / §3C |
| 官方 vanilla 仍不兼容实机 | 对照能刷 144 作者树/Action 产物做 diff，而不是退回破星盲编 |

---

## 6. 建议执行顺序（给你拍板用）

1. **现在**：只维护文档与清单（本文件 + RESEARCH）  
2. **下一步动手**：阶段 A → B（装 repo、init、sync）——耗时长、可过夜  
3. **再下一步**：阶段 C → E → F（编 vanilla OKI → 打包 → 你刷机）  
4. **Root/功能**：仅 F 通过后进 G  

若你回复 **「开始 A/B」**，再在本机执行装 repo + `repo init/sync`（会占大量磁盘与时间）；在此之前**不再产出新的实验 zip**。

---

## 7. 相关路径速查

| 用途 | 路径 |
|------|------|
| 研究结论 | `releases/RESEARCH_GKI_OKI_AK3.md` |
| 本清单 | `releases/PLAN_OKI_BUILD.md` |
| 金样 AK3 | `releases/AK3_6_6_144_..._comm.zip` |
| 官方 boot | `releases/restore/boot.img` |
| 旧破星树（隔离参考） | `/home/axymorrsen/op13-kernel/brokestar-6.6` |
| OKI 工作区 | **`/home/axymorrsen/op13-oki`**（E:\WSL\Ubuntu\ext4.vhdx） |
| repo 工具 | `/home/axymorrsen/op13-oki/tools/repo` |
| 参考包 | `/home/axymorrsen/op13-oki/ref/` |
| sync 日志 | `/home/axymorrsen/op13-oki/logs/repo-sync.log` |
