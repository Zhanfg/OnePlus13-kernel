#!/bin/bash
echo "TIME=$(date)"
echo "=== processes ==="
pgrep -c clang || echo clang=0
pgrep -c make || echo make=0
pgrep -af "make ARCH" | head -5
echo "=== core.o ==="
ls -la /home/axymorrsen/op13-kernel/src/kernel/sched/core.o 2>/dev/null || echo no_core.o
echo "=== Image ==="
ls -la /home/axymorrsen/op13-kernel/src/arch/arm64/boot/Image 2>/dev/null || echo no_Image
echo "=== latest log ==="
LOG=$(ls -t /home/axymorrsen/op13-kernel/logs/build*.log 2>/dev/null | head -1)
echo "LOG=$LOG"
if [ -n "$LOG" ]; then
  grep -E 'error:|Error 1|BUILD SUCCESS|BUILD FAILED|OBJCOPY.*Image|LD +vmlinux' "$LOG" | tail -40
  echo "--- tail ---"
  tail -15 "$LOG"
fi
echo "=== wrapper ==="
tail -10 /home/axymorrsen/op13-kernel/logs/build5-wrapper.log 2>/dev/null
tail -10 /home/axymorrsen/op13-kernel/logs/build4-wrapper.log 2>/dev/null
