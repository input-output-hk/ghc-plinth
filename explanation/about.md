---
layout: default
title: About Plinth and this fork
parent: Explanation
nav_order: 3
---

# About Plinth and this fork

[Plinth][plinth] (formerly known as Plutus Tx) is a subset of Haskell used to
write smart contracts for the [Cardano][cardano] blockchain. Plinth code is
compiled to **Plutus Core**, the low-level language the Cardano ledger
actually executes on-chain.

Because Plinth is a subset of Haskell, it is compiled by GHC: a GHC plugin
intercepts the relevant definitions during compilation and translates them to
Plutus Core. In a normal setup that plugin (`plutus-tx-plugin`) is loaded into
GHC as an ordinary, user-supplied plugin.

## What this fork provides

This repository is a fork of GHC that bundles the Plinth compiler directly,
producing a self-contained compiler called **`uplc-ghc`**. Compiling a module
that defines Plinth code with `uplc-ghc` yields Plutus Core in addition to the
usual GHC outputs.

The fork tracks an upstream GHC release and adds the Plinth integration on top;
the `plutus` submodule supplies `plutus-tx`, `plutus-tx-plugin`, and
`plutus-core`.

For the details of *how* the plugin is integrated, see
[The built-in static plugin]({% link explanation/static-plugin.md %}).

## Further reading

- [Plinth user guide][plinth]
- [Plutus / Plinth GitHub repository][plutus-repo]
- [Plinth project template][plinth-template]

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
[cardano]: https://cardano.org/
[plutus-repo]: https://github.com/IntersectMBO/plutus
[plinth-template]: https://github.com/IntersectMBO/plinth-template
