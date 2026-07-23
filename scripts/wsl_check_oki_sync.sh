#!/bin/bash
# 检查 op13-oki 仓库 sync 进度
# 用途: 检查 repo sync 是否完成、B3 目录就绪状态
# 用法: ./scripts/wsl_check_oki_sync.sh 或 wsl -d arch-linux-current -u axymorrsen -e sh -c "$(cat scripts/wsl_check_oki_sync.sh)"

OKI_HOME="/home/axymorrsen/op13-oki"
REPO="$OKI_HOME/tools/repo"

echo "================================================"
echo "  op13-oki repo sync 进度检查"
echo "  模式: 浅同步 (depth=1 + -c + --no-tags)"
echo "================================================"
echo ""

# 0. 同步类型提示
echo "--- [0/6] 同步模式 ---"
if grep -q "depth" "$OKI_HOME/.repo/manifests.git/config" 2>/dev/null; then
    echo "  浅同步 (depth=1) ✅ — 更小更快"
else
    echo "  检查中..."
fi
if grep -q "--no-tags" /home/axymorrsen/op13-oki/sync.log 2>/dev/null; then
    echo "  跳过 tags ✅"
fi
echo ""

# 1. sync 进程
echo "--- [1/6] Sync 进程 ---"
SYNC_PID=$(ps aux | grep 'repo.*sync' | grep -v grep | awk '{print $2}')
if [ -n "$SYNC_PID" ]; then
    echo "  🔄 运行中 (PID: $SYNC_PID)"
    # 显示 git fetch 子进程数
    FETCH_COUNT=$(ps aux | grep 'git.*fetch' | grep -v grep | wc -l)
    echo "  📥 活跃 git fetch 子进程: $FETCH_COUNT"
else
    echo "  ⏸️  无活跃 sync 进程"
fi
echo ""

# 2. 磁盘用量
echo "--- [2/6] 磁盘用量 ---"
du -sh "$OKI_HOME" 2>/dev/null
df -h / 2>/dev/null | tail -1
echo ""

# 3. B3 关键目录检查
echo "--- [3/6] B3 目录验收 ---"
for dir in \
    "kernel_platform/common" \
    "kernel_platform/msm-kernel" \
    "kernel_platform/prebuilts/clang/host/linux-x86" \
    "kernel_platform/oplus/build/oplus_build_kernel.sh"; do
    full="$OKI_HOME/$dir"
    if [ -e "$full" ]; then
        echo "  ✅ $dir"
    else
        echo "  ❌ $dir — 未就绪"
    fi
done
echo ""

# 4. 总文件数
echo "--- [4/6] 同步规模 ---"
FILE_COUNT=$(find "$OKI_HOME" -maxdepth 4 -type f 2>/dev/null | wc -l)
echo "  文件数 (浅4层): $FILE_COUNT"
echo ""

# 5. .repo 清单状态
echo "--- [5/6] .repo/manifests ---"
if [ -f "$OKI_HOME/.repo/manifests.git/HEAD" ]; then
    cat "$OKI_HOME/.repo/manifests.git/HEAD"
    echo ""
fi
echo ""

# 6. 未完成的 partial/锁文件
echo "--- [6/6] 残留/锁定文件 ---"
PARTIALS=$(find "$OKI_HOME/.repo" -name '*.lock' -o -name '*.partial' 2>/dev/null | head -10)
if [ -n "$PARTIALS" ]; then
    echo "  ⚠️  发现锁定文件:"
    echo "$PARTIALS"
else
    echo "  无锁定文件 ✅"
fi
echo ""

echo "================================================"
echo "  提示: 等 B3 四项全✅ + sync 进程消失 = 完成"
echo "  完成后执行: cd $OKI_HOME && ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf"
echo "================================================"
