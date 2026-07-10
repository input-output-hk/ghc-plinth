#!/usr/bin/env bash
set -euo pipefail

: ${CLEAN:=0} # set to 1 to force rebuild
# Number of parallel cabal jobs. Empty means "-j" (all cores). Compiling with
# the Plinth plugin (Core -> PLC) is memory-heavy, so on RAM-constrained
# machines (e.g. CI runners) several concurrent GHC processes can OOM. Set
# JOBS=1 there to build packages serially.
: ${JOBS:=}

# Note [Plinth compiler test coverage]
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The example project (plinth/test) is only a smoke test: it checks that
# uplc-ghc compiles a couple of real validators end-to-end. The thorough
# coverage of the Plinth compiler lives in plutus-tx-plugin's own test-suites
# (golden PIR/UPLC + evaluation + budget + property + error-message tests) --
# the same suites upstream CI runs against the external plugin. We run them here
# under uplc-ghc so the built-in compiler is exercised as thoroughly as the
# upstream plugin.
#
# Expect two kinds of failures until goldens are regenerated for this toolchain:
#  - benign golden PIR/UPLC (and consequent budget .eval) diffs: equivalent
#    output, just codegen drift between the patched-vs-stock GHC front-end;
#  - real behavioural failures: the non-golden eval/property/trace tests.
#
# Override PLUGIN_TESTS to run a different set of suites, e.g.:
#   PLUGIN_TESTS="plutus-tx-plugin:plutus-tx-plugin-tests \
#                 plutus-tx-plugin:plutus-ledger-api-plugin-test \
#                 plutus-tx-plugin:frontend-plugin-tests \
#                 plutus-tx-plugin:size \
#                 plutus-tx:plutus-tx-test"
# Set PLUGIN_TESTS= (empty) to skip the compiler suites and only run the
# example smoke test.
: ${PLUGIN_TESTS:="plutus-tx-plugin:plutus-tx-plugin-tests"}


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

# Note [Dynamic way on macOS]
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~
# uplc-ghc forces -fexternal-interpreter (see ghc/Main.hs), so every TH splice
# runs in ghc-iserv. In the default (static) way, iserv loads the whole
# dependency closure with the RTS in-memory linker, which is fragile on
# aarch64-darwin: plutus-tx-plugin-tests reliably kills it with SIGBUS
# ("ghc-iserv terminated (-10)"). Building the shared way (--enable-shared)
# makes GHC spawn ghc-iserv-dyn instead, which loads .dylibs through the system
# loader (dyld) and bypasses the RTS linker -- the same reason stock GHC on
# darwin is dynamic by default. The bindist ships ghc-iserv-dyn and the shared
# boot libraries on all non-Windows platforms.
case "$UNAME_S" in
    Darwin*) WAY_ARGS="--enable-shared --enable-executable-dynamic" ;;
    *)       WAY_ARGS="" ;;
esac

CABAL_ARGS="\
	--remote-repo-cache _build/packages \
	--store-dir=_build/store \
	--logs-dir=_build/logs"

CABAL_BUILD_ARGS="\
	-j${JOBS} -w ${GHC} \
	--builddir=_build/build \
	${WAY_ARGS} \
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

    # Run the Plinth compiler test-suites under uplc-ghc.
    # See Note [Plinth compiler test coverage].
    if [ -n "${PLUGIN_TESTS}" ]; then
        echo ""
        echo "Running Plinth compiler test-suites under uplc-ghc:"
        echo "  ${PLUGIN_TESTS}"
        echo ""
        # --test-show-details=direct streams tasty's per-test results and golden
        # diffs to stdout; --keep-going runs every suite even if one fails.
        #
        # No --enable-tests: it would enable the test stanzas of EVERY local
        # package, including plutus-metatheory whose tests need
        # plutus-core:untyped-plutus-core-testlib, a component that is not
        # buildable on Windows -- the solver then fails before running
        # anything. The explicitly named PLUGIN_TESTS components get their
        # stanzas enabled by target selection alone.
        set +e
        cabal ${CABAL_PROJECT_ARGS} ${CABAL_ARGS} test ${CABAL_BUILD_ARGS} \
            --test-show-details=direct \
            --keep-going \
            ${PLUGIN_TESTS}
        RC=$?
        set -e
        echo ""
        if [ $RC -eq 0 ]; then
            echo "plinth-test: all Plinth compiler tests passed (exit $RC)"
        else
            echo "plinth-test: some Plinth compiler tests failed (exit $RC)"
            echo "See Note [Plinth compiler test coverage] in plinth-test.sh:"
            echo "golden PIR/UPLC diffs are expected codegen drift; real"
            echo "regressions are the non-golden eval/property/trace tests."
        fi
        exit $RC
    fi
)
