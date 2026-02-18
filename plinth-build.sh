#!/usr/bin/env bash
set -euo pipefail
LOCAL_HAPPY="$PWD/_build/tools/happy"
LOCAL_ALEX="$PWD/_build/tools/alex"

####################################################################
# edit configuration here:

: ${REBUILD:=0} # set to 1 to force rebuild

# program locations
: ${GHC:=$(which ghc-9.6.7 2>/dev/null || true)}
: ${CABAL:=$(which cabal 2>/dev/null || true)}
: ${HAPPY:=$( [ -x "$LOCAL_HAPPY" ] && echo "$LOCAL_HAPPY" || which happy-1.20.1.1 2>/dev/null || true)}
: ${ALEX:=$( [ -x "$LOCAL_ALEX" ] && echo "$LOCAL_ALEX" || which alex 2>/dev/null || true)}
: ${XETEX:=$(which xetex 2>/dev/null || true)}

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
  "$CABAL" install happy-1.20.1.1 -w "$GHC" --install-method=copy --overwrite-policy=always --installdir="$PWD/_build/tools"
  HAPPY="$LOCAL_HAPPY"
  if [ ! -x "$HAPPY" ]; then
    echo "Failed to build happy"
    exit 1
  fi
fi
if [ -z "$ALEX" ] || [ ! -x "$ALEX" ]; then
  echo "Alex not found, building alex-3.5.4.0 locally..."
  "$CABAL" install alex-3.5.4.0 -w "$GHC" --install-method=copy --overwrite-policy=always --installdir="$PWD/_build/tools"
  ALEX="$LOCAL_ALEX"
  if [ ! -x "$ALEX" ]; then
    echo "Failed to build alex"
    exit 1
  fi
fi

export GHC
export CABAL
export HAPPY
export ALEX
export XETEX

echo "using tools: "
echo " GHC:    $GHC"
echo " cabal:  $CABAL ($CABAL_VERSION)"
echo " happy:  $HAPPY"
echo " alex:   $ALEX"
echo " xetex:  ${XETEX:-not found, docs will be disabled}"

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
  ./configure --enable-tarballs-autodownload
fi
HADRIAN_DOCS_ARGS=""
if [ -z "$XETEX" ] || [ ! -x "$XETEX" ]; then
  echo "xetex not found, disabling docs"
  HADRIAN_DOCS_ARGS="--docs=none"
fi

if [ ! -x ./_build/stage1/bin/ghc ] || [ "$REBUILD" -eq 1 ]; then
  ./hadrian/build -j --flavour=release $HADRIAN_DOCS_ARGS binary-dist
fi

# build Plinth GHC

STAGE="stage-plinth"
BOOT_GHC="$BASE/_build/stage1/bin/ghc"
TARGET_PLATFORM=$("$BOOT_GHC" --print-target-platform)
VERSION=$("$BOOT_GHC" --numeric-version)

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
CWRAPPER_DIR="$BASE/hadrian/bindist/cwrappers"

# detect Windows by checking the target platform
case "$TARGET_PLATFORM" in
    *-mingw32|*-windows) IS_WINDOWS=1; EXE_EXT=".exe" ;;
    *)                   IS_WINDOWS=0; EXE_EXT="" ;;
esac

DEST_UPLC_GHC="$BASE/_build/stage1/bin/uplc-ghc${EXE_EXT}"

(
    cd plinth
    SRC_UPLC_GHC=$("$CABAL" ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} list-bin ${CABAL_BUILD_ARGS} ghc:ghc)
    echo "installing uplc-ghc: $SRC_UPLC_GHC => $DEST_UPLC_GHC"

    # add to build dir
    cp "$SRC_UPLC_GHC" "$DEST_UPLC_GHC"

    # add to bindist
    for dir in "$BASE"/_build/bindist/*; do
        if [ -d "$dir" ]; then
            echo "adding uplc-ghc to bindist: $dir"
            if [ "$IS_WINDOWS" -eq 1 ]; then
                # Windows: copy versioned .exe and compile a C wrapper
                cp "$SRC_UPLC_GHC" "$dir/bin/uplc-ghc-$VERSION.exe"
                "$BOOT_GHC" -no-hs-main \
                    -o "$dir/bin/uplc-ghc.exe" \
                    "-I$CWRAPPER_DIR" \
                    "-DEXE_PATH=\"uplc-ghc-$VERSION.exe\"" \
                    "-DINTERACTIVE_PROCESS=0" \
                    "$CWRAPPER_DIR/version-wrapper.c" \
                    "$CWRAPPER_DIR/getLocation.c" \
                    "$CWRAPPER_DIR/cwrapper.c"
            else
                # Unix: copy versioned binary and symlink
                cp "$SRC_UPLC_GHC" "$dir/bin/uplc-ghc-$VERSION"
                ( cd "$dir/bin" && ln -sf "uplc-ghc-$VERSION" "uplc-ghc" )
            fi
        fi
    done
)

# rebuild archives to include uplc-ghc
rm -f "$BASE"/_build/bindist/ghc-*.tar.*
./hadrian/build -j --flavour=release $HADRIAN_DOCS_ARGS binary-dist

