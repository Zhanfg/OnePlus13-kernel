#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/repo" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f "$MOCK_COUNT" ]]; then count="$(cat "$MOCK_COUNT")"; fi
count=$((count + 1))
printf '%s\n' "$count" > "$MOCK_COUNT"
printf '%s\n' "$*" >> "$MOCK_ARGS"
case "$MOCK_MODE" in
  recover) ((count >= 3)) ;;
  always-fail) exit 42 ;;
  ok) exit 0 ;;
  *) exit 12 ;;
esac
MOCK
chmod +x "$tmp/bin/repo"
export PATH="$tmp/bin:$PATH"
export MOCK_COUNT="$tmp/calls"
export MOCK_ARGS="$tmp/args"
export SYNC_JOBS=4
export REPO_SYNC_ATTEMPTS=3
export REPO_SYNC_BACKOFF_SECONDS=0
export MOCK_MODE=recover
bash "$root/scripts/repo_sync_pinned_retry.sh"
test "$(cat "$MOCK_COUNT")" = 3
grep -q -- '-j4' "$MOCK_ARGS"
grep -q -- '-j2' "$MOCK_ARGS"
grep -q -- '-j1' "$MOCK_ARGS"
test "$(grep -c -- '--retry-fetches=2' "$MOCK_ARGS")" = 3
test "$(grep -c -- '--optimized-fetch' "$MOCK_ARGS")" = 3
test "$(grep -c -- '--no-tags' "$MOCK_ARGS")" = 3
test "$(grep -c -- '--no-clone-bundle' "$MOCK_ARGS")" = 3
echo 'PASS: transient upstream outage resumes and preserves fixed sync arguments'

rm "$MOCK_COUNT" "$MOCK_ARGS"
export MOCK_MODE=always-fail
if bash "$root/scripts/repo_sync_pinned_retry.sh"; then
  echo 'FAIL: permanent outage was treated as successful sync' >&2
  exit 1
fi
test "$(cat "$MOCK_COUNT")" = 3
echo 'PASS: permanent remote outage returns error after bounded retries'

rm "$MOCK_COUNT" "$MOCK_ARGS"
export SYNC_JOBS=0
if bash "$root/scripts/repo_sync_pinned_retry.sh"; then
  echo 'FAIL: invalid concurrency was accepted' >&2
  exit 1
fi
test ! -e "$MOCK_COUNT"
echo 'PASS: invalid retry config is rejected before repository changes'
