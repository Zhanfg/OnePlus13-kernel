#!/usr/bin/env python3
import importlib.util
import tempfile
from pathlib import Path
import zipfile

name = Path(__file__).resolve().parents[1] / "scripts/validate_fusion_ak3_template.py"
spec = importlib.util.spec_from_file_location("ak3validate", name)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

SCRIPT = """#!/sbin/sh
properties() { '
kernel.string=OnePlus13 Verified Test
do.devicecheck=1
do.modules=0
device.name1=sun
device.name2=PJZ110
'; }
block=boot
is_slot_device=1
split_boot
flash_boot
"""
BASE = {
    "anykernel.sh": SCRIPT,
    "META-INF/com/google/android/update-binary": "#!/sbin/sh\n",
    "tools/ak3-core.sh": "#!/sbin/sh\n",
}

def pack(path, entries):
    with zipfile.ZipFile(path, "w") as z:
        for key, value in entries.items():
            z.writestr(key, value)

def should_reject(path):
    try:
        mod.validate(str(path))
    except ValueError:
        return
    raise AssertionError(f"invalid fixture accepted: {path}")

with tempfile.TemporaryDirectory() as td:
    dst = Path(td) / "test.zip"
    pack(dst, BASE)
    mod.validate(str(dst))
    checks = [
        {**BASE, "vendor_boot.img": "bad"},
        {**BASE, "../anykernel.sh": "bad"},
        {**BASE, "dtbo.img": "bad"},
        {**BASE, "vbmeta.img": "bad"},
        {**BASE, "anykernel.sh": SCRIPT.replace("device.name1=sun", "device.name1=cheetah")},
        {**BASE, "anykernel.sh": SCRIPT.replace("do.devicecheck=1", "do.devicecheck=0")},
        {**BASE, "anykernel.sh": SCRIPT.replace("block=boot", "block=vendor_boot")},
        {**BASE, "anykernel.sh": SCRIPT + "\nflash_generic vendor_boot\n"},
        {**BASE, "anykernel.sh": SCRIPT + "\npatch_vbmeta_flag=1\n"},
    ]
    for i, entries in enumerate(checks, 1):
        pack(dst, entries)
        should_reject(dst)
        print(f"PASS: refused fixture #{i}")
    # Repeated entries should also be rejected.
    with zipfile.ZipFile(dst, "w") as z:
        for k, v in BASE.items():
            z.writestr(k, v)
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            z.writestr("anykernel.sh", SCRIPT)
    should_reject(dst)
    print("PASS: duplicate installer refused")
