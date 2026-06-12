---
title: Build outputs
permalink: /reference/build-outputs/
---
What `plinth-build.sh` produces.

## The compiler

The development build of the Plinth compiler is installed at:

```
_build/stage1/bin/uplc-ghc
```

This is the binary you pass to cabal with `-w` (see
[Use uplc-ghc in a project]({% link how-to/use.md %})).

## Binary distribution archive

A relocatable binary distribution is produced under `_build/bindist/`:

```
_build/bindist/ghc-<version>-<platform>.tar.xz
```

The build script fixes up the bindist so that it ships `uplc-ghc` (with the
built-in Plinth static plugin) instead of the boot GHC:

- `uplc-ghc` is added (as `uplc-ghc-<version>` plus an `uplc-ghc` wrapper).
- The boot `ghc` binary is removed, so installing the bindist does not replace
  a user's existing GHC.
- `runghc` and `runhaskell` are renamed to `uplc-runghc` and
  `uplc-runhaskell`.

Installing the bindist therefore creates `$PREFIX/bin/uplc-ghc`.
