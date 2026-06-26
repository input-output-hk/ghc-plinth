#!/bin/sh
# Shared Alpine/musl CI setup for the musl build and test jobs: install the
# build/test dependencies and a musl boot-GHC + cabal via ghcup.
#
# Meant to be SOURCED (`. ./.github/alpine-setup.sh`) from inside the `docker
# run alpine:3.20` bodies, not executed, so the ghcup environment it sets up
# persists into the caller's shell.
set -eu

apk update
apk add alpine-sdk autoconf automake bash build-base coreutils \
  curl gcc g++ git gmp gmp-dev grep linux-headers gzip \
  ncurses-dev ncurses-libs ncurses-static \
  perl python3 py3-sphinx xz zlib-dev zlib-static findutils file binutils

curl --proto "=https" --tlsv1.2 -sSf https://get-ghcup.haskell.org | \
  BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
  BOOTSTRAP_HASKELL_GHC_VERSION=9.6.7 \
  BOOTSTRAP_HASKELL_CABAL_VERSION=latest sh
. "$HOME/.ghcup/env"

git config --global --add safe.directory /workspace
