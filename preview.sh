#!/usr/bin/env bash
# Launch a local Jekyll preview server that rebuilds on file modification and
# reloads the browser via LiveReload. Pass any extra `jekyll serve` flags as
# arguments, e.g. `./preview.sh --port 5000`.
set -euo pipefail

cd "$(dirname "$0")"

exec bundle exec jekyll serve --watch --livereload --incremental --host 0.0.0.0 "$@"
