#!/usr/bin/env bash
# Retry pinned repo sync after transient CodeLinaro Gitaly/TLS failures.
# The manifest and every project revision remain fixed across attempts.
set -euo pipefail

jobs="${SYNC_JOBS:-4}"
attempts="${REPO_SYNC_ATTEMPTS:-3}"
backoff="${REPO_SYNC_BACKOFF_SECONDS:-20}"
[[ "$jobs" =~ ^[1-9][0-9]*$ && "$attempts" =~ ^[1-9][0-9]*$ &&
   "$backoff" =~ ^(0|[1-9][0-9]*)$ ]] || {
  echo "[repo-sync][ERROR] invalid retry/jobs/backoff configuration" >&2
  exit 2
}
(( attempts <= 4 && jobs <= 16 && backoff <= 120 )) || {
  echo "[repo-sync][ERROR] retry/jobs/backoff exceeds bounded safety limits" >&2
  exit 2
}

for ((try=1; try<=attempts; try++)); do
  echo "[repo-sync] attempt=$try/$attempts concurrent_projects=$jobs"
  # --optimized-fetch skips already-resolved pinned SHA projects.
  # --retry-fetches retries individual transient failures inside repo.
  # Neither option changes the reviewed SHA-pinned manifest.
  if repo sync -c --no-clone-bundle --no-tags --optimized-fetch \
      --retry-fetches=2 -j"$jobs"; then
    echo "[repo-sync] PASS: all pinned projects synced on attempt $try"
    exit 0
  fi

  if (( try == attempts )); then
    echo "[repo-sync][ERROR] pinned source sync failed after $attempts attempts" >&2
    exit 1
  fi
  # Lower network concurrency after each failure to reduce Gitaly pressure.
  if (( jobs > 1 )); then
    jobs=$(( (jobs + 1) / 2 ))
  fi
  if (( backoff > 0 )); then
    sleep "$((try * backoff))"
  fi
done
