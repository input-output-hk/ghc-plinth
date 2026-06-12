---
title: Environment variables
permalink: /reference/environment-variables/
---
Variables that change the behaviour of the helper scripts.

## plinth-build.sh

| Variable    | Default | Effect                                                        |
| ----------- | ------- | ------------------------------------------------------------- |
| `REBUILD`   | `0`     | Set to `1` to force a full rebuild (re-boot, re-configure).   |
| `RELEASE`   | `0`     | Set to `1` to build the release flavour including documentation (more build dependencies). |

The build script also honours tool-location overrides such as `GHC`, `CABAL`,
`HAPPY`, `ALEX`, and `PYTHON`, as well as `HADRIAN_ARGS`, `CONFIGURE_ARGS`, and
`FLAVOUR`, when you need to point it at specific tools or change the build
flavour.

## plinth-test.sh

| Variable | Default | Effect                                          |
| -------- | ------- | ----------------------------------------------- |
| `CLEAN`  | `0`     | Set to `1` to remove the test build dir first.  |
