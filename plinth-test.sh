#!/usr/bin/env bash
set -euo pipefail

: ${CLEAN:=0} # set to 1 to force rebuild
# Number of parallel cabal jobs. Empty means "-j" (all cores). Compiling with
# the Plinth plugin (Core -> PLC) is memory-heavy, so on RAM-constrained
# machines (e.g. CI runners) several concurrent GHC processes can OOM. Set
# JOBS=1 there to build packages serially.
: ${JOBS:=}


# build Plinth test project

UNAME_S=$(uname -s)

case "$UNAME_S" in
    MINGW*|MSYS*) EXE_EXT=".exe" ;;
    *)            EXE_EXT="" ;;
esac

# Default to the in-tree build; override GHC to point at an installed bindist
# (e.g. the CI test job consumes the bindist produced by `BINDIST=1 plinth-build.sh`).
: ${GHC:=$PWD/_build/stage1/bin/uplc-ghc${EXE_EXT}}

if [ ! -x "$GHC" ]; then
  echo "Plinth GHC not found ($GHC). Please run plinth-build.sh first."
  exit 1
fi

# Resolve GHC to an absolute path: below we cd into plinth/test before invoking
# cabal, so a GHC path relative to the repo root (e.g. the bindist consumed by
# the CI test job) would otherwise be resolved against the wrong directory and
# cabal would fail with "Cannot find the program 'ghc'".
case "$UNAME_S" in
    MINGW*|MSYS*) GHC=$(cygpath -wa "$GHC") ;;
    *)            GHC=$(cd "$(dirname "$GHC")" && pwd)/$(basename "$GHC") ;;
esac

CABAL_PROJECT_ARGS="--project-file=cabal.project"

CABAL_ARGS="\
	--remote-repo-cache _build/packages \
	--store-dir=_build/store \
	--logs-dir=_build/logs"

CABAL_BUILD_ARGS="\
	-j${JOBS} -w ${GHC} \
	--builddir=_build/build \
	--ghc-options=\"-fhide-source-paths\""

(
    cd plinth/test
    if [ "$CLEAN" -eq 1 ]; then
        rm -rf _build
    fi
    echo "Building Plinth test project... current dir: $(pwd)"
    cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} update
    cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} build ${CABAL_BUILD_ARGS} .
    cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} run ${CABAL_BUILD_ARGS} gen-examples
)
