---
layout: default
title: Overview
nav_order: 1
---

# Plinth Standalone Compiler

A fork of [GHC](https://www.haskell.org/ghc/) that embeds the
[Plinth][plinth] compiler, used to write smart contracts for the
[Cardano][cardano] blockchain.

Plinth (formerly known as Plutus Tx) is a subset of Haskell compiled to
**Plutus Core**. In this fork the Plinth compiler is shipped as a built-in
GHC Core plugin, producing a self-contained compiler called **`uplc-ghc`**:
compiling a module that defines Plinth code yields Plutus Core in addition to
the usual GHC outputs.

## Why a fork of GHC?

Plinth is normally compiled by loading the `plutus-tx-plugin` as an ordinary
GHC plugin. This fork instead bakes the plugin in as a built-in *static*
plugin. The result, `uplc-ghc`, behaves like a regular GHC but emits Plutus
Core for Plinth modules without any extra plugin configuration on the user's
side.

## Where to go next

- [Building from source]({{ '/build' | relative_url }}) — clone the repository and run `plinth-build.sh`.
- [Using uplc-ghc]({{ '/usage' | relative_url }}) — point your project at the produced compiler.
- [Testing &amp; benchmarks]({{ '/testing' | relative_url }}) — run the example project and golden benchmarks.
- [Examples]({{ '/examples' | relative_url }}) — the bundled Plinth example project and its Plutus Core output.

## External documentation

- [Plinth user guide][plinth]
- [Plutus / Plinth GitHub repository][plutus-repo]
- [Plinth project template][plinth-template]

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
[cardano]: https://cardano.org/
[plutus-repo]: https://github.com/IntersectMBO/plutus
[plinth-template]: https://github.com/IntersectMBO/plinth-template
