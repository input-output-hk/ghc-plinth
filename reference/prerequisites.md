---
title: Prerequisites
permalink: /reference/prerequisites/
---
`plinth-build.sh` expects the following tools on `PATH`:

| Tool      | Requirement                                          |
| --------- | ---------------------------------------------------- |
| `ghc`     | boot compiler `ghc-9.6.7`                            |
| `cabal`   | `>= 3.14.2.0`                                         |
| `happy`   | `happy-1.20.1.1` (built locally if missing)          |
| `alex`    | `alex-3.5.4.0` (built locally if missing)            |
| `python3` | required by Hadrian                                  |
| `tar`     | required to produce the binary distribution archive  |
| `xz`      | required to compress the binary distribution archive |

`happy` and `alex` are built locally into `_build/tools/` if they are not
found, so they are effectively optional. The others must be present.
