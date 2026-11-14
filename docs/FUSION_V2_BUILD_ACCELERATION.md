# Fusion V2 / OnePlus 13: 构建加速与缓存策略（2026-10-14）

适用：GitHub-hosted Ubuntu 24.04 完整 OnePlus OKI → ReSukiSU + SUSFS → KPatch-Next → AnyKernel3，以及可选自托管持久 Runner。

## 优化落地

| 阶段 | 变更 | 安全约束 |
| --- | --- | --- |
| 官方源码下载 | 把 CodeLinaro Clang、辅助工具和 OnePlus OSS 的 **Git bare object stores** 分组缓存，源码 SHA 固定 | 缓存键包含经审核的 35 项目 manifest 哈希；`repo sync` 仍校验固定 SHA |
| 依赖初始化 | ReSukiSU、SUSFS、KPatch-Next 改用部分克隆 + 浅克隆，并复用同 SHA、同 origin 且跟踪文件未被修改的仓库 | 不接受未审核的上游提交；SHA 不符仍 fetch/校验 |
| Root 集成 | 内核内的 ReSukiSU checkout 改为复制已验证的本地 checkout | 不再二次从网络 clone；目标 SHA 再次校验 |
| 编译缓存 | Bazel 缓存按 Root/标准片段及锁定文件计算复用前缀 | 缓存上限与实际保存阈值一致，超额缓存跳过而非使构建失败 |
| 自托管增量 | 显式 `FUSION_INCREMENTAL_BUILD=1` 时保留 Bazel / KPatch 构建中间产物 | 每次先清空最终 dist，仍执行 IKCONFIG、KPatch 元数据、映像 SHA、AK3 ZIP 校验 |
| 失败诊断 | 每阶段记录秒数和退出结果，源码同步记录网络日志 | 编译失败不打包、不发布可刷 ZIP；阶段耗时与失败日志进入 Actions Artifacts |

## 缓存与配额

缓存不是整份源码快照：GitHub Runner 仍然是全新工作环境，重新 checkout 所需的部分源码及其工作树。缓存的是可核验的 Git 对象；`repo sync --optimized-fetch` 对已有 pinned object 尽可能跳过远端请求。

- CodeLinaro Clang 对象缓存：最大 1600 MiB。
- 其他预编译工具 Git 对象：最大 1200 MiB。
- OnePlus OSS Git 对象：最大 1800 MiB。
- Bazel disk + repository cache：预算 3000 MiB，分别裁剪到 2300 MiB 与 500 MiB。

GitHub 缓存具有容量配额和淘汰机制，因此不承诺 100% 命中；容量超预算时跳过上传，但继续编译。**目前没有可信的实测加速比。**

## 运行与回归

- 构建入口：https://github.com/Zhanfg/OnePlus13-kernel/actions/workflows/build-op13-fusion-ak3.yml
- 便携式缓存回归：`bash tests/test_fusion_cache_budget.sh`
- 固定提交浅克隆回归：`bash tests/test_fusion_pinned_clone.sh`
- Workflow 结构回归：`python3 tests/test_fusion_workflow_structure.py`
- 每轮的实际耗时与缓存文件尺寸：查看 GitHub Actions 的 Summary、日志和失败证据。

## 尚未消除的发布限制

本优化只针对 **构建与测试基础设施**，不更新旧的 ReSukiSU/SUSFS 安全基线、不证明内核编译成功，也未验证 Android 17 .103 的厂商 ABI/KMI 与真机启动。只有完整构建成功、静态门槛通过，才允许产出标记为 EXPERIMENTAL 的 AK3。真机稳定性验收前不得当作正式安全发行版。
