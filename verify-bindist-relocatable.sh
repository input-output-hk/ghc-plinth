#!/usr/bin/env bash
set -euo pipefail

# Verify that the Plinth GHC bindist tarball is relocatable:
#   - Can be installed to any --prefix
#   - Works after the build directory is removed
#
# Prerequisites: bindist tarball in _build/bindist/
#
# Environment variables:
#   PREFIX_A, PREFIX_B  - override install prefixes
#   RUN_PLINTH_TEST     - run plinth test suite (default: 1)
#   CLEANUP             - remove temp dirs on exit (default: 1)
#   SKIP_CLEAN_BUILD    - skip cleaning the build directory (default: 0)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

PREFIX_A="${PREFIX_A:-/tmp/plinth-reloctest-alpha/usr/local}"
PREFIX_B="${PREFIX_B:-/tmp/plinth-reloctest-beta/opt/plinth}"
RUN_PLINTH_TEST="${RUN_PLINTH_TEST:-1}"
CLEANUP="${CLEANUP:-1}"
# don't clean by default
SKIP_CLEAN_BUILD="${SKIP_CLEAN_BUILD:-1}"

FAILURES=0
TESTS_RUN=0
EXTRACT_DIRS=()

# --- Helpers ---

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  PASS: $1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $1"
}

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

cleanup() {
    if [ "$CLEANUP" -eq 1 ]; then
        rm -rf /tmp/plinth-reloctest-alpha /tmp/plinth-reloctest-beta
        for d in "${EXTRACT_DIRS[@]}"; do
            rm -rf "$d"
        done
    fi
}

trap cleanup EXIT

# --- Find tarball ---

find_tarball() {
    local tarballs
    tarballs=("$REPO_ROOT"/_build/bindist/ghc-*-*.tar.xz)
    if [ ${#tarballs[@]} -eq 0 ] || [ ! -f "${tarballs[0]}" ]; then
        echo "ERROR: No bindist tarball found in _build/bindist/"
        echo "Run plinth-build.sh first."
        exit 1
    fi
    TARBALL="${tarballs[0]}"
    TARBALL_BASENAME="$(basename "$TARBALL" .tar.xz)"
    # Extract version from directory name pattern: ghc-VERSION-PLATFORM
    VERSION="$(echo "$TARBALL_BASENAME" | sed 's/^ghc-\(.*\)-[^-]*-[^-]*-[^-]*$/\1/')"
    echo "Found tarball: $TARBALL"
    echo "  Version: $VERSION"
    echo "  Basename: $TARBALL_BASENAME"
}

# --- Install bindist to a prefix ---

install_bindist() {
    local prefix="$1"
    local tarball="$2"
    local extract_dir
    extract_dir="$(mktemp -d /tmp/plinth-reloctest-extract-XXXXXX)"
    EXTRACT_DIRS+=("$extract_dir")

    echo ""
    echo "=== Installing to $prefix ==="
    echo "  Extracting to $extract_dir ..."
    tar -xf "$tarball" -C "$extract_dir"

    echo "  Running configure --prefix=$prefix ..."
    (cd "$extract_dir/$TARBALL_BASENAME" && ./configure --prefix="$prefix")

    echo "  Running make install ..."
    (cd "$extract_dir/$TARBALL_BASENAME" && make install)

    echo "  Installation complete."
}

# --- Verify an installation ---

verify_installation() {
    local prefix="$1"
    local label="$2"
    echo ""
    echo "=== Verifying installation: $label ($prefix) ==="

    # Determine ghclibdir (Linux non-relocatable layout)
    local ghclibdir="$prefix/lib/ghc-$VERSION"

    # 1. Binaries exist
    for bin in uplc-ghc ghc-pkg hsc2hs; do
        if [ -f "$prefix/bin/$bin" ] || [ -L "$prefix/bin/$bin" ]; then
            pass "$bin exists in bin/"
        else
            fail "$bin missing from bin/"
        fi
    done

    # ghc wrapper may exist but should be non-functional (plinth removes the real binary)
    if [ -f "$prefix/bin/ghc" ] || [ -L "$prefix/bin/ghc" ]; then
        echo "  WARN: ghc wrapper exists in bin/ (leftover from install process, points to removed binary)"
    else
        pass "ghc correctly absent from bin/"
    fi

    # 2. uplc-ghc --version
    local ver_output
    if ver_output=$("$prefix/bin/uplc-ghc" --version 2>&1); then
        if echo "$ver_output" | grep -q "$VERSION"; then
            pass "uplc-ghc --version reports $VERSION"
        else
            fail "uplc-ghc --version output doesn't contain $VERSION: $ver_output"
        fi
    else
        fail "uplc-ghc --version failed"
    fi

    # 3. Basic eval
    local eval_output
    if eval_output=$("$prefix/bin/uplc-ghc" -e 'putStrLn "hello"' 2>&1); then
        if [ "$eval_output" = "hello" ]; then
            pass "uplc-ghc -e 'putStrLn \"hello\"' works"
        else
            fail "uplc-ghc -e produced unexpected output: $eval_output"
        fi
    else
        fail "uplc-ghc -e failed: $eval_output"
    fi

    # 4. Package DB check
    if "$prefix/bin/ghc-pkg" check --no-user-package-db 2>&1; then
        pass "ghc-pkg check passes"
    else
        fail "ghc-pkg check failed"
    fi

    # 5. No build paths leaked
    local build_dir="$REPO_ROOT"
    local leaked=0

    # Check wrapper scripts in bin/
    for f in "$prefix/bin"/*; do
        [ -f "$f" ] || continue
        # Only check text files (wrapper scripts)
        file "$f" | grep -q text || continue
        if grep -q "$build_dir" "$f" 2>/dev/null; then
            fail "build path leaked in $(basename "$f"): contains $build_dir"
            leaked=1
        fi
    done

    # Check settings file
    local settings_file="$ghclibdir/lib/settings"
    if [ -f "$settings_file" ]; then
        if grep -q "$build_dir" "$settings_file" 2>/dev/null; then
            fail "build path leaked in settings file"
            leaked=1
        fi
    fi

    # Check package conf files
    local confdir="$ghclibdir/lib/package.conf.d"
    if [ -d "$confdir" ]; then
        if grep -rl "$build_dir" "$confdir"/*.conf 2>/dev/null; then
            fail "build path leaked in package conf files"
            leaked=1
        fi
    fi

    if [ "$leaked" -eq 0 ]; then
        pass "no build paths leaked in installed files"
    fi

    # 6. Package confs use ${pkgroot} — no absolute paths in directory fields
    #    Extract actual directory-field values and check they use ${pkgroot}.
    #    Fields: import-dirs, library-dirs, library-dirs-static, dynamic-library-dirs,
    #            include-dirs, data-dir, haddock-interfaces, haddock-html
    if [ -d "$confdir" ]; then
        local bad_confs=0
        local dir_fields='(import-dirs|library-dirs|library-dirs-static|dynamic-library-dirs|include-dirs|data-dir|haddock-interfaces|haddock-html):'
        for conf in "$confdir"/*.conf; do
            [ -f "$conf" ] || continue
            # Extract lines that are dir field values: either "field: /path" or indented
            # continuation lines after a dir field. We use awk to capture values.
            local abs_paths
            abs_paths=$(awk -v pat="$dir_fields" '
                /^[a-z]/ { in_field = ($0 ~ pat) }
                in_field && /^\s+\// && !/pkgroot/ { print }
                /^[a-z].*:\s+\// && $0 ~ pat && !/pkgroot/ { print }
            ' "$conf")
            if [ -n "$abs_paths" ]; then
                fail "$(basename "$conf") has absolute paths instead of \${pkgroot}"
                echo "$abs_paths" | head -3
                bad_confs=1
            fi
        done
        if [ "$bad_confs" -eq 0 ]; then
            pass "all package confs use \${pkgroot} relative paths"
        fi
    fi

    # 7. Settings use $topdir
    if [ -f "$settings_file" ]; then
        if grep 'unlit command' "$settings_file" | grep -q 'topdir'; then
            pass "settings file uses \$topdir for unlit"
        else
            fail "settings file doesn't use \$topdir for unlit command"
        fi
    else
        fail "settings file not found at $settings_file"
    fi

    # 8. No dynlib references to build directory (ldd check on ELF binaries)
    #    Note: ghc-iserv-dyn legitimately needs LD_LIBRARY_PATH for GHC's shared
    #    libs at runtime, so "not found" for GHC libs is expected. We only check
    #    that no binary references the build directory.
    if command -v ldd >/dev/null 2>&1; then
        local ldd_issues=0
        for bin in "$ghclibdir/bin"/*; do
            [ -f "$bin" ] || continue
            file "$bin" | grep -q ELF || continue
            if ldd "$bin" 2>/dev/null | grep -q "$build_dir"; then
                fail "$(basename "$bin") links to libraries in build directory"
                ldd "$bin" 2>/dev/null | grep "$build_dir" | head -5
                ldd_issues=1
            fi
        done
        if [ "$ldd_issues" -eq 0 ]; then
            pass "no ELF binaries reference build directory"
        fi
    else
        echo "  SKIP: ldd not available, skipping dynlib check"
    fi
}

# --- Run plinth test suite ---

run_plinth_test() {
    local prefix="$1"
    local label="$2"
    local suffix="$3"
    echo ""
    echo "=== Running plinth test suite: $label ($prefix) ==="

    local ghc="$prefix/bin/uplc-ghc"
    local cabal_project_args="--project-file=cabal.project"
    local cabal_args="--remote-repo-cache _build/packages --store-dir=_build/store-reloctest-$suffix --logs-dir=_build/logs-reloctest-$suffix"
    local cabal_build_args="-j -w $ghc --builddir=_build/build-reloctest-$suffix"

    (
        cd "$REPO_ROOT/plinth/test"
        echo "  Updating cabal index..."
        cabal $cabal_project_args $cabal_args update
        echo "  Building test project..."
        cabal $cabal_project_args $cabal_args build $cabal_build_args .
        echo "  Running gen-examples..."
        cabal $cabal_project_args $cabal_args run $cabal_build_args gen-examples
    )

    if [ $? -eq 0 ]; then
        pass "plinth test suite passes with $label"
    else
        fail "plinth test suite failed with $label"
    fi
}

# --- Main ---

main() {
    echo "============================================"
    echo " Plinth Bindist Relocatability Verification"
    echo "============================================"

    find_tarball

    # Copy tarball to temp location before we potentially clean the build dir
    local tarball_copy
    tarball_copy="$(mktemp /tmp/plinth-reloctest-tarball-XXXXXX.tar.xz)"
    cp "$TARBALL" "$tarball_copy"

    # Install to both prefixes
    install_bindist "$PREFIX_A" "$tarball_copy"
    install_bindist "$PREFIX_B" "$tarball_copy"

    rm -f "$tarball_copy"

    # Clean build directory to ensure no runtime dependency on it
    if [ "$SKIP_CLEAN_BUILD" -eq 0 ]; then
        echo ""
        echo "=== Cleaning build directory ==="
        echo "  Running plinth-clean.sh all to remove _build/ ..."
        "$REPO_ROOT/plinth-clean.sh" all
        echo "  Build directory removed."
    else
        echo ""
        echo "=== Skipping build directory cleanup (SKIP_CLEAN_BUILD=1) ==="
    fi

    # Verify both installations
    verify_installation "$PREFIX_A" "prefix-A"
    verify_installation "$PREFIX_B" "prefix-B"

    # Run plinth test suite
    if [ "$RUN_PLINTH_TEST" -eq 1 ]; then
        run_plinth_test "$PREFIX_A" "prefix-A" "a"
        run_plinth_test "$PREFIX_B" "prefix-B" "b"
    else
        echo ""
        echo "=== Skipping plinth test suite (RUN_PLINTH_TEST=0) ==="
    fi

    # Summary
    echo ""
    echo "============================================"
    echo " Results: $TESTS_RUN tests, $FAILURES failures"
    echo "============================================"
    if [ "$FAILURES" -gt 0 ]; then
        echo " FAILED"
        exit 1
    else
        echo " PASSED - bindist is relocatable"
        exit 0
    fi
}

main "$@"
