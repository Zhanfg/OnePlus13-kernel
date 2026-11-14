#!/usr/bin/env python3
"""Static dependency-free structural assertions for the reusable hosted OKI workflow.

GitHub remains the final workflow-language validator; this protects against
accidental generation errors such as duplicate blocks or unindented shell tails.
"""
from pathlib import Path
import re

p = Path(".github/workflows/fusion-v2-full-oki.yml")
text = p.read_text(encoding="utf-8")
lines = text.splitlines()
assert text.count("\njobs:\n") == 1
assert text.count("      - name: Prune persistent Bazel caches") == 1
assert text.count("      - name: Save Bazel caches") == 1
assert text.count("      - name: Upload failure evidence") == 1
assert text.count("      - name: Report stage timing and disk consumption") == 1
steps = re.findall(r"^      - name: (.+)$", text, re.MULTILINE)
assert len(steps) >= 20
assert len(steps) == len(set(steps)), "Duplicate workflow steps"
assert all("\t" not in line[:len(line)-len(line.lstrip())] for line in lines)
for number, line in enumerate(lines, 1):
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    spaces = len(line) - len(line.lstrip())
    if number < lines.index("jobs:") + 2:
        continue
    if spaces == 0:
        raise AssertionError(f"unexpected YAML root at {number}: {line}")
    if spaces == 2 and line != "  build:":
        raise AssertionError(f"unexpected YAML job at {number}: {line}")
    if spaces < 6 and spaces not in (2, 4):
        raise AssertionError(f"unexpected unindented block at {number}: {line}")

# No restore of mutable worktrees or .repo manifests: only selected bare
# object stores are cached, validated by subsequent pinned repo sync.
for section in (
    "Restore pinned Clang Git objects",
    "Restore pinned build tools Git objects",
    "Restore pinned OnePlus OSS Git objects",
    "Measure and budget restored source + Bazel caches",
    "Save Clang Git objects",
    "Save build tools Git objects",
    "Save OnePlus OSS Git objects",
):
    assert steps.count(section) == 1, section
assert text.count("manifests/oneplus_13_b_20261013_pinned.xml") >= 6
assert "steps.cache-budget.outputs" in text
assert "github.run_id" in text

print(f"PASS: well-structured workflow with {len(steps)} unique steps")
