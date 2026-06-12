---
title: Your first smart contract with Plinth
permalink: /tutorials/first-smart-contract/
---
In this tutorial you will compile a real smart contract to Plutus Core using
the Plinth compiler, and look at the result. By the end you will have cloned the
[Plinth project template][plinth-template], built it with `uplc-ghc`, and
generated a CIP-57 blueprint from the compiled validator.

You do not need to write any code: the example ships with the template project.

## Before you start

You need a built `uplc-ghc`. If you have not built it yet, follow
[Build the compiler from source]({% link how-to/build.md %}) first &mdash; this
tutorial waits for you here. Note where the `uplc-ghc` binary ended up; you will
point cabal at it below. Throughout this tutorial, replace `/path/to/uplc-ghc`
with the actual path to your `uplc-ghc`.

You will also need `git` and a recent `cabal` (3.8 or newer) on your `PATH`.

## Step 1: Get the example

The example contract lives in its own repository, the Plinth project template.
Clone it anywhere you like:

```console
$ git clone https://github.com/IntersectMBO/plinth-template.git
$ cd plinth-template
```

The rest of this tutorial runs from inside this `plinth-template` directory.

## Step 2: Meet the example project

The template is an ordinary cabal project. Its smart-contract sources live in
`src/`:

- **`AuctionValidator.hs`** &mdash; a *spending validator* for a simple
  auction. This is the on-chain script that decides whether a transaction is
  allowed to spend the auction's funds.
- **`AuctionMintingPolicy.hs`** &mdash; a *minting policy* paired with the
  auction, controlling when the associated tokens may be minted.

Together these make up the `plinth-validators` library. Under `app/` are two
small programs that turn the compiled validators into CIP-57 blueprints:

- **`GenAuctionValidatorBlueprint.hs`** (the `gen-auction-validator-blueprint`
  executable)
- **`GenMintingPolicyBlueprint.hs`** (the `gen-minting-policy-blueprint`
  executable)

These are ordinary Haskell modules: what makes them Plinth is that
`uplc-ghc` compiles their Plinth definitions all the way down to Plutus Core.

## Step 3: Compile the contracts

Tell cabal to use `uplc-ghc` by adding a `with-compiler` line to the project's
`cabal.project`:

```
with-compiler: /path/to/uplc-ghc
```

Now every cabal command in this project uses `uplc-ghc`. Refresh the package
index and build:

```console
$ cabal update
$ cabal build
```

The first run downloads and builds dependencies, so expect it to take a while.

Because the Plinth plugin is built into `uplc-ghc`, no extra plugin
configuration is required: compiling the validator modules yields Plutus Core in
addition to the usual GHC outputs.

## Step 4: Look at the Plutus Core

To see the compiled output as a concrete artefact, run one of the blueprint
generators and have it write its blueprint to a file:

```console
$ cabal run gen-auction-validator-blueprint -- auction-validator.json
$ cat auction-validator.json
```

The resulting `auction-validator.json` is a CIP-57 blueprint. It embeds the
compiled Plutus Core &mdash; the on-chain code that the Cardano ledger would
actually execute &mdash; produced from Haskell by `uplc-ghc`, alongside the
metadata that off-chain tooling uses to interact with the validator.

## Step 5 (optional): Generate the minting-policy blueprint

The companion generator works the same way:

```console
$ cabal run gen-minting-policy-blueprint -- minting-policy.json
```

Comparing the two blueprints is a good thread to pull on once you are
comfortable.

## Where to go next

- [Use uplc-ghc in a project]({% link how-to/use.md %}) &mdash; point your own
  project at the compiler instead of the template.
- [The Plinth standalone compiler]({% link explanation/standalone-compiler.md %})
  &mdash; understand what `uplc-ghc` is doing under the hood.
- [Plinth user guide][plinth] &mdash; learn to write Plinth code of your own.

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
[plinth-template]: https://github.com/IntersectMBO/plinth-template
