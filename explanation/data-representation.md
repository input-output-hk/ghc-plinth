---
title: "Data representation: from Haskell types to Plutus Core"
permalink: /explanation/data-representation/
---
A Plinth project holds [on-chain and off-chain code in one
package]({% link explanation/structure.md %}), and both halves work with the
*same* Haskell datatypes. For that to work, a Haskell value must have a
representation at the Plutus Core level &mdash; and for datums, redeemers, and
script parameters, a representation both sides agree on exactly. This page
explains how Haskell types map onto Plutus Core, the two representations your own
datatypes can take, and the classes and helpers that move values across the
boundary.

## How Haskell types map to Plutus Core

A handful of Haskell types *are* the [UPLC builtin
types]({% link explanation/uplc.md %}), and map straight onto them:

| Haskell                      | Plutus Core builtin |
| ---------------------------- | ------------------- |
| `Integer`                    | `integer`           |
| `BuiltinByteString`          | `bytestring`        |
| `BuiltinString`              | `string`            |
| `BuiltinList`, `BuiltinPair` | `list`, `pair`      |
| `BuiltinBool`, `BuiltinUnit` | `bool`, `unit`      |
| `BuiltinData`                | `data`              |

Note what is *not* in that table. The everyday prelude types &mdash; `Bool`,
`Maybe`, lists, tuples &mdash; are ordinary Haskell datatypes, not builtins; they
compile with the sum-of-products representation described next. (`Bool` is
literally the standard `Bool`; the builtin is the separate `BuiltinBool`.)

Your **own datatypes** &mdash; records and sum types &mdash; likewise do not have
a single fixed mapping. They have a *choice* of representation, which is the
subject of the rest of this page. One builtin above is special:
[`Data`]({% link explanation/uplc.md %}), because it is the only thing the ledger
accepts at the boundary. Every datum, redeemer, and parameter crosses as `Data`.

## Two representations for your datatypes

An algebraic datatype can be represented in Plutus Core in two ways.

**Sum-of-products (the default).** An ordinary `data` declaration compiles to
UPLC [sum-of-products terms]({% link explanation/uplc.md %}) &mdash; `constr` to
build a variant and `case` to match one (before UPLC 1.1.0 this was a Scott
encoding of lambdas). Construction and pattern matching are direct and cheap.
This is the representation for datatypes used *inside* the contract: intermediate
values, helper types, anything you compute over.

**Builtin `Data`.** The universal tree of tagged constructors, maps, lists,
integers (`I`), and byte strings (`B`). This is the only representation the ledger
accepts for datums, redeemers, and parameters, and it is what the [blueprint
schema]({% link explanation/blueprints.md %}) describes.

The two are different, so crossing the boundary means converting: a sum-of-products
value must become `Data` to leave the script, and incoming `Data` must become a
sum-of-products value before typed code can use it. Those conversions are the job
of the `ToData` / `FromData` classes.

## `ToData`, `FromData`, and `UnsafeFromData`

`BuiltinData` is the on-chain handle to a `Data` value. Three classes convert
between it and your types:

```haskell
class ToData a where
  toBuiltinData :: a -> BuiltinData

class FromData a where
  fromBuiltinData :: BuiltinData -> Maybe a

class UnsafeFromData a where
  unsafeFromBuiltinData :: BuiltinData -> a
```

`toBuiltinData` always succeeds. Decoding can fail (the bytes may not match the
type), so there are two ways to do it: `fromBuiltinData` returns `Maybe`, while
`unsafeFromBuiltinData` calls [`error`]({% link explanation/plutus-core.md %}) on a
mismatch and is typically much faster. On-chain code usually takes the unsafe
route &mdash; the [validator wrapper]({% link explanation/plinth-language.md %})
decodes its argument with `unsafeFromBuiltinData`, since a malformed argument
should just fail the script. (When you write an instance by hand, decode
substructures with `unsafeFromBuiltinData` too, or you lose the speed.)

You rarely write these instances yourself.

## Deriving the instances

Template Haskell helpers derive the conversions:

```haskell
data AuctionRedeemer = NewBid Bid | Payout
PlutusTx.makeIsDataIndexed ''AuctionRedeemer [('NewBid, 0), ('Payout, 1)]
```

- **`makeIsDataIndexed ''T [(...)]`** derives `ToData`, `FromData`, and
  `UnsafeFromData` using an **explicit** mapping of constructors to integer
  indices. Those indices *are* the on-chain encoding: they end up in the `Data`
  tree and in the [blueprint schema]({% link explanation/blueprints.md %}).
  Pinning them by hand keeps the encoding stable when you add, remove, or reorder
  constructors &mdash; which is why anything persisted on-chain or shared with
  off-chain tooling should use this.
- **`unstableMakeIsData ''T`** derives `ToData` and `FromData` with indices
  assigned automatically from constructor order. Convenient, but the encoding
  shifts if the constructors change &mdash; only safe for throwaway types you
  control end to end.
- **`makeIsDataSchemaIndexed`** (from `PlutusTx.Blueprint`) is like
  `makeIsDataIndexed` and *also* derives the [CIP-57
  schema]({% link explanation/blueprints.md %}); see [Generate a
  blueprint]({% link how-to/generate-blueprint.md %}).
- **`makeLift`** is related but separate: it derives a `Lift` instance, which
  splices a Haskell value into a script as a *constant*. This is how
  [parameters]({% link explanation/structure.md %}) are applied (`liftCode`), and
  it does not go through `Data`.

## Choosing a representation: ordinary data vs `asData`

By default a datatype is sum-of-products, and you add `makeIsDataIndexed` so it
can cross the boundary. Each crossing then **fully** encodes or decodes the whole
value at once.

The alternative is to back the datatype with `Data` directly, using `asData`:

```haskell
import PlutusTx.AsData qualified as AsData

$(AsData.asData
    [d|
      data Vote = Yes | No | Abstain Integer
        deriving newtype (Eq)
    |])
```

This replaces the datatype with a newtype around `BuiltinData` and generates
pattern synonyms (`Yes`, `No`, `Abstain`) that behave like the original
constructors. Because the value *is* already `Data`, crossing the boundary is
free &mdash; no conversion happens. The cost moves elsewhere: the pattern synonyms
call `toBuiltinData` / `unsafeFromBuiltinData` on the fields on **every**
construction and every pattern match.

That trade-off decides which to use:

- `asData` pays off for values you mostly **pass around and rarely inspect**, and
  it compounds well when the field types are *also* defined with `asData` (no
  repeated re-encoding of nested structure).
- It is expensive for types you **pattern-match on heavily**, or whose fields are
  ordinary sum-of-products values &mdash; each access re-encodes them. For those,
  the plain representation plus `makeIsDataIndexed` is cheaper.

> A future Plinth release will let you select the `Data`-backed representation by
> *deriving* it on an ordinary datatype, removing the `$(asData [d| ... |])`
> Template Haskell boilerplate shown above.
{:.info}

## Sharing across the boundary

This is what lets the two halves of a project share data safely. The off-chain
code builds a datum, redeemer, or parameter from a Haskell value with
`toBuiltinData`; the validator decodes the very same `Data` back with
`unsafeFromBuiltinData`. Both use the *same* datatype and the *same* derived
instances, so the encoding each side assumes is identical by construction &mdash;
they cannot drift out of agreement. The [test
guide]({% link how-to/test.md %}) uses exactly this to feed a redeemer to a
compiled script, and [blueprint generation]({% link how-to/generate-blueprint.md %})
publishes the encoding so non-Haskell tooling can match it too.

## Further reading

- [The UPLC language]({% link explanation/uplc.md %}) &mdash; the builtin types,
  the `Data` tree, and the `constr`/`case` sum-of-products forms.
- [The Plinth contract language]({% link explanation/plinth-language.md %}) &mdash;
  the validator wrapper that decodes `BuiltinData`, and the prelude.
- [Contract blueprints (CIP-57)]({% link explanation/blueprints.md %}) &mdash; the
  schema is the published form of the `Data` encoding described here.
- [The structure of a Plinth smart contract]({% link explanation/structure.md %})
  &mdash; where the shared types and off-chain code sit, and `liftCode` parameters.
- [Generate a blueprint]({% link how-to/generate-blueprint.md %}) &mdash; deriving
  schemas with `makeIsDataSchemaIndexed`.
- [Plinth user guide][plinth] &mdash; the complete reference.

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
