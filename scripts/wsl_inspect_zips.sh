#!/bin/bash
set -e
for z in /mnt/d/OnePlus13-kernel/*.zip; do
  [ -f "$z" ] || continue
  echo "=== $(basename "$z") ==="
  unzip -l "$z" 2>/dev/null | grep -iE 'module.prop|anykernel|Image|update-binary|META-INF' || echo "(empty list?)"
done

echo
echo "=== detail MGR zip full list ==="
unzip -l /mnt/d/OnePlus13-kernel/v6.6.89-OnePlus13-sun-AK3-MGR-20260720-2235.zip

echo
echo "=== anykernel/module.prop in repo ==="
cat /mnt/d/OnePlus13-kernel/anykernel/module.prop 2>/dev/null || true
