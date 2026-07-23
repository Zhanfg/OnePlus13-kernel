#!/usr/bin/env python3
"""D1 Static Verification — 3-way comparison of kernel Images"""
import subprocess, os, sys

STOCK = "/tmp/stock_kernel.Image"
W144  = "/tmp/ak3_extract/Image"
BUILD = "/home/axymorrsen/op13-oki/kernel_platform/out/msm-kernel-sun-perf/dist/Image"

files = [
    ("Stock (6.6.118)", STOCK),
    ("能刷 144 (6.6.144)", W144),
    ("本次构建 (6.6.118)", BUILD),
]

def sh(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
    return r.stdout.strip()

# Check all exist
for name, path in files:
    if not os.path.exists(path):
        print(f"ERROR: {name} not found at {path}")
        sys.exit(1)

results = {
    "file": [],
    "size": [],
    "version": [],
    "toolchain": [],
    "vermagic": [],
}

for name, path in files:
    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"{'='*60}")
    
    # file
    ftype = sh(f"file '{path}'")
    results["file"].append((name, ftype))
    print(f"  file: {ftype}")
    
    # size
    size = os.path.getsize(path)
    results["size"].append((name, size))
    print(f"  size: {size} bytes ({size/1024/1024:.1f}MB)")
    
    # version string
    ver = sh(f"strings '{path}' | grep -m1 'Linux version'")
    results["version"].append((name, ver))
    print(f"  version: {ver}")
    
    # toolchain
    tc = sh(f"strings '{path}' | grep -m1 'clang'")
    results["toolchain"].append((name, tc))
    print(f"  toolchain: {tc}")
    
    # vermagic
    vm = sh(f"strings '{path}' | grep -m1 'vermagic'")
    results["vermagic"].append((name, vm))
    print(f"  vermagic: {vm}")
    
    # abogki / android15
    abogki = sh(f"strings '{path}' | grep -oE 'abogki[0-9]+' | head -1")
    android = sh(f"strings '{path}' | grep -oE 'android15-[0-9]+' | head -1")
    pages = sh(f"strings '{path}' | grep -oE '\\-4k\\b' | head -1")
    print(f"  abogki tag: {abogki or 'NOT FOUND'}")
    print(f"  android tag: {android or 'NOT FOUND'}")
    print(f"  4k pages: {pages or 'NOT FOUND'}")

print(f"\n{'='*60}")
print("  D1 结论")
print(f"{'='*60}")

# Compare versions
v_stock = sh(f"strings '{STOCK}' | grep -m1 'Linux version'")
v_build = sh(f"strings '{BUILD}' | grep -m1 'Linux version'")
v_144   = sh(f"strings '{W144}' | grep -m1 'Linux version'")

print(f"\nStock:     {v_stock}")
print(f"144:       {v_144}")
print(f"Our build: {v_build}")

# Key checks
print("\n--- 关键验证项 ---")
checks = [
    ("file 类型为 ARM64 4K", all("4K pages" in r[1] for r in results["file"])),
    ("体积 ~30-40MB", all(25 < r[1]/1024/1024 < 45 for r in results["size"])),
    ("含 android15-8", "android15-8" in v_build),
    ("含 4K 后缀", "-4k" in v_build),
    ("工具链含 Android clang r510928", "r510928" in results["toolchain"][2][1]),
    ("版本族与 stock 一致", v_stock.split()[1].rsplit("-",2)[0] in v_build),
]

for desc, ok in checks:
    status = "✅ PASS" if ok else "❌ FAIL"
    print(f"  {status} — {desc}")

print(f"\n{'='*60}")
print(f"  写结果到 releases/OKI_BUILD_LOG.md")
print(f"{'='*60}")
