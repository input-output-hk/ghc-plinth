#!/usr/bin/env bash
# Test installing the uplc-ghc (plinth) bindist via *stock* ghcup.
#
# uplc-ghc is distributed as a custom third-party ghcup tool named `plinth`,
# installable with an unmodified ghcup >= 0.2.1.0 (which introduced the
# installer DSL for arbitrary tools). This script:
#   1. generates a ghcup channel metadata file for a locally-available bindist
#      tarball, with file:// download URLs (via generate-ghcup-metadata.py),
#   2. installs `plinth` into an isolated ghcup prefix using --url-source,
#   3. sets it as default and verifies the uplc-* symlinks + a sample compile.
#
# It needs only a bindist tarball (not a full source tree), so CI jobs can run
# it against the tarball produced by plinth-build.sh / downloaded as an
# artifact. Locations are queried from ghcup itself (`whereis`) so it works the
# same on Linux, macOS and Windows.
#
# Prerequisites: a bindist tarball under _build/bindist/ (or set BINDIST_DIR),
# python3, and a ghcup >= 0.2.1.0 on PATH (or set GHCUP_BIN).
#
# Usage:
#   ./plinth-ghcup-test.sh
#   GHCUP_BIN=/path/to/ghcup ./plinth-ghcup-test.sh
#   VERSION=9.6.7-plinthtest ./plinth-ghcup-test.sh   # override tool version
#   BINDIST_DIR=_build/artifact ./plinth-ghcup-test.sh
#   SKIP_CLEANUP=1 ./plinth-ghcup-test.sh             # keep the test env
#   EXPECT_MUSL=1 ./plinth-ghcup-test.sh              # require a musl bindist
set -euo pipefail

BASE="$PWD"

UNAME_S=$(uname -s)
case "$UNAME_S" in
    MINGW*|MSYS*) IS_WINDOWS=1; EXE_EXT=".exe" ;;
    *)            IS_WINDOWS=0; EXE_EXT="" ;;
esac

: ${SKIP_CLEANUP:=0}
: ${EXPECT_MUSL:=0}
: ${BINDIST_DIR:="$BASE/_build/bindist"}
: ${GHCUP_BIN:=$(command -v ghcup 2>/dev/null || true)}
: ${PYTHON:=$(command -v python3 2>/dev/null || true)}

# ghcup wraps its error codes in an OSC-8 hyperlink escape ("[<OSC8>GHCup-00070
# </OSC8>] real message"). GitHub's log viewer swallows the escape *and the rest
# of the line*, hiding every ghcup error behind a bare "[". Strip terminal
# escapes so failures are legible in CI.
ESC=$'\033'
strip_escapes() {
    sed -e "s/${ESC}]8;;[^${ESC}]*${ESC}\\\\//g" -e "s/${ESC}\\[[0-9;?]*[A-Za-z]//g"
}

# ghcup on Windows is a native binary, so paths must be translated between the
# MSYS world (this script) and the Windows world (ghcup) with cygpath.
#
# - to_file_uri: absolute path -> file:// URI ghcup accepts (file:///C:/... on Windows)
# - to_native:   MSYS path -> native path to hand to ghcup (e.g. GHCUP_INSTALL_BASE_PREFIX)
# - from_native: native path from ghcup (`whereis`) -> MSYS path for shell tests
to_file_uri() {
    if [ "$IS_WINDOWS" -eq 1 ]; then
        printf 'file:///%s' "$(cygpath -m "$1")"
    else
        printf 'file://%s' "$1"
    fi
}
to_native() { if [ "$IS_WINDOWS" -eq 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
from_native() { if [ "$IS_WINDOWS" -eq 1 ]; then cygpath -u "$1"; else printf '%s' "$1"; fi; }

####################################################################
# locate inputs

if [ -z "$GHCUP_BIN" ] || [ ! -x "$GHCUP_BIN" ]; then
    echo "error: ghcup not found (set GHCUP_BIN or put ghcup on PATH)"
    echo "       a ghcup >= 0.2.1.0 is required (installer DSL for custom tools)"
    exit 1
fi
if [ -z "$PYTHON" ]; then
    echo "error: python3 not found (needed by generate-ghcup-metadata.py)"
    exit 1
fi

# Resolve BINDIST_DIR to an absolute path: the file:// URIs built below are
# invalid otherwise (e.g. "file://_build/artifact/..." makes "_build" the URI
# host, not a path, and ghcup can't read it).
if [ ! -d "$BINDIST_DIR" ]; then
    echo "error: BINDIST_DIR not found: $BINDIST_DIR"
    exit 1
fi
BINDIST_DIR="$(cd "$BINDIST_DIR" && pwd)"

shopt -s nullglob
tarballs=("$BINDIST_DIR"/ghc-*.tar.xz)
if [ ${#tarballs[@]} -ne 1 ]; then
    echo "error: expected exactly one bindist tarball in $BINDIST_DIR, found: ${tarballs[*]:-none}"
    echo "       run 'BINDIST=1 ./plinth-build.sh' first, or set BINDIST_DIR"
    exit 1
fi
TARBALL="${tarballs[0]}"

# generate-ghcup-metadata.py derives the ghcup platform from the bindist name, so
# a musl bindist that lost its -musl suffix is published as Linux_UnknownLinux
# and is then uninstallable on Alpine. See Note [Detecting musl] in
# plinth-build.sh. Fail here rather than deep inside ghcup.
if [ "$EXPECT_MUSL" -eq 1 ]; then
    case "$TARBALL" in
        *-musl.tar.xz) ;;
        *) echo "error: EXPECT_MUSL=1 but the bindist is not named '*-musl.tar.xz':"
           echo "       $TARBALL"
           echo "       the musl bindist would be published for the wrong platform"
           exit 1 ;;
    esac
fi

# ghcup tool version. Any consistent string works (this script controls install
# + set + path checks); default to the GHC version embedded in the tarball name.
: ${VERSION:=$("$PYTHON" - "$TARBALL" <<'PY'
import os, re, sys
b = os.path.basename(sys.argv[1])
m = re.match(r"ghc-(.+?)-(?:x86_64|amd64|i386|i686|aarch64|arm64|armv7l)-", b)
print(m.group(1) if m else "0.0.0")
PY
)}

echo "test inputs:"
echo "  ghcup:    $GHCUP_BIN ($("$GHCUP_BIN" --version 2>&1 | head -1))"
echo "  version:  $VERSION"
echo "  tarball:  $TARBALL"

####################################################################
# generate channel metadata pointing at the local tarball (file:// URLs)

METADATA_FILE="$BINDIST_DIR/ghcup-plinth.yaml"
DB_FILE="$BINDIST_DIR/ghcup-plinth.versions.json"
rm -f "$DB_FILE"   # fresh single-version DB for the test

"$PYTHON" "$BASE/generate-ghcup-metadata.py" \
    --version "$VERSION" \
    --base-url "$(to_file_uri "$BINDIST_DIR")" \
    --db "$DB_FILE" \
    --output "$METADATA_FILE" \
    --set-latest \
    "$TARBALL"

echo "generated metadata: $METADATA_FILE"

####################################################################
# isolated ghcup environment

# Note [Short ghcup prefix on Windows]
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ghcup stages an install in a temp dir whose layout repeats the *whole* install
# path underneath it:
#
#   <basedir>/tmp/ghcup-<hash>/<basedir sans drive>/plinth/<ver>/<file>
#
# so every character of GHCUP_INSTALL_BASE_PREFIX is paid for twice. With the
# prefix under MSYS's /tmp (D:\a\_temp\msys64\tmp\plinth-ghcup-test.XXXXXX) the
# staged path for GHC's deepest library files reached 261 characters -- one over
# Windows' 260-char MAX_PATH -- and the copy failed with "The system cannot find
# the path specified". Keep the prefix at the drive root (D:\pgt.XXXXXX) so the
# doubled prefix stays small. Real installs use a short prefix already (C:\ghcup),
# so this is a limitation of the test harness, not of the bindist.
TEST_DIR=""
if [ "$IS_WINDOWS" -eq 1 ]; then
    # Only a drive-letter root gives us a short prefix; a UNC workspace or a
    # read-only root has to fall back (with a warning, since MAX_PATH then bites).
    win_drive=$(cygpath -w "$PWD" 2>/dev/null | cut -c1-3 || true)
    case "$win_drive" in
        [A-Za-z]:\\)
            win_root=$(cygpath -u "$win_drive" 2>/dev/null || true)
            if [ -n "$win_root" ]; then
                TEST_DIR=$(mktemp -d "${win_root}pgt.XXXXXX" 2>/dev/null || true)
            fi
            ;;
    esac
    if [ -z "$TEST_DIR" ]; then
        echo "warning: no short test prefix available at the drive root of $PWD;"
        echo "         falling back to ${TMPDIR:-/tmp}, where the staged install"
        echo "         may exceed MAX_PATH (see Note [Short ghcup prefix on Windows])"
    fi
fi
if [ -z "$TEST_DIR" ]; then
    TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plinth-ghcup-test.XXXXXX")
fi

cleanup() {
    status=$?
    # ghcup's console summary is terse; its own logs hold the details. Dump them
    # before the test env goes away, or a CI failure is unreproducible.
    if [ "$status" -ne 0 ]; then
        for log in "$TEST_DIR"/.ghcup/logs/*.log "$TEST_DIR"/ghcup/logs/*.log; do
            [ -f "$log" ] || continue
            echo ""
            echo "=== ghcup log: $log ==="
            strip_escapes < "$log"
        done
    fi
    if [ "$SKIP_CLEANUP" -eq 1 ]; then
        echo "SKIP_CLEANUP=1: test environment preserved at $TEST_DIR"
    else
        rm -rf "$TEST_DIR"
    fi
}
trap cleanup EXIT

# ghcup honors GHCUP_INSTALL_BASE_PREFIX on all platforms (Windows too), giving
# us an isolated install. The native binary needs a native path for it.
export GHCUP_INSTALL_BASE_PREFIX="$(to_native "$TEST_DIR")"
export XDG_CONFIG_HOME="$TEST_DIR/config"
export XDG_DATA_HOME="$TEST_DIR/data"
mkdir -p "$TEST_DIR/config" "$TEST_DIR/data"

URL_SOURCE=$(to_file_uri "$METADATA_FILE")
GHCUP=( "$GHCUP_BIN" --url-source "$URL_SOURCE" )

# Query ghcup for its own directories so the checks below hold on every OS
# (Windows uses no leading-dot ".ghcup"); translate back to MSYS paths so the
# shell tests and exec work under msys2.
BASEDIR=$(from_native "$("$GHCUP_BIN" whereis basedir)")
BINDIR=$(from_native "$("$GHCUP_BIN" whereis bindir)")
INSTALL_DIR="$BASEDIR/plinth/$VERSION"

# Capability gate: a ghcup predating the installer DSL (< 0.2.1.0) won't know
# the custom `plinth` tool. Fail with a clear hint rather than deep in install.
if ! "${GHCUP[@]}" list -t plinth 2>/dev/null | grep -q plinth; then
    echo "error: this ghcup ($("$GHCUP_BIN" --version)) does not recognize the"
    echo "       custom 'plinth' tool. The installer DSL needs ghcup >= 0.2.1.0."
    exit 1
fi

echo ""
echo "=== installing plinth $VERSION ==="
# `pipefail` keeps ghcup's exit status despite the strip_escapes filter.
"${GHCUP[@]}" install plinth "$VERSION" 2>&1 | strip_escapes

echo ""
echo "=== setting plinth $VERSION as default ==="
"${GHCUP[@]}" set plinth "$VERSION" 2>&1 | strip_escapes

####################################################################
# verify

ALL_OK=1
check() { if eval "$2"; then echo "  OK: $1"; else echo "  MISSING: $1"; ALL_OK=0; fi; }

echo ""
echo "=== verifying installation ==="
check "install dir $INSTALL_DIR" "[ -d '$INSTALL_DIR' ]"

# Only the link names ghcup creates; must match LINKED_BINARIES in
# generate-ghcup-metadata.py. Test with -e (which follows symlinks) and not -L,
# so a link ghcup created towards a file the bindist doesn't contain fails here
# instead of being shipped broken.
EXPECTED_BINS="uplc-ghc uplc-ghc-pkg"
for bin in $EXPECTED_BINS; do
    check "$bin-$VERSION" "[ -e '$BINDIR/$bin-$VERSION$EXE_EXT' ]"
    check "$bin (unversioned/set)" "[ -e '$BINDIR/$bin$EXE_EXT' ]"
done

echo ""
UPLC_GHC="$BINDIR/uplc-ghc${EXE_EXT}"
got=""
if [ -x "$UPLC_GHC" ]; then
    got=$("$UPLC_GHC" --numeric-version 2>&1 || true)
    echo "  OK: uplc-ghc runs (--numeric-version = $got; tool version = $VERSION)"
else
    echo "  FAIL: uplc-ghc not executable at $UPLC_GHC"; ALL_OK=0
fi

# uplc-ghc-pkg must run and report the same version as uplc-ghc: cabal
# (configured with `with-hc-pkg: uplc-ghc-pkg`) refuses a ghc/ghc-pkg version
# mismatch. See Note [Finding ghc-pkg on Windows] in generate-ghcup-metadata.py.
UPLC_GHC_PKG="$BINDIR/uplc-ghc-pkg${EXE_EXT}"
if [ -x "$UPLC_GHC_PKG" ]; then
    pkg_ver=$("$UPLC_GHC_PKG" --version 2>&1 | grep -o '[0-9][0-9.]*$' || true)
    if [ -n "$got" ] && [ "$pkg_ver" = "$got" ]; then
        echo "  OK: uplc-ghc-pkg runs and matches uplc-ghc ($pkg_ver)"
    else
        echo "  FAIL: uplc-ghc-pkg version '$pkg_ver' does not match uplc-ghc '$got'"
        ALL_OK=0
    fi
else
    echo "  FAIL: uplc-ghc-pkg not executable at $UPLC_GHC_PKG"; ALL_OK=0
fi

####################################################################
# compile a tiny sample with the installed compiler

echo ""
echo "=== compiling a sample module with uplc-ghc ==="
SAMPLE_DIR="$TEST_DIR/sample"
mkdir -p "$SAMPLE_DIR"
cat > "$SAMPLE_DIR/Hello.hs" <<'HS'
module Main where
main :: IO ()
main = putStrLn "hello from uplc-ghc"
HS
if "$UPLC_GHC" -o "$SAMPLE_DIR/hello${EXE_EXT}" "$SAMPLE_DIR/Hello.hs" >"$SAMPLE_DIR/build.log" 2>&1 \
   && "$SAMPLE_DIR/hello${EXE_EXT}" | grep -q "hello from uplc-ghc"; then
    echo "  OK: compiled and ran a sample program"
else
    echo "  FAIL: sample compile/run failed; see $SAMPLE_DIR/build.log"
    sed -n '1,40p' "$SAMPLE_DIR/build.log" || true
    ALL_OK=0
fi

echo ""
if [ "$ALL_OK" -eq 1 ]; then
    echo "=== ALL TESTS PASSED ==="
else
    echo "=== SOME TESTS FAILED ==="
    SKIP_CLEANUP=1
    echo "  inspect: $TEST_DIR"
    exit 1
fi
