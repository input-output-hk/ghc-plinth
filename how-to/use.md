---
title: Use uplc-ghc in a project
permalink: /how-to/use/
---
The build produces `uplc-ghc`, a GHC that ships the Plinth plugin as a built-in
static plugin. Use it as the compiler for a Plinth project.

## Point cabal at uplc-ghc

The recommended way is to set the compiler once in `cabal.project`. The same
file also needs the Cardano package repository (CHaP), which provides the Plinth
libraries (`plutus-tx`, `plutus-core`, and friends &mdash; they are not bundled
with the compiler):

```haskell
with-compiler: /path/to/uplc-ghc

packages: .

repository cardano-haskell-packages
  url: https://chap.intersectmbo.org/
  secure: True
  root-keys:
    3e0cce471cf09815f930210f7827266fd09045445d65923e6d0238a6cd15126f
    443abb7fb497a134c343faf52f0b659bd7999bc06b7f63fa76dc99d631f9bea1
    a86a1f6ce86c449c46666bda44268677abf29b5b2d2eb5ec7af903ec2f117a82
    bcec67e8e99cabfa7764d75ad9b158d72bfacf70ca1d0ec8bc6b4406d1bf8413
    c00aae8461a256275598500ea0e187588c35a5d5d7454fb57eac18d9edb86a56
    d4a35cd3121aa00d18544bb0ac01c3e1691d618f462c46129271bccf39f7e8ee

index-state:
  , hackage.haskell.org 2025-09-21T21:31:06Z
  , cardano-haskell-packages 2026-01-24T11:25:12Z
```

Adapt the two `index-state` dates to your project: they pin the package set, and
the right values depend on the `plutus-tx` version your `uplc-ghc` targets.
Then build as usual:

```console
$ cabal build
```

Alternatively, you can pass the compiler per command with `-w` (you still need
the `cabal.project` above for the CHaP repository):

```console
$ cabal build -w /path/to/uplc-ghc
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
