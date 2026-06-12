---
title: "The structure of a Plinth smart contract"
permalink: /explanation/structure/
---
This page describes what a Plinth contract project *looks like* &mdash; its
shape, not the steps to build it. For a hands-on walk-through, follow
[Your first smart contract with Plinth]({% link tutorials/first-smart-contract.md %})
instead.

The short version: a Plinth contract is an ordinary Haskell project whose one
special move is a Template Haskell splice that turns the on-chain logic into a
plain Haskell value. That single idea is what lets a project hold both the
on-chain code and the off-chain code that deploys and interacts with it.

## An ordinary Haskell project

Because [Plinth is a subset of Haskell]({% link explanation/about.md %}), a
Plinth project is just a cabal package. The entire `cabal-install` workflow
applies unchanged: dependencies are resolved from Hackage and the Cardano
package repository (CHaP), code is organised into modules, a library, and
executables or test suites, and `cabal build` builds it.

The single tweak is the compiler. Instead of stock GHC you build with
`uplc-ghc`, most conveniently by setting it once in `cabal.project`:

```
with-compiler: /path/to/uplc-ghc
packages: .
```

This is the persistent equivalent of passing `cabal -w /path/to/uplc-ghc` on the
command line. Nothing else changes: because the
Plinth pass is a [built-in static plugin]({% link explanation/static-plugin.md %}),
compiling a module that defines Plinth code simply yields Plutus Core in addition
to the usual GHC outputs &mdash; no plugin flags, no extra dependencies.

## On-chain and off-chain in one project

The defining structural feature of a Plinth project is that the same package,
built by the same compiler, holds two kinds of code bound for two different
places:

- **On-chain code** &mdash; the validator and minting-policy logic, written in
  the Plinth subset, that ends up as [UPLC]({% link explanation/uplc.md %}) on the
  ledger.
- **Off-chain code** &mdash; ordinary Haskell that prepares, inspects,
  serialises, and deploys that on-chain code: blueprint generators, tests, and
  transaction-building.

These are not separate projects that share a data format by convention; they are
the same Haskell program. What joins them is a Template Haskell splice.

## The bridge: `PlutusTx.compile`

The on-chain logic starts life as an ordinary Haskell function. You turn it into
on-chain code by quoting it and compiling it *at compile time*:

```haskell
validatorCode :: CompiledCode (BuiltinData -> BuiltinUnit)
validatorCode = $$(PlutusTx.compile [|| validator ||])
```

Reading this:

- `[|| validator ||]` is a **typed Template Haskell quote** of the function.
- `$$(PlutusTx.compile ...)` runs during compilation. This splice is exactly
  where the GHC plugin intercepts the quoted code and runs the
  [Plinth-to-UPLC pipeline]({% link explanation/from-plinth-to-the-chain.md %}).
- the result is a **`CompiledCode a`**: an ordinary Haskell value holding the
  compiled UPLC program. The phantom type `a` (here `BuiltinData ->
  BuiltinUnit`) records the Haskell type the program was compiled from.

The key idea is that the splice **freezes the on-chain program into the host
program as a value**. Once `validatorCode` is just a value, the rest of the
project &mdash; the off-chain half &mdash; can pick it up and work with it like
any other data. That is what lets one project hold both worlds.

(A handful of other Template Haskell helpers &mdash; `makeLift`,
`makeIsDataIndexed` &mdash; derive the glue that moves Haskell datatypes across
the boundary as on-chain `Data`. Writing the Plinth code itself, and these
helpers, are the subject of a separate page; here we only need the splice.)

## Working with `CompiledCode` off-chain

Everything past the splice is plain Haskell operating on a value &mdash; no
plugin involved. The plugin was needed only to *produce* the `CompiledCode`; what
the off-chain code *does* with it is where most of a project's non-validator code
lives. Typically it:

- **Applies parameters.** A parameterised script is a `CompiledCode (P -> V)`;
  before deployment you bake in its compile-time parameter with `unsafeApplyCode`
  (or the checked `applyCode`) together with `liftCode`, producing a
  `CompiledCode V`. This happens off-chain and changes the resulting script
  &mdash; and therefore its hash. The template does it right at the splice site:

  ```haskell
  auctionValidatorScript params =
    $$(PlutusTx.compile [|| auctionUntypedValidator ||])
      `PlutusTx.unsafeApplyCode` PlutusTx.liftCode plcVersion110 params
  ```

- **Serialises it.** `serialiseCompiledCode :: CompiledCode a -> SerialisedScript`
  produces the flat-in-CBOR
  [bytes]({% link explanation/from-plinth-to-the-chain.md %}) the ledger actually
  runs (`SerialisedScript` is a `ShortByteString`). From those bytes come the
  script hash and the script address.

  ```haskell
  import PlutusLedgerApi.Common (serialiseCompiledCode)

  script = serialiseCompiledCode validatorCode
  ```

- **Describes it as a blueprint.** Wrapping the serialised code together with the
  datum, redeemer, and parameter schemas into a `ContractBlueprint` and calling
  `writeBlueprint` emits a [CIP-57 blueprint]({% link explanation/blueprints.md %}).
  This is precisely what the template's `gen-*-blueprint` executables do.

- **Builds transactions and tests.** The serialised script can be handed to
  `cardano-api` (or a test harness) to
  [attach it to a transaction]({% link explanation/from-plinth-to-the-chain.md %})
  as an inline or reference script, and to exercise the validator off-chain.

## A typical layout

Put together, a Plinth project is usually a **library** of on-chain validators
&mdash; each exposed as a `CompiledCode`, often as a function of its parameters
&mdash; plus **executables or test suites** for the off-chain side. The
[project template]({% link tutorials/first-smart-contract.md %}) is laid out
exactly this way: the `plinth-validators` library under `src/`, and the
`gen-auction-validator-blueprint` and `gen-minting-policy-blueprint` executables
under `app/`. The library is the on-chain half frozen into values; the
executables are the off-chain half consuming them.

## Further reading

- [From Plinth to the chain]({% link explanation/from-plinth-to-the-chain.md %})
  &mdash; the pipeline the `compile` splice triggers, and how the serialised
  script reaches a transaction.
- [Contract blueprints (CIP-57)]({% link explanation/blueprints.md %}) &mdash;
  what the off-chain blueprint generators emit.
- [The built-in static plugin]({% link explanation/static-plugin.md %}) &mdash;
  why building with `uplc-ghc` needs no plugin configuration.
- [Your first smart contract with Plinth]({% link tutorials/first-smart-contract.md %})
  &mdash; the same template, built step by step.
- [Plinth user guide][plinth] &mdash; for writing Plinth code itself, which will
  also get its own explanation page here.

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
