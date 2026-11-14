#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git init -q --bare "$tmp/origin.git"
git init -q "$tmp/source"
git -C "$tmp/source" config user.name 'CI'
git -C "$tmp/source" config user.email 'ci@example.invalid'
printf 'pinned contents\n' > "$tmp/source/README"
git -C "$tmp/source" add README
git -C "$tmp/source" commit -qm 'pinned input'
git -C "$tmp/source" remote add origin "file://$tmp/origin.git"
git -C "$tmp/source" push -q origin HEAD
sha="$(git -C "$tmp/source" rev-parse HEAD)"

# Unit-test the real source implementation without running any production
# checkout/integration operation.
function_text="$(sed -n '/^clone_pinned() {/,/^}/p' "$root/scripts/fusion_v2.sh")"
[[ -n "$function_text" ]]
eval "$function_text"
log() { printf '%s\n' "$*"; }
die() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$tmp/deps"
clone_pinned "fixture" "file://$tmp/origin.git" "$sha" "$tmp/deps/fixture"
[[ "$(git -C "$tmp/deps/fixture" rev-parse HEAD)" == "$sha" ]]
[[ "$(cat "$tmp/deps/fixture/README")" == "pinned contents" ]]

again="$(clone_pinned "fixture" "file://$tmp/origin.git" "$sha" "$tmp/deps/fixture")"
[[ "$again" == *"reuse fixture exact verified pin"* ]] || {
  echo "FAIL: clone_pinned did not reuse the exact current source" >&2
  exit 1
}
printf 'modified\n' > "$tmp/deps/fixture/README"
if clone_pinned "fixture" "file://$tmp/origin.git" "$sha" "$tmp/deps/fixture" \
    > "$tmp/dirty.out" 2>&1; then
  [[ "$(git -C "$tmp/deps/fixture" diff --quiet; echo $?)" != "0" ]] || true
  [[ "$(cat "$tmp/dirty.out")" != *"reuse fixture exact verified pin"* ]] || {
    echo "FAIL: dirty source incorrectly treated as reusable" >&2
    exit 1
  }
fi

python3 - "$root/scripts/fusion_v2.sh" <<'PY'
from pathlib import Path
import re
import sys
s=Path(sys.argv[1]).read_text()
block=s.split("install_resukisu() {",1)[1].split("\n}\n",1)[0]
assert 'cp -a "$DEPS_DIR/resukisu" "$dst"' in block
assert "git clone" not in block
assert 'RESUKISU_COMMIT' in block
print("PASS: internal ReSukiSU checkout copied from verified dependency, no duplicate clone")
PY
echo "PASS: exact pinned checkout reused; dirty input not blindly trusted"
