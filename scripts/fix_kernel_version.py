#!/usr/bin/env python3
"""Fix kernel_version extraction in oplus_modules_variant.sh"""
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old = 'kernel_version=$(make -s -f ${script_dir}/../../common/Makefile -p 2>/dev/null | awk \'/^VERSION *=/ { v=$3 } /^PATCHLEVEL *=/ { p=$3 } END { print v"."p }\')'
new = "kernel_version=$(awk '/^VERSION =/ { v=$3 } /^PATCHLEVEL =/ { p=$3 } END { print v\".\"p }' ${script_dir}/../../common/Makefile)"

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print("FIXED: kernel_version now uses direct awk instead of make -p")
else:
    print("WARN: old pattern not found, checking if already fixed...")
    if 'kernel_version=$(awk' in content:
        print("OK: already fixed")
    else:
        print("ERROR: unexpected file content")
        sys.exit(1)
