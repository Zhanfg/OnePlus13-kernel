#!/usr/bin/env python3
"""Extract kernel Image from Android boot.img"""
import struct, os, sys

bootimg = sys.argv[1]
outpath = sys.argv[2]

with open(bootimg, 'rb') as f:
    magic = f.read(8)
    if magic != b'ANDROID!':
        print(f"ERROR: bad magic {magic}")
        sys.exit(1)
    f.seek(8)
    kernel_size = struct.unpack('<I', f.read(4))[0]
    
    page_size = 4096  # default
    
    with open(outpath, 'wb') as out:
        f.seek(page_size)  # kernel starts at page 1
        kernel_data = f.read(kernel_size)
        out.write(kernel_data)
    
    actual = os.path.getsize(outpath)
    print(f"OK: kernel_size={kernel_size} ({kernel_size/1024/1024:.1f}MB)")
    print(f"    extracted to {outpath} ({actual/1024/1024:.1f}MB)")
