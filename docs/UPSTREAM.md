# OnePlus 13 官方上游与同步策略

更新时间：2026-07-29

## 1. 完整源码入口

OnePlus 13（`sun` / PJZ110 / SM8750）的完整官方工程必须从 OnePlusOSS manifest 同步：

```text
Manifest repository: OnePlusOSS/kernel_manifest
Manifest branch: oneplus/sm8750
Manifest file: oneplus_13_b.xml
```

```bash
repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8750 \
  -m oneplus_13_b.xml
repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)"
repo manifest -r -o manifest-pinned.xml
```

只克隆单个 common 或 msm-kernel 仓库不能获得完整 OKI 工程。

## 2. 官方组件

| 组件 | 分支 | 2026-07-29 核对 SHA |
|---|---|---|
| common | `oneplus/sm8750_b_16.0.0_oneplus_13` | `e1b346b6b4f4096eb342ae3684838a942fd6f6c4` |
| msm-kernel | `oneplus/sm8750_b_16.0.0_oneplus_13` | `6028f47faddaa27700f8dd3a1d83906ea8f27170` |
| modules / devicetree | `oneplus/sm8750_b_16.0.0_oneplus_13` | `d50b305f7da9e14715a25120a4ac7b1a4b8b97c3` |

设备版本为 `PJZ110_16.0.9.401(CN01)`；官方 common 为 Linux 6.6.118，Android tag 为 `android15-6.6-2026-01_r22`。

## 3. 自定义 common 关系

```text
Local: Zhanfg/android_kernel_common_oneplus_sm8750:6.6-final
Local kernel: Linux 6.6.126
Official common: e1b346b6b4f4096eb342ae3684838a942fd6f6c4
Official kernel: Linux 6.6.118
Merge base: 5a0ffb447c1dbd82e8e3af7a98c4a629f4b6d143
Ahead: 8947
Behind: 5
```

本轮工作是将官方 OnePlus/OPlus、Android common 和 ABI/KMI 更新移植到较新的本地 common 基线上，不是把官方 6.6.118 整树覆盖到 6.6.126。

## 4. 权威冲突基线

固定候选为 common 仓库 PR `#6`。

真实 `git merge --no-commit --no-ff` 后检查 unmerged index，得到 **116 个冲突路径**。早期 80 个数字来自截断的 merge-tree 文本报告，已经废止。

| 类别 | 数量 |
|---|---:|
| drivers | 29 |
| fs | 17 |
| kernel | 15 |
| include | 13 |
| net | 12 |
| android ABI/KMI/AFDO | 10 |
| arch | 8 |
| sound | 6 |
| 其他 | 6 |

完整清单位于 common 仓库 `docs/UPSTREAM_SYNC_16.0.9.401.md`。

## 5. 第一轮解决

第一轮规则已在 common 仓库合并并通过 Actions 重放验证：

```text
Initial conflicts: 116
Resolved paths: 31
Remaining conflicts: 85
```

实现文件：

```text
sync/resolutions/16.0.9.401/pass1-ours.txt
scripts/resolve_merge_markers.py
.github/workflows/test-upstream-resolution-pass.yml
```

该规则只替换指定冲突块，保留 Git 已自动合入的官方无冲突 hunk。工作流在仍有 85 个冲突时主动失败，以阻止源码集成。

## 6. 调度架构阻塞

官方 16.0.9.401 使用：

```text
CONFIG_SLIM_SCHED=y
CONFIG_SCHED_CLASS_EXT=y
SCHED_EXT=7
```

本地使用：

```text
CONFIG_HMBIRD_SCHED=y
SCHED_HMBIRD=7
```

HMBIRD 与官方 SCX 占用相同策略编号并修改同一批 fork、tick、pick-next、setscheduler、cgroup 和 idle 接口。`kernel/sched/core.c` 单文件有 28 个冲突块。

在完成策略编号和公共接口重构前，不得声明 HMBIRD 与 SCX 已完成共存。当前稳妥方向为：

1. 保留 wait / fair 默认路径。
2. 保留 HMBIRD / 风驰作为当前自定义路径。
3. 先移植官方非 SCX 修复。
4. SCX 恢复另开独立架构任务。
5. SLIM_SCHED 单独核对依赖和运行时行为。

## 7. 分阶段同步规则

每一轮必须：

- 固定官方 SHA 和本地基线
- 提供 base / ours / theirs 证据
- 使用明确的路径清单
- 可在 GitHub Actions 中重复重放
- 输出解决前后冲突计数
- 仍有冲突时阻止最终 merge commit

后续顺序：

1. 调度架构和策略编号
2. ABI/KMI、OPlus symbols、protected exports、AFDO
3. `gki_defconfig`、Kleaf/Bazel 和工具链
4. task/fork/tick、内存和 vendor hooks
5. common 与 msm-kernel / vendor modules 接口
6. F2FS、EXT4、ZRAM 和文件系统 hooks
7. USB、Type-C、IOMMU、电源和设备驱动
8. 网络与音频
9. 完整 OKI clean build
10. ABI/KMI 与真机回归

## 8. 禁止方式

- 不使用 `git merge -s ours`
- 不整树或批量选择一侧
- 不通过删除 ABI、symbol list、vendor hooks 或配置项消除冲突
- 不只更新 common 而忽略 msm-kernel、modules/devicetree 和 vendor 产物
- 不把单仓库 stub CI 产物作为正式发布
- 未完成完整构建和真机验证前，不合并 PR #6

## 9. 完整验证

- [ ] 剩余 85 个冲突全部解决
- [ ] HMBIRD / SCX / SLIM 架构明确
- [ ] 保存固定 manifest
- [ ] common / msm-kernel / modules / DT revision 匹配
- [ ] 完整 `sun perf` clean build
- [ ] ABI/KMI、OPlus symbols、AFDO 通过
- [ ] Image、vendor_boot、vendor modules 与 vermagic 匹配
- [ ] OnePlus 13 可重复启动、重启和回退
- [ ] 蜂窝、Wi-Fi、蓝牙、相机、指纹、充电、温控和休眠通过
- [ ] Root、SuSFS、KPM、wait/HMBIRD 和网络栈通过
- [ ] SCX 若恢复，单独完成启用与回退验证

## 10. 相关链接

- `https://github.com/OnePlusOSS/kernel_manifest`
- `https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750`
- `https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750`
- `https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750`
- `https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750/pull/6`
