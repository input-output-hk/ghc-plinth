#!/usr/bin/env bash
set -euo pipefail

: ${CLEAN:=0} # set to 1 to force rebuild


# build Plinth test project

GHC="$PWD/_build/stage1/bin/uplc-ghc"

if [ ! -x "$GHC" ]; then
  echo "Plinth GHC not found. Please run build-plinth.sh first."
  exit 1
fi

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
    cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} update
    cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} build ${CABAL_BUILD_ARGS} .
)