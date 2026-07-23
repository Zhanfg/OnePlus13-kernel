#!/bin/bash
# Setup brokestar233 6.6-final as build baseline
set -euo pipefail

ROOT=/home/axymorrsen/op13-kernel
SRC="${ROOT}/brokestar-6.6"
# 开发用 fork；upstream 仅同步破星，禁止 push 到 upstream
FORK=https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750.git
UPSTREAM=https://github.com/brokestar233/android_kernel_common_oneplus_sm8750.git
BRANCH=6.6-final

# WSL 若配置了失效本地代理，git/curl 会连不上 GitHub
export http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= all_proxy=

echo "=== disk ==="
df -h "$ROOT" | tail -1

if [ ! -d "${SRC}/.git" ]; then
  echo "=== cloning fork ${BRANCH} ==="
  mkdir -p "$ROOT"
  git -c http.proxy= -c https.proxy= clone --branch "$BRANCH" "$FORK" "$SRC"
  cd "$SRC"
  git remote add upstream "$UPSTREAM"
else
  echo "=== already cloned, rewire remotes + fetch ==="
  cd "$SRC"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$FORK"
  else
    git remote add origin "$FORK"
  fi
  if git remote get-url upstream >/dev/null 2>&1; then
    git remote set-url upstream "$UPSTREAM"
  else
    git remote add upstream "$UPSTREAM"
  fi
  git -c http.proxy= -c https.proxy= fetch origin "$BRANCH"
  git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
  git branch --set-upstream-to="origin/$BRANCH" "$BRANCH" 2>/dev/null || true
fi

cd "$SRC"
echo "=== remotes ==="
git remote -v
echo "=== HEAD ==="
git log -1 --oneline
head -8 Makefile

echo "=== init submodules (starkernel) ==="
git -c http.proxy= -c https.proxy= submodule update --init --recursive 2>&1 | tail -20 || true
ls drivers/starkernel 2>/dev/null | head -10 || echo "no starkernel checkout yet"

echo "=== build configs ==="
ls build.config.gki* build.config.common 2>/dev/null
echo "--- build.config.gki.aarch64 ---"
cat build.config.gki.aarch64 2>/dev/null | head -50
echo "--- build.config.common (head) ---"
head -60 build.config.common 2>/dev/null

echo "=== tools present? ==="
which clang; clang --version 2>/dev/null | head -1
which bazel; which bazelisk
ls prebuilts 2>/dev/null | head || echo "no prebuilts in tree (need Android build env / kleaf)"

echo "=== gki_defconfig exists ==="
test -f arch/arm64/configs/gki_defconfig && echo yes || echo no

# copy working anykernel as packaging template reference
REF_AK3=/mnt/d/OnePlus13-kernel/releases/AK3_6_6_144_g4de260df0fc2_Oplus_sun_gki_35662_20260720_2039_comm.zip
if [ -f "$REF_AK3" ]; then
  mkdir -p "${ROOT}/ak3-brokestar-template"
  rm -rf "${ROOT}/ak3-brokestar-template"/*
  unzip -o "$REF_AK3" -d "${ROOT}/ak3-brokestar-template" >/dev/null
  echo "AK3 template extracted from working package"
  head -40 "${ROOT}/ak3-brokestar-template/anykernel.sh"
fi

# update project baseline pointer
cat > /mnt/d/OnePlus13-kernel/releases/BASELINE_CURRENT.txt << EOF
ACTIVE_BASELINE=破星 brokestar（经 fork 后本地开发）
FORK=https://github.com/Zhanfg/android_kernel_common_oneplus_sm8750
UPSTREAM=https://github.com/brokestar233/android_kernel_common_oneplus_sm8750
BRANCH_PRIMARY=$BRANCH
BRANCH_DEV=dev（可跟进修复）
VERSION=6.6.126
LOCAL_SRC=$SRC
TREE_TYPE=Android Common GKI（含 BORE 等）
DEVICE=PJZ110_16.0.9.401(CN01)
DEVICE_STOCK=6.6.118-android15-9-g690101101069
WORKING_REF_AK3=6.6.144-android15-8-g4de260df0fc2
PACK=block=boot + split_boot/flash_boot（对齐能刷的 AK3）
USER_CONFIRMED=2026-07-20 选破星
NOTE=禁止再刷本仓库旧 6.6.89 包；改动只推 fork，不推 upstream
HEAD=$(git rev-parse --short HEAD)
UPDATED=$(date -Is)
EOF

echo "=== done ==="
cat /mnt/d/OnePlus13-kernel/releases/BASELINE_CURRENT.txt
