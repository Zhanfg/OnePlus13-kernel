#!/usr/bin/env python3
"""Validate the OnePlus 13 Image-only AnyKernel3 template before repacking.

Reject executable/payload surprises rather than attempting to sanitize an
untrusted installer. This validates declared behavior, not arbitrary shell
semantics; production builds must additionally use the pinned reviewed ZIP.
"""
from __future__ import annotations
import argparse
from pathlib import PurePosixPath
import re
import stat
import sys
import zipfile

CORE = "META-INF/com/google/android/update-binary"
REQUIRED = ("anykernel.sh", CORE, "tools/ak3-core.sh")
FORBIDDEN_IMAGES = {
    "boot.img", "init_boot.img", "vendor_boot.img", "vendor_kernel_boot.img",
    "dtbo.img", "vbmeta.img", "vbmeta_system.img", "recovery.img",
}
DANGEROUS = re.compile(
    r"(?m)^\s*(?!#)(?:flash_generic\s+|fastboot\s+|(?:busybox\s+)?dd\b.*\bof=|"
    r"patch_vbmeta_flag\s*=\s*1\b)"
)
ASSIGNMENT = re.compile(r"(?m)^\s*([A-Za-z0-9_.]+)\s*=\s*([^\r\n#]+)")

def validate(filename: str) -> None:
    with zipfile.ZipFile(filename) as zf:
        members = zf.infolist()
        names = set()
        for entry in members:
            name = entry.filename
            parts = PurePosixPath(name).parts
            if (not name or name.startswith("/") or "\\" in name or
                    not parts or any(p in (".", "..") for p in parts) or
                    "\x00" in name or re.match(r"^[A-Za-z]:", name)):
                raise ValueError(f"unsafe archive entry: {name!r}")
            if name in names:
                raise ValueError(f"duplicate archive entry: {name}")
            names.add(name)
            if entry.flag_bits & 1:
                raise ValueError(f"encrypted archive entry: {name}")
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f"symlinks are forbidden in AK3 template: {name}")
            if PurePosixPath(name).name.lower() in FORBIDDEN_IMAGES:
                raise ValueError(f"unexpected partition image payload: {name}")
        for item in REQUIRED:
            if item not in names:
                raise ValueError(f"missing required AnyKernel3 file: {item}")
        script = zf.read("anykernel.sh").decode("utf-8")
        props = {key: value.strip().strip("\"'") for key, value
                 in ASSIGNMENT.findall(script)}
        if props.get("do.devicecheck") != "1":
            raise ValueError("AK3 device check must be enabled")
        devices = [value.lower() for key, value in props.items()
                   if key.startswith("device.name")]
        if not any(x in ("sun", "pjz110") for x in devices):
            raise ValueError("AK3 device list must include sun/PJZ110")
        if not re.search(r"(?m)^\s*block\s*=\s*[\"']?boot[\"']?\s*(?:#.*)?$", script):
            raise ValueError("Image-only AK3 must explicitly use block=boot")
        for operation in ("split_boot", "flash_boot"):
            if not re.search(r"\b" + operation + r"\b", script):
                raise ValueError(f"required AnyKernel3 operation missing: {operation}")
        if DANGEROUS.search(script):
            raise ValueError("unexpected direct partition write / vbmeta bypass in installer")
        if "kernel.string=" not in script:
            raise ValueError("missing kernel.string field")
        print(f"PASS: AK3 template {filename}: device guard, boot-only installer, "
              f"{len(members)} safe members")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("template")
    args = parser.parse_args()
    try:
        validate(args.template)
    except (OSError, zipfile.BadZipFile, ValueError, UnicodeError, KeyError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
