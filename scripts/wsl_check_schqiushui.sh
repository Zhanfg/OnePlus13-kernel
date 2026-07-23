#!/bin/bash
set -u
TMP=/tmp/schq
rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP"

check_branch() {
  local br="$1"
  echo ""
  echo "======== schqiushui branch: $br ========"
  rm -rf tree
  if ! git clone --depth 1 --branch "$br" --filter=blob:none --sparse \
      https://github.com/schqiushui/android_kernel_oneplus_sm8750.git tree 2>err; then
    echo "fail clone"
    cat err | tail -5
    return 1
  fi
  cd tree
  git sparse-checkout set Makefile README.md 2>/dev/null || true
  # maybe nested
  if [ -f Makefile ]; then
    head -6 Makefile
  else
    find . -name Makefile -maxdepth 3 2>/dev/null | head -10
    for m in common/Makefile kernel/Makefile kernel_platform/common/Makefile; do
      if [ -f "$m" ]; then echo "--- $m ---"; head -6 "$m"; fi
    done
    ls | head -30
  fi
  echo "HEAD: $(git log -1 --oneline)"
  git log -1 --format=%B | head -8
  cd "$TMP"
}

for br in clo-base clo-rebase clo-rebase-hmbird_gki kernel.lnx.6.6.r1-rel; do
  check_branch "$br"
done

echo ""
echo "======== schqiushui manifest sm8750 ========"
rm -rf man
git clone --depth 1 --branch oneplus/sm8750 \
  https://github.com/schqiushui/kernel_manifest.git man 2>&1 | tail -8
if [ -d man ]; then
  ls -la man
  find man -type f | head -40
  for f in man/*.xml man/**/*.xml; do
    [ -f "$f" ] || continue
    echo "--- $f ---"
    head -40 "$f"
  done
fi

echo ""
echo "======== LineageOS 23.2 SUBLEVEL again ========"
# already know 6.6.139

echo DONE
