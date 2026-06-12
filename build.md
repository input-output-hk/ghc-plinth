---
layout: default
title: Building from source
nav_order: 2
---

# Building from source

## Clone the repository

Clone together with its submodules. The `plutus` submodule provides
`plutus-tx`, `plutus-tx-plugin`, and `plutus-core`:

```console
$ git clone --recurse-submodules git@github.com:input-output-hk/ghc-plinth.git
```

If you already cloned without `--recurse-submodules`, fetch them with:

```console
$ git submodule update --init --recursive
```

## Build

Run the `plinth-build.sh` script at the root of the repository:

```console
$ ./plinth-build.sh
```

The script bootstraps GHC and then builds the Plinth-enabled compiler,
`uplc-ghc`.

## Prerequisites

The script expects the following tools on `PATH`:

| Tool      | Requirement                                          |
| --------- | ---------------------------------------------------- |
| `ghc`     | boot compiler `ghc-9.6.7`                            |
| `cabal`   | `>= 3.14.2.0`                                         |
| `happy`   | `happy-1.20.1.1` (built locally if missing)          |
| `alex`    | `alex-3.5.4.0` (built locally if missing)            |
| `python3` | required by Hadrian                                  |
| `tar`     | required to produce the binary distribution archive  |
| `xz`      | required to compress the binary distribution archive |

## Environment knobs

| Variable    | Effect                                                          |
| ----------- | --------------------------------------------------------------- |
| `REBUILD=1` | Forces a full rebuild (re-boot, re-configure, rebuild).         |
| `RELEASE=1` | Builds a release flavour including documentation (more deps).   |

## Output

A binary distribution archive is produced under `_build/bindist/`:

```
_build/bindist/ghc-<version>-<platform>.tar.xz
```

The development build of the compiler itself lives at
`_build/stage1/bin/uplc-ghc`.
