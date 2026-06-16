---
title: "Contract blueprints (CIP-57)"
permalink: /explanation/blueprints/
---
A **blueprint** is the artefact that
[From Plinth to the chain]({% link explanation/from-plinth-to-the-chain.md %})
introduced as the bridge to off-chain tooling. This page looks at it closely:
what a blueprint contains, how it is produced and used, and where its limits
are. Blueprints are standardised as [CIP-57][cip57], and the standard is
**language-agnostic** &mdash; a blueprint produced by Plinth and one produced by
Aiken are the same kind of document.

## Why a blueprint exists

The compiled output of a contract is just a [serialised UPLC
script]({% link explanation/from-plinth-to-the-chain.md %}): a blob of bytes the
ledger runs. That blob is opaque. To *use* a contract, off-chain code &mdash; a
wallet, a dApp backend, `cardano-cli` &mdash; needs two things the bytes alone
do not give it:

- the script itself (to attach it to a transaction, and to hash it into an
  address), and
- a precise description of the data the script expects, so it can build a
  **datum** and **redeemer** in exactly the encoding the validator will decode.

A blueprint packages both into one machine-readable document. It is the
contract's *interface*, in the same sense as a header file or an API schema.

## What a blueprint contains

A blueprint is a single JSON document with three parts: a **preamble** of
metadata, an array of **validators**, and a registry of reusable schema
**definitions**. A trimmed example:

```json
{
  "preamble": {
    "title": "auction/validator",
    "description": "Spending validator for a simple auction",
    "version": "1.0.0",
    "plutusVersion": "v3",
    "compiler": { "name": "uplc-ghc", "version": "9.6.7" }
  },
  "validators": [
    {
      "title": "AuctionValidator",
      "redeemer": { "title": "redeemer", "schema": { "$ref": "#/definitions/AuctionRedeemer" } },
      "datum":    { "title": "datum",    "schema": { "$ref": "#/definitions/AuctionDatum" } },
      "compiledCode": "5907c4010000...e1",
      "hash": "a3f1c0...d28b"
    }
  ],
  "definitions": {
    "Integer": { "dataType": "integer" },
    "AuctionRedeemer": {
      "anyOf": [
        { "title": "Bid",   "dataType": "constructor", "index": 0,
          "fields": [ { "$ref": "#/definitions/Integer" } ] },
        { "title": "Close", "dataType": "constructor", "index": 1, "fields": [] }
      ]
    }
  }
}
```

**The preamble** is informational: a `title`, optional `description` and
`version`, the `plutusVersion` the script targets (`v1`, `v2`, or `v3`), an
optional `license`, and a `compiler` record naming the tool that produced it.

**Each validator** carries the parts that matter most:

- `compiledCode` &mdash; the serialised script as CBOR hex. This is the
  on-chain code itself.
- `hash` &mdash; the blake2b-224 [script hash]({% link explanation/from-plinth-to-the-chain.md %})
  (mandatory whenever `compiledCode` is present).
- `redeemer` (required) and `datum` (optional) &mdash; each an *argument*: a
  `title`/`description`, an optional `purpose` (`spend`, `mint`, `withdraw`,
  `publish`), and a `schema` pointing at a definition.
- `parameters` (optional) &mdash; compile-time parameters, described the same
  way as datum and redeemer.

**The definitions** are a registry of named **Plutus Data schemas**, referenced
by `$ref`. They are where the interface really lives.

## The data schema: the encoding contract

On the wire a datum or redeemer is a [`Data`
value]({% link explanation/from-plinth-to-the-chain.md %}) &mdash; a tree of
integers, byte strings, lists, maps, and tagged constructors. The data schema
describes exactly which shape a given argument takes, using a small vocabulary:

- a `dataType` of `integer`, `bytes`, `list`, `map`, or `constructor`;
- a `constructor` carries an `index` (which variant) and `fields` (the
  positional contents);
- sum types are written as an `anyOf` of constructor alternatives &mdash; as in
  `AuctionRedeemer` above, where `Bid` is constructor 0 and `Close` is
  constructor 1;
- `list`/`map` schemas use `items`, or `keys` and `values`.

This is the crux of why the blueprint is the cross-toolchain contract: the
*constructor indices and field order* it records are precisely what the
on-chain script decodes. Any off-chain code that builds a redeemer must match
them. Get the index wrong and the transaction fails when the validator runs.
On the Haskell side those indices come from `makeIsDataIndexed`; see [Data
representation]({% link explanation/data-representation.md %}).

## Producing a blueprint

The blueprint format is part of Cardano, not part of Plinth; what is
Plinth-specific is only the library that emits one. Plinth provides
`PlutusTx.Blueprint`, which derives the schema for a Haskell datum/redeemer type
and writes the document out. The [Plinth project
template]({% link tutorials/first-smart-contract.md %}) ships small generator
executables (`gen-auction-validator-blueprint` and friends) that do exactly
this.

Other toolchains emit the same kind of document: an [Aiken][aiken] build, for
instance, produces a `plutus.json` that is a CIP-57 blueprint. This is what lets
[different languages]({% link explanation/languages.md %}) interoperate with the
same off-chain tools.

## Using a blueprint

Off-chain, a blueprint feeds three independent jobs:

- **Deploy the script.** Take `compiledCode` and attach it to a transaction
  &mdash; inline in the witness set, or once as a [reference
  script]({% link explanation/from-plinth-to-the-chain.md %}).
- **Address the script.** Use `hash` to form the script address that funds are
  locked at, or the policy id for a minting policy.
- **Build the arguments.** Use the schemas to construct datum, redeemer, and
  parameters in the right `Data` encoding.

Tooling differs in how much of the third job it automates. TypeScript
off-chain libraries such as Lucid and Mesh read a blueprint and *generate*
typed bindings for its datum/redeemer, so the encoding is never written by
hand. `cardano-cli` consumes the compiled code directly. On the Haskell side the
*emit* direction is well supported (`PlutusTx.Blueprint`); generating types
*from* a foreign blueprint is not yet a mature facility, so using a non-Plinth
script from Haskell still tends to mean mirroring its types by hand.

## Limitations

A blueprint is useful precisely because of what it is &mdash; and it is easy to
expect more of it than it provides:

- **It is off-chain only and unauthenticated.** The ledger never sees a
  blueprint; nothing on-chain enforces that it matches the script it claims to
  describe. It is documentation you choose to trust, not a security boundary. (A
  wrong blueprint does not let anyone steal funds &mdash; a mismatched datum just
  makes a transaction fail or strands an output &mdash; but you cannot rely on it
  to be correct by construction.)
- **It describes the interface, not the behaviour.** A blueprint tells you the
  *shape* of the data and the script's bytes. It says nothing about what the
  validator actually accepts or computes; there is no machine-checkable spec of
  its logic.
- **Its precision is bounded.** The schema can record structure and some
  refinements (byte lengths, integer ranges), but not *meaning*: a 28-byte field
  is just `bytes`, not "a script hash". Semantic distinctions that a hand-written
  type would capture collapse, so types derived from a blueprint are coarser than
  ones written by a person.
- **Its faithfulness depends on the producer.** The schema is only as correct as
  the tool that emitted it. When the same compiler produces both the script and
  the blueprint (Plinth, Aiken), they cannot drift; a hand-edited or buggy
  blueprint can simply be wrong.

## Further reading

- [From Plinth to the chain]({% link explanation/from-plinth-to-the-chain.md %})
  &mdash; where the compiled code and script hash inside a blueprint come from.
- [How smart contracts run]({% link explanation/plutus-core.md %}) &mdash; the
  UPLC that `compiledCode` contains.
- [Your first smart contract with Plinth]({% link tutorials/first-smart-contract.md %})
  &mdash; generate a real blueprint from the template, hands-on.
- [CIP-57: Plutus contract blueprints][cip57] &mdash; the full standard.

[cip57]: https://cips.cardano.org/cip/CIP-0057
[aiken]: https://aiken-lang.org/
