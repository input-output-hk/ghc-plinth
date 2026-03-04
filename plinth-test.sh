#!/usr/bin/env bash
set -euo pipefail

: ${CLEAN:=0} # set to 1 to force rebuild


# build Plinth test project

UNAME_S=$(uname -s)

case "$UNAME_S" in
    MINGW*|MSYS*) EXE_EXT=".exe" ;;
    *)            EXE_EXT="" ;;
esac

GHC="$PWD/_build/stage1/bin/uplc-ghc${EXE_EXT}"

if [ ! -x "$GHC" ]; then
  echo "Plinth GHC not found. Please run plinth-build.sh first."
  exit 1
fi

case "$UNAME_S" in
    MINGW*|MSYS*) GHC=$(cygpath -w "$GHC") ;;
esac

CABAL_PROJECT_ARGS="--project-file=cabal.project"

CABAL_ARGS="\
	--remote-repo-cache _build/packages \
	--store-dir=_build/store \
	--logs-dir=_build/logs"

CABAL_BUILD_ARGS="\
	-j -w ${GHC} \
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
