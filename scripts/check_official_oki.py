#!/usr/bin/env python3
"""Fail-closed verifier for the pinned OnePlus 13 official OKI manifest."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

PINNED = Path("manifests/oneplus_13_b_20261013_pinned.xml")
OFFICIAL_BRANCH = "oneplus/sm8750_b_16.0.0_oneplus_13"
EXPECTED = {
    "android_kernel_common_oneplus_sm8750": ("kernel_platform/common", "e1b346b6b4f4096eb342ae3684838a942fd6f6c4"),
    "android_kernel_oneplus_sm8750": ("kernel_platform/msm-kernel", "6028f47faddaa27700f8dd3a1d83906ea8f27170"),
    "android_kernel_modules_and_devicetree_oneplus_sm8750": ("./", "d50b305f7da9e14715a25120a4ac7b1a4b8b97c3"),
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-remote", action="store_true", help="fail if the official OnePlus branch has advanced")
    args = parser.parse_args()
    root = ET.parse(PINNED).getroot()
    if root.tag != "manifest":
        raise ValueError("Not a repo manifest")
    remotes = {r.attrib["name"]: r.attrib["fetch"] for r in root.findall("remote")}
    if remotes.get("origin") != "https://github.com/OnePlusOSS":
        raise ValueError("Unexpected OnePlusOSS remote")
    if remotes.get("clo-la") != "https://git.codelinaro.org/clo/la":
        raise ValueError("Unexpected Codelinaro remote")
    projects = root.findall("project")
    if len(projects) != 35:
        raise ValueError(f"Expected 35 projects, found {len(projects)}")
    names = [p.attrib.get("name") for p in projects]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate manifest project")
    for project in projects:
        rev = project.attrib.get("revision", "")
        if not re.fullmatch(r"[0-9a-f]{40}", rev):
            raise ValueError(f"Non-fixed revision for {project.attrib.get('name')}: {rev}")
    by_name = {p.attrib["name"]: p for p in projects}
    for name, (path, expected_sha) in EXPECTED.items():
        proj = by_name.get(name)
        if proj is None or proj.attrib.get("remote") != "origin":
            raise ValueError(f"Official project missing or remote changed: {name}")
        if proj.attrib.get("path") != path or proj.attrib.get("revision") != expected_sha:
            raise ValueError(f"Pinned SHA or path mismatch: {name}")
        print(f"PINNED  {name}: {expected_sha}")
        if args.check_remote:
            url = f"https://github.com/OnePlusOSS/{name}.git"
            output = subprocess.check_output(
                ["git", "ls-remote", "--exit-code", url, f"refs/heads/{OFFICIAL_BRANCH}"],
                text=True, timeout=60
            )
            head = output.split()[0]
            if head != expected_sha:
                raise ValueError(f"UPSTREAM MOVED: {name} {head}, pinned {expected_sha}. Re-pin and review before accepting.")
            print(f"CURRENT {name}: official branch matches pinned SHA")
    print(f"OK: {len(projects)} source projects fixed; official OS baseline is PJZ110_16.0.9.401 (6.6.118)")
    print("NOTE: this validates source provenance, NOT a build, ABI, boot or runtime compatibility.")

if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError, ET.ParseError) as exc:
        print(f"OFFICIAL OKI VERIFICATION FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
