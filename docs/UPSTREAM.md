# OnePlus 13 官方上游与同步策略

更新时间：2026-07-29

## 1. 唯一正确的完整源码入口

OnePlus 13（`sun` / PJZ110 / SM8750）的完整官方工程应从 OnePlusOSS manifest 同步：

```text
Manifest repository: OnePlusOSS/kernel_manifest
Manifest branch: oneplus/sm8750
Manifest file: oneplus_13_b.xml
```

初始化与同步：

```bash
repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)"
repo manifest -r -o manifest-pinned.xml
```

只克隆单个 common 或 msm-kernel 仓库不能获得完整 OKI 工程。

## 2. 官方仓库关系

`oneplus_13_b.xml` 当前包含以下 OnePlusOSS 核心仓库：

| 路径 | 仓库 | 分支 |
|---|---|---|
| `kernel_platform/common` | `OnePlusOSS/android_kernel_common_oneplus_sm8750` | `oneplus/sm8750_b_16.0.0_oneplus_13` |
| `kernel_platform/msm-kernel` | `OnePlusOSS/android_kernel_oneplus_sm8750` | `oneplus/sm8750_b_16.0.0_oneplus_13` |
| 工程根目录 / vendor modules / DT | `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750` | `oneplus/sm8750_b_16.0.0_oneplus_13` |

Manifest 还固定了 CodeLinaro 构建规则、工具链、Kleaf/Bazel 依赖和其他组件。同步时不得只更新上表中的一个仓库而忽略 manifest 其余 revision。

## 3. 当前公开上游基线

最后核对：2026-07-29。

| 组件 | 当前版本 / 提交 |
|---|---|
| OnePlus 13 系统基线 | `PJZ110_16.0.9.401(CN01)` |
| common | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` |
| msm-kernel | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| common 上游 Android tag | `android15-6.6-2026-01_r22` |
| msm-kernel QCOM tag | `AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111` |
| 内核版本 | Linux `6.6.118` |

上述 SHA 是分支在核对时的 tip，不代替 `manifest-pinned.xml`。正式构建必须保存完整固定 revision manifest。

## 4. 本项目仓库与上游的关系

### `Zhanfg/OnePlus13-kernel`

项目控制仓库，保存：

- 构建入口和辅助脚本
- 补丁来源、配置和策略
- AK3 模板
- 测试、发布与回退记录
- 上游版本锁定信息

它不是完整内核源码仓库。

### `Zhanfg/android_kernel_common_oneplus_sm8750`

自定义 common 源码镜像，默认分支 `6.6-final`。用于承载已经拆分和审计的 common 层补丁。

该仓库：

- 不包含完整 msm-kernel、modules/devicetree 和工具链工程
- 不应单独用于生成最终 OnePlus 13 发布产物
- 必须记录其官方 common 基线和本地补丁序列
- 上游更新应通过独立同步分支或 PR 完成

## 5. 同步流程

### 阶段 A：只读核对

1. 获取 manifest 分支最新提交。
2. 读取 `oneplus_13_b.xml`。
3. 获取 common、msm-kernel、modules/devicetree 当前 tip。
4. 对比当前保存的 `manifest-pinned.xml` 与构建基线。
5. 记录系统版本、QCOM/Android tag 和提交 SHA。

### 阶段 B：完整 OKI 更新

```bash
repo sync -c --force-sync --no-tags -j"$(nproc)"
repo manifest -r -o manifest-pinned.xml
```

更新后先执行未加自定义补丁的官方构建：

```bash
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

只有官方基线构建通过，才进入本地补丁重放。

### 阶段 C：分组重放本地补丁

建议顺序：

1. 设备、DT/DTBO、vendor modules 与 ABI 兼容修复
2. 构建系统和工具链适配
3. Root / ReSukiSU / SuSFS / KPM
4. 默认 wait、HMBIRD / 风驰、SCX 等调度改动
5. ZRAM、I/O 与文件系统改动
6. BBRv3、fq、IP_SET、TPROXY、WireGuard 等网络改动
7. Baseband Guard、Re:Kernel、Wakelock 与其他功能
8. 编译优化与非必要调优

每组必须形成独立提交或 PR，便于回退和定位 bootloop。

### 阶段 D：验证

至少执行：

- 完整 OKI clean build
- Image / vendor_boot / modules 版本与 vermagic 核对
- AK3 打包静态检查
- Boot Verified
- 蜂窝、Wi-Fi、蓝牙、相机、指纹、充电、休眠
- Root、SuSFS、KPM、调度、网络与省电功能
- 重启、待机和回退测试

## 6. 禁止的同步方式

- 只更新 common，不同步 manifest 其他仓库
- 使用单仓库 CI 的空 Kconfig / Makefile stub 产物作为正式发布
- 直接覆盖整个自定义分支
- 使用 `git merge -s ours` 或删除冲突代码伪造成功
- 不保存上游 SHA 和固定 manifest
- 把 6.6.89 等旧产物重新标记为当前 6.6.118 基线
- 未核对 vendor modules / vendor_boot 就刷入 Image

## 7. 发布记录模板

每次同步或发布至少写明：

```text
Device: PJZ110 / sun
ROM: ColorOS 16.x.x.xxx
Manifest repo/branch/file:
Pinned manifest SHA256:
Common SHA:
MSM-kernel SHA:
Modules/devicetree SHA:
Toolchain:
Kernel version:
Local patch range:
Build result:
Boot result:
Runtime result:
Artifact SHA256:
Rollback package:
Known issues:
```

## 8. 相关链接

- https://github.com/OnePlusOSS/kernel_manifest
- https://github.com/OnePlusOSS/kernel_manifest/blob/oneplus/sm8750/oneplus_13_b.xml
- https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750
- https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750
- https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750
- https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750
