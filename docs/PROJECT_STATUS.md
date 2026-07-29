# OnePlus 13 内核项目整理

更新时间：2026-07-29

## 1. 仓库关系

| 角色 | 仓库 | 默认分支 | 用途 |
|---|---|---|---|
| 主项目 | `Zhanfg/OnePlus13-kernel` | `main` | 构建脚本、AK3 模板、测试、发布基线和项目文档 |
| 内核源码镜像 | `Zhanfg/android_kernel_common_oneplus_sm8750` | `6.6-final` | SM8750 common 内核源码参考与补丁承载 |

这两个仓库属于同一个 OnePlus 13 内核项目组，但职责不同。主项目不应被源码镜像替代；源码镜像也不等于完整的 OnePlus OKI 工程。

## 2. 目标设备与边界

- 设备：OnePlus 13 国行，代号 `sun`
- 型号：PJZ110
- SoC：Qualcomm SM8750
- 系统：ColorOS 16
- 当前内核基线：6.6.118
- 正确源码路径：OnePlusOSS 完整 OKI manifest，而不是只克隆单个 common 仓库
- 发布产物：匹配同一源码和 ABI 基线的 `Image`、必要的 `vendor_boot` 内容及 AK3 ZIP

旧的 6.6.89 构建不属于当前有效基线，不应继续刷写或作为新构建起点。

## 3. 当前真实状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| 完整 OKI 源码同步 | 已完成 | 使用 OnePlus SM8750 manifest 和 OnePlus 13 配置 |
| 官方构建脚本编译 | 已完成 | `oplus_build_kernel.sh sun perf` 已生成内核产物 |
| 静态检查 | 已完成 | 工具链和 6.6.118 产物已确认 |
| AK3 打包 | 已完成 | 已生成测试包 |
| 真机启动验证 | 待完成 | 未完成前不得标记为稳定版 |
| Root / SuSFS / 调度 / 网络等功能验证 | 待完成 | 需要在能够稳定启动后逐项验证 |

## 4. 构建路径分级

### A. 主构建路径

完整 OnePlus OKI 源码树 + 官方构建脚本：

```bash
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

仓库中的 `scripts/wsl_build_oki.sh` 用于辅助完整构建、增量构建和打包。当前应把这条路径视为主要工程路径。

### B. 实验性 GitHub Actions

`.github/workflows/build.yml` 当前只克隆单个 `android_kernel_oneplus_sm8750` 仓库，并通过创建空 Kconfig / Makefile stub 绕过缺失组件。这种方式不等价于完整 OKI 构建，也不能作为稳定发布依据。

在完成以下工作前，该工作流应明确标记为实验性：

- 使用完整 manifest 同步所有必需仓库。
- 固定源码 revision 和工具链。
- 禁止用空 stub 隐藏缺失依赖。
- 生成与设备 ABI、vendor modules 匹配的完整产物。
- 完成真机启动和运行时验证。

### C. 旧版脚本路径

`build.sh`、`scripts/patch.sh` 和 `configs/base_defconfig_fragment` 属于早期单仓库构建设计。它们与当前完整 OKI 路径存在重叠和冲突，应在验证后选择以下一种处理方式：

1. 重构为完整 OKI 构建入口；或
2. 移入 `legacy/` 并明确停止用于发布。

## 5. 目录职责

| 路径 | 职责 |
|---|---|
| `scripts/` | WSL / OKI 构建、修复、验证和打包脚本 |
| `anykernel/` | AK3 模板和刷写逻辑 |
| `tests/` | 静态、策略和真机运行时测试 |
| `docs/` | 对外稳定文档和工程说明 |
| `releases/` | 当前基线、测试产物记录和回退资料 |
| `.work/memory/` | 临时工程记录，不应作为公开文档或唯一事实来源 |
| `.github/workflows/` | 自动化构建；当前仍属于实验性路径 |

## 6. 文档事实来源

建议按以下优先级维护：

1. `docs/PROJECT_STATUS.md`：公开项目状态和仓库边界。
2. `releases/BASELINE_CURRENT.txt`：当前设备、源码和产物基线。
3. `README.md`：面向使用者的构建、刷写和功能说明。
4. `.work/memory/`：内部过程记录，只保留临时价值，不作为发布依据。

README 当前仍把 GitHub Actions 描述为推荐构建方式，与实际 OKI 基线不一致。后续应修改 README，使其以完整 OKI 构建为主，并把现有 CI 标记为实验性。

## 7. 隐私与仓库卫生

主仓库是公开仓库，内部记录不应长期保存以下信息：

- 本机绝对路径和磁盘布局。
- 临时会话记录。
- 本地用户名、个人目录和环境细节。
- 未脱敏日志、账号、Token、Cookie、密钥或设备私密数据。

建议把 `.work/memory/` 移出公开仓库，或至少将其加入 `.gitignore`，并把仍有长期价值的内容整理进 `docs/`。历史提交中的敏感信息不会因普通删除自动消失；发现真实密钥时需要立即吊销并重写 Git 历史。

## 8. 当前最高优先级

1. 先固定可启动的 Stock 回退包和恢复流程。
2. 用同一完整 OKI 基线重新生成匹配的 Image 与 vendor 侧产物。
3. 禁止旧 6.6.89 包进入发布区。
4. 将 GitHub Actions 改名为 Experimental，或暂时取消 push 自动触发。
5. 更新 README，移除“当前 CI 已可复现稳定构建”的误导表述。
6. 完成真机启动验证后，再验证蜂窝、Wi-Fi、相机、指纹、充电、休眠、Root、SuSFS 和调度功能。
7. 通过验证后发布带源码 revision、manifest、工具链、SHA256 和回退说明的正式 Release。

## 9. 发布状态定义

- **Experimental**：可编译或可打包，但未完成真机启动验证。
- **Boot Verified**：指定系统版本可以稳定启动，并可正常回退。
- **Runtime Verified**：关键硬件与内核功能完成测试。
- **Stable**：完成重复刷写、重启、待机和基础功能回归测试后才可使用。
