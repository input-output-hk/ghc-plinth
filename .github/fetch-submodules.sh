#!/usr/bin/env bash
# Fetch the submodules for a CI job, with retries.
#
# Shallow (single-commit) submodule clones: the build never needs submodule
# history, and these submodules (notably plutus) carry a lot of it. --jobs
# fetches them in parallel. GitHub allows fetching the pinned SHA directly,
# so depth 1 works even when it isn't a branch tip.
#
# GitHub sometimes fails a fetch with "HTTP 500" or "expected
# 'acknowledgments'". The failure is transient, so try again after a delay
# (30s, 60s, 90s). A new attempt keeps the submodules that are already
# checked out and fetches only the missing ones.
set -euo pipefail

tries=4

git submodule sync --recursive
for i in $(seq 1 "$tries"); do
  if git submodule update --init --recursive --depth 1 --jobs 4; then
    exit 0
  fi
  if [ "$i" -lt "$tries" ]; then
    echo "submodule fetch: attempt $i/$tries failed; retrying in $((30 * i))s" >&2
    sleep $((30 * i))
  fi
done
echo "submodule fetch: all $tries attempts failed" >&2
exit 1
