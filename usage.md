---
layout: default
title: Using uplc-ghc
nav_order: 3
---

# Using uplc-ghc

The build produces `uplc-ghc`, a GHC that ships the Plinth plugin as a
built-in static plugin. Use it as the compiler for a Plinth project, for
example by pointing `cabal` at it:

```console
$ cabal build -w _build/stage1/bin/uplc-ghc
```

Compiling a module that defines Plinth code then yields Plutus Core in
addition to the usual GHC outputs.

## Starting a project

For a ready-made project layout to start from, see the
[Plinth project template][plinth-template]. For how to write and compile
Plinth code, consult the [Plinth user guide][plinth].

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
[plinth-template]: https://github.com/IntersectMBO/plinth-template
