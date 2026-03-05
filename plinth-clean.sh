#!/usr/bin/env bash
set -euo pipefail

# Clean all build directories created by plinth-build.sh
#
# Usage:
#   ./plinth-clean.sh          # clean everything
#   ./plinth-clean.sh plinth   # clean only the plinth (cabal) build
#   ./plinth-clean.sh ghc      # clean only the GHC (hadrian) build
#   ./plinth-clean.sh tools    # clean only locally built tools (happy, alex)

what="${1:-all}"

case "$what" in
    plinth)
        echo "Cleaning plinth build..."
        rm -rf _build/stage-plinth
        (cd plinth && rm -rf dist-newstyle)
        ;;
    ghc)
        echo "Cleaning GHC build..."
        rm -rf _build/stage0 _build/stage1 _build/bindist
        # clean configure artifacts
        rm -f mk/config.h mk/config.mk config.log config.status
        ;;
    tools)
        echo "Cleaning locally built tools..."
        rm -rf _build/tools
        ;;
    all)
        echo "Cleaning all build directories..."
        rm -rf _build
        (cd plinth && rm -rf dist-newstyle)
        # clean configure artifacts
        rm -f mk/config.h mk/config.mk config.log config.status
        ;;
    *)
        echo "Usage: $0 [all|ghc|plinth|tools]"
        exit 1
        ;;
esac

echo "Done."
