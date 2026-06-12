---
title: Overview
permalink: /
---
A fork of [GHC](https://www.haskell.org/ghc/) that embeds the
[Plinth][plinth] compiler, used to write smart contracts for the
[Cardano][cardano] blockchain. Plinth (formerly Plutus Tx) is a subset of
Haskell compiled to **Plutus Core**; this fork ships the compiler as a
built-in static GHC plugin, producing a self-contained compiler called
**`uplc-ghc`**.

## Finding your way around

This documentation follows the [Diataxis](https://diataxis.fr/) framework,
which separates docs into four kinds by what you need from them:

- **[Tutorials]({% link tutorials/index.md %})** &mdash; *learning-oriented.*
  Start here if you are new: a hands-on lesson that walks you through compiling
  your first smart contract.
- **[How-to guides]({% link how-to/index.md %})** &mdash; *task-oriented.*
  Practical recipes for a specific job: build the compiler, use it in a
  project, test and benchmark it.
- **[Reference]({% link reference/index.md %})** &mdash; *information-oriented.*
  The dry facts: required tools, environment variables, build outputs.
- **[Explanation]({% link explanation/index.md %})** &mdash;
  *understanding-oriented.* Background and discussion: what Plinth is and how
  this fork works.

## External documentation

- [Plinth user guide][plinth]
- [Plutus / Plinth GitHub repository][plutus-repo]
- [Plinth project template][plinth-template]

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
[cardano]: https://cardano.org/
[plutus-repo]: https://github.com/IntersectMBO/plutus
[plinth-template]: https://github.com/IntersectMBO/plinth-template
