#!/bin/bash
set -euo pipefail
cd /home/axymorrsen/op13-kernel/src
S=$(mktemp)
strings arch/arm64/boot/Image > "$S"
echo "=== strings gates ==="
for pat in 'Linux version' 'susfs|kernelsu' 'hmbird' 'bbr3' 'baseband_guard' 'adios' 'ip_set' 'sch_cake|cake'; do
  if grep -qiE "$pat" "$S"; then echo "[PASS] $pat"; else echo "[FAIL] $pat"; fi
done
echo "=== samples ==="
grep -i adios "$S" | head -8 || true
grep -i ip_set "$S" | head -5 || true
grep -i cake "$S" | head -5 || true
rm -f "$S"
echo "=== symbols ==="
for s in adios ip_set cake ksu_ susfs_ hmbird bbg ntsync rekernel tcp_bbr3; do
  n=$(grep -c "$s" System.map || true)
  printf '%s: %s\n' "$s" "$n"
done
ls -la arch/arm64/boot/Image
echo "=== unicode ==="
grep -n 'decomposition result is empty' fs/unicode/utf8-norm.c | head -3 || echo "unicode not applied"
echo "=== config ==="
grep -E 'CONFIG_IP_SET=|CONFIG_NET_SCH_CAKE=|CONFIG_MQ_IOSCHED_ADIOS=|CONFIG_NETFILTER_XT_SET=' .config
