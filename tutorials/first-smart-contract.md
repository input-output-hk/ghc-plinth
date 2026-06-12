---
layout: default
title: Your first smart contract with Plinth
parent: Tutorials
nav_order: 1
---

# Your first smart contract with Plinth

In this tutorial you will compile a real smart contract to Plutus Core using
the Plinth compiler, and look at the result. By the end you will have built the
bundled example project with `uplc-ghc` and seen the Plutus Core it produces.

You do not need to write any code: everything you need ships with the
repository.

## Before you start

You need a built `uplc-ghc`. If you have not built it yet, follow
[Build the compiler from source]({% link how-to/build.md %}) first &mdash; this
tutorial waits for you here.

You will also need the `plutus` submodule, which is fetched automatically when
you clone with `--recurse-submodules`.

## Step 1: Meet the example project

The repository bundles a small Plinth project under `plinth/test/`, adapted
from the [Plinth project template][plinth-template]. Its smart-contract sources
live in `plinth/test/src/`:

- **`AuctionValidator.hs`** &mdash; a *spending validator* for a simple
  auction. This is the on-chain script that decides whether a transaction is
  allowed to spend the auction's funds.
- **`AuctionMintingPolicy.hs`** &mdash; a *minting policy* paired with the
  auction, controlling when the associated tokens may be minted.
- **`Examples.hs`** &mdash; small standalone Plinth snippets.
- **`Utils.hs`** &mdash; helpers shared across the examples.

These are ordinary Haskell modules: what makes them Plinth is that
`uplc-ghc` compiles their Plinth definitions all the way down to Plutus Core.

## Step 2: Compile the contracts

From the root of the repository, run:

```console
$ ./plinth-test.sh
```

This builds the example project with `uplc-ghc` and then runs its
`gen-examples` program, which writes the compiled Plutus Core to disk. The
first run downloads and builds dependencies, so expect it to take a while.

If you want to start from a clean slate, set `CLEAN=1`:

```console
$ CLEAN=1 ./plinth-test.sh
```

## Step 3: Look at the Plutus Core

The compiled output lands in `plinth/test/examples-output/`. Open one of the
generated files to see real Plutus Core:

```console
$ cat plinth/test/examples-output/succ.uplc
```

You are looking at the on-chain code that the Cardano ledger would actually
execute &mdash; produced from Haskell by `uplc-ghc`. The companion file
`eqCheck.uplc` is generated the same way.

## Step 4 (optional): Generate the validator blueprints

The project also ships blueprint generators under `plinth/test/app/`
(`GenAuctionValidatorBlueprint.hs`, `GenMintingPolicyBlueprint.hs`,
`GenExamples.hs`). These produce the CIP-57 blueprints that off-chain tooling
uses to interact with the compiled validators &mdash; a good thread to pull on
once you are comfortable.

## Where to go next

- [Use uplc-ghc in a project]({% link how-to/use.md %}) &mdash; point your own
  project at the compiler instead of the bundled example.
- [The built-in static plugin]({% link explanation/static-plugin.md %}) &mdash;
  understand what `uplc-ghc` is doing under the hood.
- [Plinth user guide][plinth] &mdash; learn to write Plinth code of your own.

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
[plinth-template]: https://github.com/IntersectMBO/plinth-template
