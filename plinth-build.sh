#!/usr/bin/env bash
set -euo pipefail
LOCAL_HAPPY="$PWD/_build/tools/happy"
LOCAL_ALEX="$PWD/_build/tools/alex"

UNAME_S=$(uname -s)
case "$UNAME_S" in
    MINGW*|MSYS*) IS_WINDOWS=1; EXE_EXT=".exe" ;;
    *)            IS_WINDOWS=0; EXE_EXT="" ;;
esac

RELEASE_HADRIAN_ARGS=""
DEV_HADRIAN_ARGS="--docs=none"
RELEASE_FLAVOUR="release"
DEV_FLAVOUR="release+debug_info+debug_ghc+assertions"

# platform-specific default configure arguments
case "$UNAME_S" in
    MINGW*|MSYS*) DEFAULT_CONFIGURE_ARGS="--enable-tarballs-autodownload" ;;
    Darwin*)      DEFAULT_CONFIGURE_ARGS="--with-intree-gmp" ;;
    *)            DEFAULT_CONFIGURE_ARGS="" ;;
esac

RELEASE_CONFIGURE_ARGS="$DEFAULT_CONFIGURE_ARGS"
DEV_CONFIGURE_ARGS="$DEFAULT_CONFIGURE_ARGS"

####################################################################
# edit configuration here:

: ${REBUILD:=0} # set to 1 to force rebuild
: ${RELEASE:=0} # set to 1 to build release version including documentation (more build dependencies)

# program locations
: ${GHC:=$(command -v ghc-9.6.7 2>/dev/null || true)}
: ${CABAL:=$(command -v cabal 2>/dev/null || true)}
: ${PYTHON:=$(command -v python3 2>/dev/null || true)}
: ${HAPPY:=$( [ -x "$LOCAL_HAPPY" ] && echo "$LOCAL_HAPPY" || command -v happy-1.20.1.1 2>/dev/null || true)}
: ${ALEX:=$( [ -x "$LOCAL_ALEX" ] && echo "$LOCAL_ALEX" || command -v alex 2>/dev/null || true)}
: ${TAR:=$(command -v tar 2>/dev/null || true)}
: ${XZ:=$(command -v xz 2>/dev/null || true)}

# override default arguments
: ${HADRIAN_ARGS:=$( [ "$RELEASE" -eq 1 ] && echo "$RELEASE_HADRIAN_ARGS" || echo "$DEV_HADRIAN_ARGS" )}
: ${CONFIGURE_ARGS:=$( [ "$RELEASE" -eq 1 ] && echo "$RELEASE_CONFIGURE_ARGS" || echo "$DEV_CONFIGURE_ARGS" )}
: ${FLAVOUR:=$( [ "$RELEASE" -eq 1 ] && echo "$RELEASE_FLAVOUR" || echo "$DEV_FLAVOUR" )}

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

if [ -z "$TAR" ] || [ ! -x "$TAR" ]; then
  echo "tar not found"
  exit 1
fi
if [ -z "$XZ" ] || [ ! -x "$XZ" ]; then
  echo "xz not found"
  exit 1
fi
if [ -z "$PYTHON" ] || [ ! -x "$PYTHON" ]; then
  echo "python3 not found"
  exit 1
fi

export GHC
export CABAL
export HAPPY
export ALEX
export PYTHON

echo "using tools: "
echo " GHC:    $GHC"
echo " cabal:  $CABAL ($CABAL_VERSION)"
echo " happy:  $HAPPY"
echo " alex:   $ALEX"
echo " python: $PYTHON"
echo " tar:    $TAR"
echo " xz:     $XZ"

####################################################################
# do the things

BASE=$PWD

# check plutus
if [ ! -d plutus/plutus-tx ]; then
  echo "plutus submodule not found, please fetch submodules"
  exit 1
fi
# build boot GHC
DID_BOOT_OR_CONFIGURE=0
if [ ! -x ./configure ] || [ "$REBUILD" -eq 1 ]; then
  echo "booting..."
  ./boot
  DID_BOOT_OR_CONFIGURE=1
fi
if [ ! -e ./mk/config.h ] || [ "$REBUILD" -eq 1 ]; then
  echo "configuring..."
  (
  # On Windows/MinGW64, ensure we use the CA bundle from MSYS2 to avoid SSL errors when downloading tarballs
  if [ "$IS_WINDOWS" -eq 1 ]; then
      export SSL_CERT_FILE="$(cygpath -w /mingw64/etc/ssl/certs/ca-bundle.crt)"
  fi
  ./configure $CONFIGURE_ARGS
  )
  DID_BOOT_OR_CONFIGURE=1
fi

# On Windows, plinth/ghc must be a real symlink to ../ghc
if [ "$IS_WINDOWS" -eq 1 ] && [ ! -L plinth/ghc ]; then
    echo "error: plinth/ghc is not a symlink."
    echo ""
    # Check Developer Mode via PowerShell (the registry key location varies across Windows versions)
    DEV_MODE=$(powershell.exe -NoProfile -Command "(Get-WindowsDeveloperLicense).IsValid" 2>/dev/null | tr -d '\r')
    [ "$DEV_MODE" = "True" ] && DEV_MODE=1 || DEV_MODE=0
    if [ "$DEV_MODE" != "1" ]; then
        echo "  Windows Developer Mode is not enabled."
        echo "  Enable it in: Settings > System > Advanced"
        echo ""
    fi
    SYMLINKS_CFG=$(git config --get core.symlinks 2>/dev/null || echo "false")
    if [ "$SYMLINKS_CFG" != "true" ]; then
        echo "  git core.symlinks is not enabled."
        echo "  Run: git config core.symlinks true"
        echo ""
    fi
    if [ "$DEV_MODE" = "1" ] && [ "$SYMLINKS_CFG" = "true" ]; then
        echo "  Developer Mode and core.symlinks are both enabled, but plinth/ghc"
        echo "  is still not a symlink. Try re-checking out the path:"
        echo "    rm -rf plinth/ghc && git checkout -- plinth/ghc"
        echo ""
    fi
    echo "After fixing, re-run this script."
    exit 1
fi

if [ ! -x ./_build/stage1/bin/ghc ] || [ "$REBUILD" -eq 1 ]; then
  echo "building..."
  echo "./hadrian/build -j --flavour=$FLAVOUR $HADRIAN_ARGS binary-dist-dir"

  ./hadrian/build -j --flavour=$FLAVOUR $HADRIAN_ARGS binary-dist-dir
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

# On Windows/MinGW64, ensure we use Git for Windows (not MSYS2 git) and
# prevent git from hanging on interactive credential/host-key prompts
# when called as a subprocess by cabal.
if [ "$IS_WINDOWS" -eq 1 ]; then
    if [ -d "/c/Program Files/Git/bin" ]; then
        export PATH="/c/Program Files/Git/bin:$PATH"
    fi
    export GIT_TERMINAL_PROMPT=0
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="core.longpaths"
    export GIT_CONFIG_VALUE_0="true"
fi

(
    echo "building uplc-ghc"
    cd plinth
    echo "cabal update..."
    "$CABAL" ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} update
    echo "cabal build..."
    "$CABAL" ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} build ${CABAL_BUILD_ARGS} ghc:ghc
)

# add uplc-ghc to the _build dir and the bindists
CWRAPPER_DIR="$BASE/hadrian/bindist/cwrappers"

DEST_UPLC_GHC="$BASE/_build/stage1/bin/uplc-ghc${EXE_EXT}"

(
    cd plinth
    SRC_UPLC_GHC=$("$CABAL" ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} list-bin ${CABAL_BUILD_ARGS} ghc:ghc)
    echo "installing uplc-ghc: $SRC_UPLC_GHC => $DEST_UPLC_GHC"

    # add to build dir
    cp "$SRC_UPLC_GHC" "$DEST_UPLC_GHC"

    # fixup the bindist:
    #  - add uplc-ghc with the static Plinth plugin
    #  - remove boot GHC, since we don't want the UPLC GHC to replace the user's GHC
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

            # Add wrapper scripts so `make install` creates $PREFIX/bin/uplc-ghc
            mkdir -p "$dir/wrappers"
            echo 'exec "$executablename" -B"$libdir" ${1+"$@"}' > "$dir/wrappers/uplc-ghc-$VERSION"
            ( cd "$dir/wrappers" && ln -sf "uplc-ghc-$VERSION" "uplc-ghc" )

            # remove the boot GHC from the bindist
            rm -f "$dir"/bin/ghc
            rm -f "$dir"/bin/ghc.exe
            rm -f "$dir"/bin/ghc-$VERSION
            rm -f "$dir"/bin/ghc-$VERSION.exe
            # rename runhaskell/runghc
            mv -f "$dir"/bin/runhaskell "$dir"/bin/uplc-runhaskell 2>/dev/null || true
            mv -f "$dir"/bin/runghc "$dir"/bin/uplc-runghc 2>/dev/null || true
            # XXX wrappers on Windows, other tools like unlit need to be renamed?
        fi
    done
)

# Detect C library (musl vs glibc) on Linux
LIBC_SUFFIX=""
case "$UNAME_S" in
    Linux*)
        if ldd --version 2>&1 | grep -qi musl; then
            LIBC_SUFFIX="-musl"
        fi
        ;;
esac

# create bindist archive after fixup
echo "creating bindist archive..."
BINDIST_NAME="ghc-$VERSION-$TARGET_PLATFORM${LIBC_SUFFIX}"
BINDIST_TARBALL="$BASE/_build/bindist/$BINDIST_NAME.tar.xz"
(cd "$BASE/_build/bindist" && "$TAR" -cf - "$BINDIST_NAME" | "$XZ" > "$BINDIST_NAME.tar.xz")

# generate ghcup metadata for the bindist
# See Note [Ghcup metadata generation] below
echo "generating ghcup metadata..."

TARBALL_HASH=$(sha256sum "$BINDIST_TARBALL" | cut -d' ' -f1)
TARBALL_URI="file://$BINDIST_TARBALL"

# map target platform to ghcup architecture/platform identifiers
ARCH_COMPONENT=$(echo "$TARGET_PLATFORM" | cut -d'-' -f1)
case "$ARCH_COMPONENT" in
    x86_64)        GHCUP_ARCH="A_64" ;;
    i386|i686)     GHCUP_ARCH="A_32" ;;
    aarch64)       GHCUP_ARCH="A_ARM64" ;;
    armv7l)        GHCUP_ARCH="A_ARM" ;;
    *)             echo "warning: unknown architecture $ARCH_COMPONENT, defaulting to A_64"
                   GHCUP_ARCH="A_64" ;;
esac

case "$UNAME_S" in
    MINGW*|MSYS*) GHCUP_PLATFORM="Windows" ;;
    Darwin*)      GHCUP_PLATFORM="Darwin" ;;
    *)
        if [ -n "$LIBC_SUFFIX" ]; then
            GHCUP_PLATFORM="Linux_Alpine"
        else
            GHCUP_PLATFORM="Linux_UnknownLinux"
        fi
        ;;
esac

METADATA_FILE="$BASE/_build/bindist/$BINDIST_NAME-ghcup-metadata.yaml"

cat > "$METADATA_FILE" <<METADATA_EOF
toolRequirements: {}
ghcupDownloads:
  plinth:
    $VERSION:
      viTags: []
      viArch:
        $GHCUP_ARCH:
          $GHCUP_PLATFORM:
            unknown_versioning:
              dlHash: $TARBALL_HASH
              dlSubdir: $BINDIST_NAME
              dlUri: $TARBALL_URI
              dlInstallInfo:
                configArgs:
                  - "--prefix=\${PREFIX}"
                configFile: "configure"
                makeArgs: ["DESTDIR=\${TMPDIR}", "install"]
                preserveMtimes: True
                exeSymLinked:
                  - ["bin/hsc2hs", "uplc-hsc2hs"]
                  - ["bin/haddock", "uplc-haddock"]
                  - ["bin/hpc", "uplc-hpc"]
                  - ["bin/uplc-ghc", "uplc-ghc"]
                  - ["bin/ghc-pkg", "uplc-ghc-pkg"]
                  - ["bin/hp2ps", "uplc-hp2ps"]
METADATA_EOF

echo "ghcup metadata written to: $METADATA_FILE"
echo "  tarball hash: $TARBALL_HASH"
echo "  tarball URI:  $TARBALL_URI"

