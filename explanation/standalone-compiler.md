---
title: "The Plinth standalone compiler"
permalink: /explanation/standalone-compiler/
---
[Plinth][plinth] (formerly known as Plutus Tx) is a subset of Haskell used to
write smart contracts for the [Cardano][cardano] blockchain. Plinth code is
compiled to **Plutus Core**, the low-level language the Cardano ledger actually
executes on-chain. Because Plinth is a subset of Haskell, it is compiled by GHC.

## From a plugin to a compiler

Plinth was previously distributed as a **GHC plugin** (`plutus-tx-plugin`): you
used a stock GHC and added the plugin to your project, and during compilation it
intercepted the relevant definitions and translated them to Plutus Core.

This repository takes a different approach. It is a fork of GHC with the Plinth
plugin **wired in**, producing a single self-contained compiler called
**`uplc-ghc`**. There is no separate plugin to install or configure: `uplc-ghc`
behaves like an ordinary GHC, and when a module defines Plinth code it emits the
corresponding Plutus Core alongside the usual outputs.

The fork tracks an upstream GHC release and adds the Plinth integration on top;
the `plutus` submodule supplies `plutus-tx`, `plutus-tx-plugin`, and
`plutus-core`.

## Why a standalone compiler

Shipping a dedicated compiler, rather than a plugin you add to someone else's
GHC, brings several benefits:

- **Simpler setup.** Users deal with one tool instead of a GHC plus a matched
  plugin package and `-fplugin` flags. Pointing cabal at `uplc-ghc` (see
  [Use uplc-ghc in a project]({% link how-to/use.md %})) is all that is needed,
  and the Plinth machinery stays invisible until a module actually defines Plinth
  code.
- **Freedom to adapt GHC.** Because the compiler is ours, we can change GHC
  itself to suit Plinth rather than working within the limits of the plugin
  interface &mdash; better diagnostics, error messages, and developer experience.
- **Prebuilt boot libraries with Plinth support.** The compiler ships with its
  boot libraries already built for Plinth, so their definitions compile to Plutus
  Core out of the box instead of every user rebuilding them.
- **Reproducibility.** The Plinth-to-Plutus-Core translation is sensitive to how
  GHC compiles the surrounding code (optimisation passes, inlining, and so on).
  Pinning the plugin to a specific GHC build keeps compiler and plugin in
  lockstep, which makes the generated Plutus Core reproducible and lets the whole
  thing be validated as a single unit (see the test and benchmark scripts in
  [Build Plinth from source]({% link how-to/build.md %}#test-and-benchmark)).

## Further reading

- [Plinth user guide][plinth]
- [Plutus / Plinth GitHub repository][plutus-repo]
- [Plinth project template][plinth-template]

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
[cardano]: https://cardano.org/
[plutus-repo]: https://github.com/IntersectMBO/plutus
[plinth-template]: https://github.com/IntersectMBO/plinth-template
