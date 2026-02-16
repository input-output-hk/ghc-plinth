#!/usr/bin/env bash
set -euo pipefail
LOCAL_HAPPY="$PWD/_build/tools/happy"

####################################################################
# edit configuration here:

: ${REBUILD:=0} # set to 1 to force rebuild

# program locations
: ${GHC:=$(which ghc-9.6.7 2>/dev/null || true)}
: ${CABAL:=$(which cabal 2>/dev/null || true)}
: ${HAPPY:=$( [ -x "$LOCAL_HAPPY" ] && echo "$LOCAL_HAPPY" || which happy-1.20.1.1 2>/dev/null || true)}

# end configuration
####################################################################

# version comparison: returns 0 if $1 >= $2
version_ge() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

if [ ! -x "$GHC" ]; then
  echo "GHC not found: $GHC"
  exit 1
fi
if [ -z "$CABAL" ] || [ ! -x "$CABAL" ]; then
  echo "cabal not found"
  exit 1
fi
CABAL_VERSION=$("$CABAL" --numeric-version)
if ! version_ge "$CABAL_VERSION" "3.14.2.0"; then
  echo "cabal version $CABAL_VERSION is too old, need at least 3.14.2.0"
  exit 1
fi
if [ -z "$HAPPY" ] || [ ! -x "$HAPPY" ]; then
  echo "Happy not found, building happy-1.20.1.1 locally..."
  "$CABAL" install happy-1.20.1.1 -w "$GHC" --install-method=copy --installdir="$PWD/_build/tools"
  HAPPY="$LOCAL_HAPPY"
  if [ ! -x "$HAPPY" ]; then
    echo "Failed to build happy"
    exit 1
  fi
fi

export GHC
export CABAL
export HAPPY

echo "using tools: "
echo " GHC:    $GHC"
echo " cabal:  $CABAL ($CABAL_VERSION)"
echo " happy:  $HAPPY"

####################################################################
# do the things

BASE=$PWD

# check plutus
if [ ! -d plutus/plutus-tx ]; then
  echo "plutus submodule not found, please fetch submodules"
  exit 1
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
    "$CABAL" ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} update
    "$CABAL" ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} build ${CABAL_BUILD_ARGS} ghc:ghc
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

