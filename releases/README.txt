一加13 自定义内核 — 成品目录 (按 ReSukiSU 官方说明打包)
========================================================

【必读】ReSukiSU 官方文档两种安装方式完全不同:

1) LKM 修补/安装
   - 管理器界面会出现: 内核版本 / 使用修补工具 5_15+
   - 作用: 给 **当前系统的 boot/init_boot 镜像** 打 LKM 补丁
   - 输出: KernelSU_patched_*.img 再刷分区
   - **不能** 用来安装本目录的「整包自定义内核 Image」

2) 刷写 AnyKernel3  (本包用途)
   - 管理器: 安装/刷写 → **刷写 AnyKernel3** (horizon_kernel / GKI_install_methods)
   - 需要管理器已有 ROOT (你已是 Built-in, 满足)
   - 本 zip 内含 Image, 由 update-binary 写到 **boot** 分区

文档:
  https://resukisu.github.io/zh-Hans/guide/install.html
  - LKM 安装
  - GKI2/GKI1 / 非 GKI 内核（AnyKernel3）安装

【本次推荐文件】
  v6.6.89-OnePlus13-sun-AK3-RESUKISU-20260720-2250.zip

【为什么以前失败】
  1. 错误地把包刷到 init_boot (ramdisk 分区装不下 30MB 内核 Image)
  2. 管理器若走 LKM, 会显示「6.6.144 + 5_15+」——那是读当前手机内核, 不是本包版本
  3. 正确目标: boot + split_boot/flash_boot, 版本应为 6.6.89

【刷写步骤】
  1. 打开 ReSukiSU 管理器
  2. 选「刷写 AnyKernel3 / Flash AnyKernel3」(不是 LKM 修补)
  3. 选本文件: v6.6.89-OnePlus13-sun-AK3-RESUKISU-20260720-2250.zip
  4. 重启后: uname -r  应类似 6.6.89-4k-...

【开机后检测脚本】
  check_kernel.sh  — 轻量检测 (补丁功能 + AK3 可能影响的系统项)

  用法:
    adb push check_kernel.sh /data/local/tmp/
    adb shell su -c 'sh /data/local/tmp/check_kernel.sh'

  报告默认写到:
    /sdcard/Download/kernel_check_时间戳.txt

生成时间: 2026-07-20T22:50:10+08:00
内核: 6.6.89
分区: boot (A/B)
