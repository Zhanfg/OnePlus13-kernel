#!/usr/bin/env bash
set -euo pipefail
target="${1:-}"
[[ -n "$target" && -f "$target" ]] || {
  echo "[ak3-hardener] Usage: $0 <unpacked-anykernel.sh>" >&2
  exit 2
}
for prop in do.devicecheck device.name1 device.name2; do
  grep -Eq "^[[:space:]]*${prop//./\\.}=" "$target" || {
    echo "[ak3-hardener] Missing original property: $prop" >&2
    exit 2
  }
done
sed -i -E \
  -e 's/^([[:space:]]*do\.devicecheck=).*/\11/' \
  -e 's/^([[:space:]]*device\.name1=).*/\1sun/' \
  -e 's/^([[:space:]]*device\.name2=).*/\1PJZ110/' "$target"
grep -Eq '^[[:space:]]*do\.devicecheck=1[[:space:]]*$' "$target" || exit 2
grep -Eq '^[[:space:]]*device\.name1=sun[[:space:]]*$' "$target" || exit 2
grep -Eq '^[[:space:]]*device\.name2=PJZ110[[:space:]]*$' "$target" || exit 2
echo "[ak3-hardener] PASS: sun/PJZ110 device checks enabled"
