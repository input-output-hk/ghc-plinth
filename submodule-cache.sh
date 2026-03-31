#!/usr/bin/env bash
set -euo pipefail

# Local cache for git submodules.
#
# Maintains bare mirrors of submodule repositories so that CI and
# local builds don't depend on the availability of upstream servers
# (especially gitlab.haskell.org).  When a needed commit is already
# in the cache, no network access is required.
#
# Usage:
#   ./submodule-cache.sh sync                  # fetch all mirrors from upstream
#   ./submodule-cache.sh update --init         # update submodules via cache
#   ./submodule-cache.sh update --init --recursive
#
# Environment:
#   SUBMODULE_CACHE   Cache directory (default: ~/.cache/ghc-submodule-mirrors)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CACHE_DIR="${SUBMODULE_CACHE:-$HOME/.cache/ghc-submodule-mirrors}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Iterate over submodules: calls  callback <name> <path> <url>
# for every entry in .gitmodules.
for_each_submodule() {
    local callback="$1"
    git config -f .gitmodules --get-regexp '\.url$' | while read -r key url; do
        local name="${key#submodule.}"
        name="${name%.url}"
        local path
        path="$(git config -f .gitmodules "submodule.$name.path")"
        "$callback" "$name" "$path" "$url"
    done
}

# Convert a remote URL to a path under $CACHE_DIR.
#
#   https://gitlab.haskell.org/ghc/packages/binary.git
#     -> $CACHE_DIR/gitlab.haskell.org/ghc/packages/binary.git
#
#   git@github.com:input-output-hk/ghc-plinth-plutus.git
#     -> $CACHE_DIR/github.com/input-output-hk/ghc-plinth-plutus.git
#
url_to_cache_path() {
    local url="$1"
    local rel
    # Strip scheme (https://, git://, ssh://)
    rel="${url#*://}"
    # Strip user@ prefix  (git@github.com:...)
    rel="${rel#*@}"
    # SSH short-hand uses ':' as separator; normalise to '/'
    rel="${rel/://}"
    echo "$CACHE_DIR/$rel"
}

# Create a bare mirror for a remote URL if one doesn't exist yet.
# Prints the cache path.
ensure_mirror() {
    local url="$1"
    local cache_path
    cache_path="$(url_to_cache_path "$url")"

    if [ ! -d "$cache_path" ]; then
        echo "  Creating mirror: $cache_path"
        mkdir -p "$(dirname "$cache_path")"
        git clone --bare "$url" "$cache_path" 2>&1 | sed 's/^/    /'
    fi
    echo "$cache_path"
}

# Fetch the latest upstream objects into an existing mirror.
fetch_upstream_into_mirror() {
    local url="$1"
    local cache_path
    cache_path="$(url_to_cache_path "$url")"

    if [ ! -d "$cache_path" ]; then
        ensure_mirror "$url" >/dev/null
        return
    fi

    # Make sure the fetch URL is correct (it may have been cloned
    # before the URL in .gitmodules was changed).
    local current_url
    current_url="$(git -C "$cache_path" config remote.origin.url 2>/dev/null || true)"
    if [ "$current_url" != "$url" ]; then
        git -C "$cache_path" remote set-url origin "$url"
    fi

    echo "  Fetching: $url"
    git -C "$cache_path" fetch origin '+refs/*:refs/*' --prune 2>&1 | sed 's/^/    /'
}

# True if a commit exists in a repo.
has_commit() {
    local repo="$1" commit="$2"
    git -C "$repo" cat-file -e "$commit^{commit}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

# sync — fetch all mirrors from upstream
cmd_sync() {
    echo "Syncing submodule mirrors into $CACHE_DIR"
    _sync_one() {
        local name="$1" path="$2" url="$3"
        echo "[$name] $url"
        fetch_upstream_into_mirror "$url"
    }
    for_each_submodule _sync_one
    echo "Sync complete."
}

# update — update submodules using the local cache.
#
# For each submodule:
#   1. Look up the commit recorded in the current tree.
#   2. If the cache already has it → point the URL to the cache.
#   3. If not → fetch upstream into the cache, then use the cache.
#   4. As a last resort, fall back to direct upstream access.
#   5. Restore the original URL.
cmd_update() {
    local init_flag="" recursive_flag=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --init)      init_flag="--init"; shift ;;
            --recursive) recursive_flag="--recursive"; shift ;;
            *) echo "Unknown flag: $1"; exit 1 ;;
        esac
    done

    echo "Updating submodules (cache: $CACHE_DIR)"
    # Make sure .git/config has the right submodule URLs from .gitmodules
    # before we temporarily override them.
    git submodule sync --quiet

    _update_one() {
        local name="$1" path="$2" url="$3"

        # Commit recorded in the superproject index
        local commit
        commit="$(git ls-tree HEAD -- "$path" 2>/dev/null | awk '{print $3}')" || true
        if [ -z "$commit" ]; then
            return  # submodule not referenced in the tree
        fi

        local cache_path
        cache_path="$(url_to_cache_path "$url")"

        echo "[$name] need $commit"

        # --- ensure the cache has the commit ---

        if [ -d "$cache_path" ] && has_commit "$cache_path" "$commit"; then
            echo "  Cache hit."
        else
            echo "  Cache miss — fetching from upstream..."
            fetch_upstream_into_mirror "$url"

            if ! has_commit "$cache_path" "$commit"; then
                echo "  WARNING: commit still missing after fetch; falling back to direct upstream."
                # shellcheck disable=SC2086
                git submodule update $init_flag $recursive_flag -- "$path"
                return
            fi
        fi

        # --- point URL to cache and update ---

        git config "submodule.$name.url" "$cache_path"

        # shellcheck disable=SC2086
        if ! git submodule update $init_flag $recursive_flag -- "$path" 2>&1; then
            echo "  Cache update failed — retrying from upstream..."
            git config "submodule.$name.url" "$url"
            # shellcheck disable=SC2086
            git submodule update $init_flag $recursive_flag -- "$path"
        fi

        # Restore the canonical remote URL so that later git operations
        # (e.g. push, fetch) work against the real upstream.
        git config "submodule.$name.url" "$url"

        # If the submodule was freshly cloned its origin will point to the
        # cache.  Fix it up to point to the real upstream.
        local sm_gitdir
        sm_gitdir="$(git -C "$path" rev-parse --git-dir 2>/dev/null)" || true
        if [ -n "$sm_gitdir" ]; then
            local origin_url
            origin_url="$(git -C "$path" config remote.origin.url 2>/dev/null)" || true
            if [ "$origin_url" = "$cache_path" ]; then
                git -C "$path" remote set-url origin "$url"
            fi
        fi

        echo "  OK"
    }
    for_each_submodule _update_one
    echo "Submodule update complete."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-help}" in
    sync)   shift; cmd_sync "$@" ;;
    update) shift; cmd_update "$@" ;;
    help|-h|--help)
        echo "Usage: $0 {sync|update} [options]"
        echo ""
        echo "Commands:"
        echo "  sync                     Fetch all mirrors from upstream"
        echo "  update [--init] [--recursive]"
        echo "                           Update submodules using local cache"
        echo ""
        echo "Environment:"
        echo "  SUBMODULE_CACHE   Cache directory (default: ~/.cache/ghc-submodule-mirrors)"
        ;;
    *) echo "Unknown command: $1"; exit 1 ;;
esac
