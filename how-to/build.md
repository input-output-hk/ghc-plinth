---
title: Install Plinth standalone compiler
permalink: /how-to/build/
---
This guide explains how to get `uplc-ghc`, the
[Plinth standalone compiler]({% link explanation/standalone-compiler.md %}).

## Installing via ghcup

*Coming soon.* Installing `uplc-ghc` through
[ghcup](https://www.haskell.org/ghcup/) &mdash; the standard installer for
Haskell toolchains &mdash; is planned but not yet available. Until then, build
from source as described below.

## Building from source

This assumes the [prerequisites]({% link reference/prerequisites.md %}) are on
your `PATH`.

### 1. Clone with submodules

The `plutus` submodule provides `plutus-tx`, `plutus-tx-plugin`, and
`plutus-core`, so clone recursively:

```console
$ git clone --recurse-submodules git@github.com:input-output-hk/ghc-plinth.git
```

If you already cloned without `--recurse-submodules`, fetch them with:

```console
$ git submodule update --init --recursive
```

### 2. Run the build script

From the root of the repository:

```console
$ ./plinth-build.sh
```

The script bootstraps GHC and then builds `uplc-ghc`. When it finishes, the
compiler is at `_build/stage1/bin/uplc-ghc` and a binary distribution archive
is under `_build/bindist/` (see [Build outputs]({% link reference/build-outputs.md %})).

### Force a full rebuild

Set `REBUILD=1` to re-boot, re-configure, and rebuild from scratch:

```console
$ REBUILD=1 ./plinth-build.sh
```

### Build a release (with documentation)

Set `RELEASE=1` to build the release flavour, which also builds the
documentation (and pulls in more build dependencies):

```console
$ RELEASE=1 ./plinth-build.sh
```

See [Environment variables]({% link reference/environment-variables.md %}) for
the full list of knobs.
