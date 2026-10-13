# OnePlus 13 官方 OKI 同步记录（2026-10-13）

## 设备信息更正（2026-10-13）

用户当前报告 **OnePlus 13 / Android 17 / 版本尾号 103**，不再按此前 Android 16 `16.0.10.501` 当作当前设备环境。社区已有 OnePlus 13 `ColorOS 17.0.0.103` 固件包记录，但尚未收到设备完整版本号、`uname -r` 和 build fingerprint，不能确认完全一致。该信息是运行设备基线，**不得与公开的 .401 OSS 源码发布基线混为一谈**。

- 参考（第三方固件索引，非 OnePlusOSS 源码）：https://sourceforge.net/projects/oneplus13flashers/files/Oneplus%2013/Regional%20Flashers/COS/
- OnePlusOSS 尚未出现 OnePlus 13 Android 17 专项分支（2026-10-13 检查）。
- 只有在拿到当前设备构建指纹、内核 KMI/模块/设备树对照结果后，才能开展针对其固件的可刷机集成。

## 本次结论

- 目标：OnePlus 13 / sun / SM8750 / PJZ110
- **最新核实的 OnePlusOSS 公开设备源码**：PJZ110_16.0.9.401(CN01)
- 官方内核：Linux **6.6.118**，Android common **android15-6.6-2026-01_r22**
- OnePlusOSS kernel_manifest 分支：`oneplus/sm8750`，官方文件：`oneplus_13_b.xml`
- 官方 kernel_manifest 分支 HEAD：`f8e50677874c65b6da41057d2f39be7b4ef3c08a`
- 最新官方 .401 发布于 2026-07-22；核实时间 2026-10-13
- **并未发现官方发布了对应 Android 17 `.103` 的完整 OnePlus 13 OKI 源码**；此前 `.501` 属于历史设备基线，不得把 .401 认作 Android 17 设备适配成功
- 本仓库此前镜像 `ZhanfgBuild/android_kernel_common_oneplus_sm8750:upstream/oneplus-sm8750-b-16.0.0-oneplus-13` 已是最新官方 common：无需重复/强推历史提交

## 完整官方版本锁定

| 组件 | 官方仓库 | 官方 branch HEAD |
|---|---|---|
| Common | `OnePlusOSS/android_kernel_common_oneplus_sm8750` | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` |
| MSM / Qualcomm | `OnePlusOSS/android_kernel_oneplus_sm8750` | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| Modules + Device Tree | `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750` | `d50b305f7da9e14715a25120a4ac7b1a4b8b97c3` |

完整可复现入口：[`manifests/oneplus_13_b_20261013_pinned.xml`](../manifests/oneplus_13_b_20261013_pinned.xml)。保留 OnePlusOSS 官方的项目路径、remote、linkfile、Codelinaro 锁定提交；将三个 OnePlusOSS 项目分支引用替换为核实的完整 40 位 SHA，共 35 个项目。

## 校验与同步

```sh
python3 scripts/check_official_oki.py --check-remote

mkdir -p op13-oki && cd op13-oki
repo init -u https://github.com/Zhanfg/OnePlus13-kernel.git \
  -b sync/oneplusoss-oki-20261013 \
  -m manifests/oneplus_13_b_20261013_pinned.xml
repo sync -c --no-clone-bundle --no-tags -j"$(nproc)"
repo manifest -r -o manifest-resolved.xml
sha256sum manifest-resolved.xml
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

*构建前应先确认磁盘空间、Android Clang、Bazel/Kleaf 依赖与当前系统的 vendor ABI；上面的命令是正式 OKI 路线，并未在本次 GitHub API 同步中执行。* 配套工作流 `.github/workflows/verify-official-oki.yml` **只验证源码锁定/官方上游是否变化**，并不声称已完成源码克隆、编译或真机验收。

## 自定义 common 的边界

- `ZhanfgBuild/android_kernel_common_oneplus_sm8750:6.6-final` 的 Linux 6.6.126 是**自定义 common**，不是最新官方完整 OKI。
- 历史 PR #6 尝试将官方 .401 同步到旧自定义 common，截至 PR 的第三轮记录仍有 **50 个冲突路径**。
- Fusion V2 新路线 PR #17 直接从官方 `e1b346...` 开始，再分层集成 ReSukiSU/SUSFS，仍处于 Draft。
- 控制仓库 PR #13 仍待完整 OKI clean build、KPatch-Next、AK3、ABI/KMI 和真机验证。
- **本次只锁定并固化最新官方发布的完整 OKI 基线，没有覆盖现有 6.6-final、main、Root 或调度代码。**
- 当前设备报告 Android 17 `.103`，但没有完成其原厂 boot/vendor_boot/vendor_dlkm 兼容验证；**不得直接把基于 .401 的 Image/ZIP 刷入当前主力机**。

## 验收等级

- [x] 官方发布 HEAD 与三套源码 SHA 已核实
- [x] 最新官方 common 已存在于本地镜像分支
- [x] 完整 35 项目 manifest 预锁定
- [x] GitHub 官方源码来源校验通过（Actions run 38426265865；不等于内核编译）
- [ ] 完整 `repo sync` 以及 pinned resolved manifest
- [ ] `sun perf` clean build 完成
- [ ] ABI/KMI、vermagic、Modules + DT 匹配
- [ ] 与实际手机固件版本一致性核查
- [ ] 真机启动、硬件功能、稳定性验收

此文件用于官方源码同步，不代表可刷写发布版本。