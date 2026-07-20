# 一加13 内核构建项目 - 长期记忆

## 项目概况
- 路径: D:\OnePlus13-kernel
- 目标: 一加13 (sun/SM8750) + ColorOS 16 国行自定义内核
- 源码基准: OnePlusOSS OOS SM8750 官方树
- 产物: 仅 AnyKernel3 (AK3) zip

## 默认策略 (规格§3, 不可更改)
- 调度=wait, TCP=bbr3, qdisc=fq, ZRAM=lz4
- BBG=默认开可关, KPM=默认不应用, KALLSYMS+ALL=始终启用

## 关键约束
- 不修改基带镜像
- 杜比不进内核 (用户态KSU模块)
- 保留官方: 充电/信号/指纹/相机/音频
- AK3刷写路径: init_boot (split_boot/flash_boot)
- 音量键含义全程固定: +=第一项/推荐, -=第二项/备选

## 项目结构
- build.sh: 构建主脚本
- scripts/patch.sh: 补丁管理 (10步合入顺序)
- configs/base_defconfig_fragment: CONFIG碎片
- anykernel/anykernel.sh: AK3刷写包(7题交互菜单)
- .github/workflows/build.yml: CI/CD
- tests/: 静态测试+单元测试+运行时验收
