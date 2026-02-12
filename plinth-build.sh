#!/usr/bin/env bash
set -euo pipefail

####################################################################
# edit configuration here:

PLUTUS_COMMIT="91fc693959bb828f42b714347fc1a54ef9605e63"
PLUTUS_REPO="https://github.com/IntersectMBO/plutus.git"

: ${REBUILD:=0} # set to 1 to force rebuild

# program locations
: ${GHC:=`which ghc-9.6.7`}
: ${HAPPY:=`which happy-1.20.1.1`}

# end configuration
####################################################################

if [ ! -x "$GHC" ]; then
  echo "GHC not found: $GHC"
  exit 1
fi
if [ ! -x "$HAPPY" ]; then
  echo "Happy not found: $HAPPY"
  exit 1
fi

export GHC
export HAPPY

echo "using tools: "
echo " GHC:    $GHC"
echo " happy:  $HAPPY"

####################################################################
# do the things

BASE=$PWD

# fetch plutus
# XXX make submodule?
if [ ! -d plutus ]; then
  git clone "$PLUTUS_REPO"
  ( cd plutus && git checkout "$PLUTUS_COMMIT" )
fi
# build boot GHC
if [ ! -x ./configure ] || [ "$REBUILD" -eq 1 ]; then
  ./boot
fi
if [ ! -e ./mk/config.h ] || [ "$REBUILD" -eq 1 ]; then
  ./configure
fi
if [ ! -x ./_build/stage1/bin/ghc ] || [ "$REBUILD" -eq 1 ]; then
  ./hadrian/build -j --flavour=release binary-dist
fi

# build Plinth GHC

STAGE="stage-plinth"
BOOT_GHC="$BASE/_build/stage1/bin/ghc"
TARGET_PLATFORM=`"$BOOT_GHC" --print-target-platform`
VERSION=`"$BOOT_GHC" --numeric-version`

CABAL_PROJECT_ARGS="--project-file=cabal.project"

CABAL_ARGS="\
    --remote-repo-cache _build/packages \
    --store-dir=_build/${STAGE}/${TARGET_PLATFORM}/store \
    --logs-dir=_build/${STAGE}/logs"

CABAL_BUILD_ARGS="\
    -j -w ${BOOT_GHC} \
    --builddir=_build/${STAGE}/${TARGET_PLATFORM} \
    --ghc-options=\"-fhide-source-paths\""

(
    cd plinth
    cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} update
    cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} build ${CABAL_BUILD_ARGS} ghc:ghc
)

# add uplc-ghc to the _build dir and the bindists
DEST_UPLC_GHC="$BASE/_build/stage1/bin/uplc-ghc"
(
    cd plinth
    SRC_UPLC_GHC=`cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} list-bin ${CABAL_BUILD_ARGS} ghc:ghc`
    echo "installing uplc-ghc: $SRC_UPLC_GHC => $DEST_UPLC_GHC"

    # add to build dir
    cp "$SRC_UPLC_GHC" "$DEST_UPLC_GHC"

    # add to bindist
    for dir in $BASE/_build/bindist/*; do
        if [ -d "$dir" ]; then
            echo "adding uplc-ghc to bindist: $dir"
            cp "$SRC_UPLC_GHC" "$dir/bin/uplc-ghc-$VERSION"
            ( cd "$dir/bin" && ln -sf "uplc-ghc-$VERSION" "uplc-ghc" )
        fi
    done
)

# rebuild archives to include uplc-ghc
rm -f $BASE/_build/bindist/ghc-*.tar.*
./hadrian/build -j --flavour=release binary-dist

