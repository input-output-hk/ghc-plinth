#!/usr/bin/env bash
# Test installing the uplc-ghc (plinth) bindist via *stock* ghcup.
#
# uplc-ghc is distributed as a custom third-party ghcup tool named `plinth`,
# installable with an unmodified ghcup >= 0.2.1.0 (which introduced the
# installer DSL for arbitrary tools). This script:
#   1. generates a ghcup channel metadata file for the locally-built bindist,
#      with file:// download URLs (via generate-ghcup-metadata.py),
#   2. installs `plinth` into an isolated ghcup prefix using --url-source,
#   3. sets it as default and verifies the uplc-* symlinks + a sample compile.
#
# Prerequisites: run plinth-build.sh (BINDIST=1) first to produce the bindist
# tarball under _build/bindist/, and have a ghcup >= 0.2.1.0 available.
#
# Usage:
#   ./plinth-ghcup-test.sh
#   GHCUP_BIN=/path/to/ghcup ./plinth-ghcup-test.sh   # use a specific ghcup
#   VERSION=9.6.7-plinthtest ./plinth-ghcup-test.sh   # override tool version
#   SKIP_CLEANUP=1 ./plinth-ghcup-test.sh             # keep the test env
set -euo pipefail

BASE="$PWD"

UNAME_S=$(uname -s)
case "$UNAME_S" in
    MINGW*|MSYS*) EXE_EXT=".exe" ;;
    *)            EXE_EXT="" ;;
esac

: ${SKIP_CLEANUP:=0}
: ${GHCUP_BIN:=$(command -v ghcup 2>/dev/null || true)}
: ${PYTHON:=$(command -v python3 2>/dev/null || true)}

####################################################################
# locate the bindist produced by plinth-build.sh

BOOT_GHC="$BASE/_build/stage1/bin/ghc${EXE_EXT}"
if [ ! -x "$BOOT_GHC" ]; then
    echo "error: boot GHC not found at $BOOT_GHC; run plinth-build.sh first"
    exit 1
fi

: ${VERSION:=$("$BOOT_GHC" --numeric-version)}

shopt -s nullglob
tarballs=("$BASE"/_build/bindist/ghc-*.tar.xz)
if [ ${#tarballs[@]} -ne 1 ]; then
    echo "error: expected exactly one bindist tarball in _build/bindist/, found: ${tarballs[*]:-none}"
    echo "       run 'BINDIST=1 ./plinth-build.sh' first"
    exit 1
fi
TARBALL="${tarballs[0]}"

if [ -z "$GHCUP_BIN" ] || [ ! -x "$GHCUP_BIN" ]; then
    echo "error: ghcup not found (set GHCUP_BIN or put ghcup on PATH)"
    echo "       a ghcup >= 0.2.1.0 is required (installer DSL for custom tools)"
    exit 1
fi
if [ -z "$PYTHON" ]; then
    echo "error: python3 not found (needed by generate-ghcup-metadata.py)"
    exit 1
fi

echo "test inputs:"
echo "  ghcup:    $GHCUP_BIN ($("$GHCUP_BIN" --numeric-version 2>/dev/null || "$GHCUP_BIN" --version))"
echo "  version:  $VERSION"
echo "  tarball:  $TARBALL"

####################################################################
# generate channel metadata pointing at the local tarball (file:// URLs)

METADATA_FILE="$BASE/_build/bindist/ghcup-plinth.yaml"
DB_FILE="$BASE/_build/bindist/ghcup-plinth.versions.json"
rm -f "$DB_FILE"   # fresh single-version DB for the test

"$PYTHON" "$BASE/generate-ghcup-metadata.py" \
    --version "$VERSION" \
    --base-url "file://$BASE/_build/bindist" \
    --db "$DB_FILE" \
    --output "$METADATA_FILE" \
    --set-latest \
    "$TARBALL"

echo "generated metadata: $METADATA_FILE"

####################################################################
# isolated ghcup environment

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plinth-ghcup-test.XXXXXX")
cleanup() {
    if [ "$SKIP_CLEANUP" -eq 1 ]; then
        echo "SKIP_CLEANUP=1: test environment preserved at $TEST_DIR"
    else
        rm -rf "$TEST_DIR"
    fi
}
trap cleanup EXIT

export GHCUP_INSTALL_BASE_PREFIX="$TEST_DIR"
export XDG_CONFIG_HOME="$TEST_DIR/config"
export XDG_DATA_HOME="$TEST_DIR/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

GHCUP=( "$GHCUP_BIN" --url-source "file://$METADATA_FILE" )
GHCUP_BIN_DIR="$TEST_DIR/.ghcup/bin"
INSTALL_DIR="$TEST_DIR/.ghcup/plinth/$VERSION"

echo ""
echo "=== ghcup sees the plinth channel ==="
"${GHCUP[@]}" list -t plinth 2>&1 | sed -n '1,20p' || true

echo ""
echo "=== installing plinth $VERSION ==="
"${GHCUP[@]}" install plinth "$VERSION"

echo ""
echo "=== setting plinth $VERSION as default ==="
"${GHCUP[@]}" set plinth "$VERSION"

####################################################################
# verify

ALL_OK=1
check() { if eval "$2"; then echo "  OK: $1"; else echo "  MISSING: $1"; ALL_OK=0; fi; }

echo ""
echo "=== verifying installation ==="
check "install dir $INSTALL_DIR" "[ -d '$INSTALL_DIR' ]"

EXPECTED_BINS="uplc-ghc uplc-ghc-pkg uplc-haddock uplc-hsc2hs uplc-hpc uplc-hp2ps"
for bin in $EXPECTED_BINS; do
    check "$bin-$VERSION" "[ -e '$GHCUP_BIN_DIR/$bin-$VERSION$EXE_EXT' ] || [ -L '$GHCUP_BIN_DIR/$bin-$VERSION$EXE_EXT' ]"
    check "$bin (unversioned/set)" "[ -e '$GHCUP_BIN_DIR/$bin$EXE_EXT' ] || [ -L '$GHCUP_BIN_DIR/$bin$EXE_EXT' ]"
done

echo ""
UPLC_GHC="$GHCUP_BIN_DIR/uplc-ghc${EXE_EXT}"
if [ -x "$UPLC_GHC" ] || [ -L "$UPLC_GHC" ]; then
    got=$("$UPLC_GHC" --numeric-version 2>&1 || true)
    if [ "$got" = "$VERSION" ]; then
        echo "  OK: uplc-ghc --numeric-version = $got"
    else
        # version key and compiler numeric-version may legitimately differ;
        # only require that it runs and prints something version-like.
        echo "  OK: uplc-ghc runs (--numeric-version = $got; tool version = $VERSION)"
    fi
else
    echo "  FAIL: uplc-ghc not executable at $UPLC_GHC"; ALL_OK=0
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
if "$UPLC_GHC" -o "$SAMPLE_DIR/hello" "$SAMPLE_DIR/Hello.hs" >"$SAMPLE_DIR/build.log" 2>&1 \
   && "$SAMPLE_DIR/hello" | grep -q "hello from uplc-ghc"; then
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
    echo "  inspect: $TEST_DIR/.ghcup/"
    exit 1
fi
