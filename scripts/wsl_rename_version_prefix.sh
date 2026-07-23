#!/bin/bash
# Prefix existing release zips with kernel version: v6.6.89-...
set -euo pipefail
IMG=/home/axymorrsen/op13-kernel/src/arch/arm64/boot/Image
WIN=/mnt/d/OnePlus13-kernel
WSL=/home/axymorrsen/op13-kernel

VER=$(strings "$IMG" 2>/dev/null | grep -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
if [ -z "$VER" ]; then
  VER="6.6.89"
fi
echo "Kernel version: $VER"

rename_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  cd "$dir"
  for f in OnePlus13-sun-AK3-*.zip OnePlus13-sun-custom-*.zip OnePlus13-AK3-*.zip; do
    [ -f "$f" ] || continue
    case "$f" in
      v${VER}-*|v[0-9]*)
        # already version-prefixed
        if [[ "$f" == v${VER}-* ]]; then
          echo "ok already: $f"
        else
          # re-prefix with correct version if different
          base="${f#v*-}"
          # only if looks like old vX.Y.Z-
          if [[ "$f" =~ ^v[0-9]+\.[0-9]+\.[0-9]+- ]]; then
            echo "skip other-ver: $f"
          else
            nf="v${VER}-${f}"
            cp -f "$f" "$nf"
            sha256sum "$nf" > "${nf}.sha256"
            echo "prefixed: $f -> $nf"
          fi
        fi
        ;;
      *)
        nf="v${VER}-${f}"
        cp -f "$f" "$nf"
        sha256sum "$nf" > "${nf}.sha256"
        echo "prefixed: $f -> $nf"
        ;;
    esac
  done
}

rename_dir "$WIN"
rename_dir "$WSL"

# also rename Image-release
if [ -f "$WIN/Image-release" ]; then
  cp -f "$WIN/Image-release" "$WIN/v${VER}-Image"
  echo "Image: v${VER}-Image"
fi

echo "=== Windows (version-first) ==="
ls -lah "$WIN"/v${VER}-*.zip 2>/dev/null || ls -lah "$WIN"/v*.zip 2>/dev/null | head -20
