---
title: Use uplc-ghc in a project
permalink: /how-to/use/
---
The build produces `uplc-ghc`, a GHC that ships the Plinth plugin as a built-in
static plugin. Use it as the compiler for a Plinth project.

## Point cabal at uplc-ghc

The recommended way is to set the compiler once in `cabal.project`, so every
cabal command in the project uses it:

```
with-compiler: _build/stage1/bin/uplc-ghc
packages: .
```

Then build as usual:

```console
$ cabal build
```

Alternatively, you can pass `uplc-ghc` per command with `-w` &mdash; handy for a
quick try without editing `cabal.project`:

```console
$ cabal build -w _build/stage1/bin/uplc-ghc
```

Either way, compiling a module that defines Plinth code yields Plutus Core in
addition to the usual GHC outputs &mdash; no extra plugin configuration is
required, because the Plinth plugin is built into the compiler.

## Start from the project template

For a ready-made project layout, clone the
[Plinth project template][plinth-template] and build it with `uplc-ghc` as
above. For how to write and structure Plinth code, consult the
[Plinth user guide][plinth].

If you would rather see a worked example before starting your own project, walk
through [Your first smart contract with Plinth]({% link tutorials/first-smart-contract.md %}).

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
[plinth-template]: https://github.com/IntersectMBO/plinth-template
