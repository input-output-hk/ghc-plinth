---
title: "The Plinth contract language"
permalink: /explanation/plinth-language/
---
[The structure of a Plinth smart contract]({% link explanation/structure.md %})
showed the shape of a project and the `PlutusTx.compile` splice that freezes
on-chain logic into a value. This page is about the code that goes *inside* that
splice: what writing Plinth actually looks like, and how it differs from ordinary
Haskell. It is an overview, not a reference &mdash; the [Plinth user
guide][plinth] is the complete guide to the language.

## A subset of Haskell

Plinth is not a separate language with its own syntax. It *is* Haskell, written
in ordinary modules and type-checked by GHC, restricted to the part the
[compiler]({% link explanation/standalone-compiler.md %}) can translate to
[UPLC]({% link explanation/uplc.md %}). You keep the things that have a
Plutus Core counterpart &mdash; algebraic data types, pattern matching,
higher-order functions, recursion, parametric polymorphism, and type classes
&mdash; and give up the things that do not, such as `IO`, and arbitrary library
code that was never written to be compiled on-chain. As a small but telling
example, on-chain integers are arbitrary-precision `Integer` (which maps to the
UPLC `integer` builtin), never the machine-word `Int`.

## The Plinth prelude

The standard Haskell `Prelude` is full of functions that cannot go on-chain, so
Plinth modules use **`PlutusTx.Prelude`** instead &mdash; either by enabling
`NoImplicitPrelude` and importing it unqualified, or (as the project template
does) importing it qualified:

```haskell
import PlutusTx.Prelude qualified as PlutusTx
```

`PlutusTx.Prelude` mirrors the familiar names &mdash; `Eq`, `Ord`, `&&`, the
arithmetic operators, list functions &mdash; but every one is built from Plinth
primitives that compile down to [UPLC builtins]({% link explanation/uplc.md %}).
So you still write `==`, `&&`, `+`, and `map`; they just resolve to the on-chain
versions rather than the standard library's.

## Crossing the boundary: `Data`, `makeIsDataIndexed`, `makeLift`

A datum, redeemer, or script parameter crosses between Haskell and the ledger as
[`Data`]({% link explanation/uplc.md %}), so your Haskell types need encodings.
Two Template Haskell helpers derive them:

- **`makeIsDataIndexed`** derives the `ToData` / `FromData` instances that convert
  a type to and from `Data`, with explicit constructor indices so the on-chain
  encoding is stable across changes to the source:

  ```haskell
  data AuctionRedeemer = NewBid Bid | Payout
  PlutusTx.makeIsDataIndexed ''AuctionRedeemer [('NewBid, 0), ('Payout, 1)]
  ```

- **`makeLift`** derives a `Lift` instance, letting an ordinary Haskell value be
  *lifted* into a script as a constant. This is what makes parameterised scripts
  work: the off-chain code applies a parameter with `liftCode` (see
  [the structure page]({% link explanation/structure.md %})).

A schema-aware variant, `makeIsDataSchemaIndexed`, additionally derives the
[CIP-57 blueprint schema]({% link explanation/blueprints.md %}) for the type; the
template uses it so its blueprint generators have schemas to emit.

## What a validator looks like

The entry point the ledger actually calls is **untyped**: it takes
`BuiltinData` and returns `BuiltinUnit`, signalling success by returning and
failure by [erroring]({% link explanation/plutus-core.md %}). You rarely write at
that level. Instead you write a *typed* function over real Haskell types and wrap
it. From the template (PlutusV3, where the single argument is the script context
that now carries the redeemer):

```haskell
auctionTypedValidator :: AuctionParams -> ScriptContext -> Bool
auctionTypedValidator params ctx = ...

auctionUntypedValidator :: AuctionParams -> BuiltinData -> BuiltinUnit
auctionUntypedValidator params ctx =
  PlutusTx.check (auctionTypedValidator params (PlutusTx.unsafeFromBuiltinData ctx))

{-# INLINEABLE auctionTypedValidator #-}
{-# INLINEABLE auctionUntypedValidator #-}
```

Reading the wrapper: `unsafeFromBuiltinData` decodes the `Data` into your typed
`ScriptContext`; the typed validator returns a `Bool`; and `check :: Bool ->
BuiltinUnit` turns `False` into an error (so the script fails) and `True` into
unit (so it passes). It is `auctionUntypedValidator` &mdash; the untyped entry
point &mdash; that gets quoted into the `compile` splice. A minting policy is
written the same way: a typed function returning `Bool`, wrapped with `check`; it
simply receives no datum.

(Earlier ledger languages differ only in the wrapper's shape: PlutusV1 and V2
pass the datum, redeemer, and context as *separate* `BuiltinData` arguments,
whereas PlutusV3 passes a single context argument.)

## `INLINEABLE` and the plugin

The plugin compiles the one function named in the `compile` quote, following
every definition it references. For a referenced definition in another module to
be available, GHC must have kept its **unfolding** in the interface file &mdash;
which is why on-chain functions are marked `{-# INLINEABLE #-}`. Omitting it on a
function used on-chain is a common cause of compile-time errors complaining that
the plugin cannot find a definition's unfolding.

## Sharing with off-chain code

Because all of this is Haskell, the datatypes and their derived `ToData` /
`FromData` instances are shared directly with the
[off-chain code]({% link explanation/structure.md %}) in the same project: the
off-chain side builds datums and redeemers from the very same types the validator
decodes, so the two halves cannot drift out of agreement.

## Further reading

- [The structure of a Plinth smart contract]({% link explanation/structure.md %})
  &mdash; where this code sits in a project, and the `compile` splice.
- [From Plinth to the chain]({% link explanation/from-plinth-to-the-chain.md %})
  &mdash; what the compiled validator becomes.
- [The UPLC language]({% link explanation/uplc.md %}) &mdash; the builtins and
  `Data` type the prelude and encodings map onto.
- [Contract blueprints (CIP-57)]({% link explanation/blueprints.md %}) &mdash;
  the schemas `makeIsDataSchemaIndexed` produces.
- [Plinth user guide][plinth] &mdash; the complete language reference.

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
