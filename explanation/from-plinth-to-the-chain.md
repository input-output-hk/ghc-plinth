---
title: "From Plinth to the chain: compilation, blueprints, and transactions"
permalink: /explanation/from-plinth-to-the-chain/
---
[How smart contracts run]({% link explanation/plutus-core.md %}) explained that
the ledger executes Untyped Plutus Core (UPLC), and
[The Cardano blockchain]({% link explanation/cardano-blockchain.md %}) explained
that a smart contract is a validator script guarding an output. This page
connects the two: how Plinth source becomes UPLC, how that UPLC is packaged, and
how it finally reaches a transaction.

The single most useful thing to understand is where the **UPLC boundary** lies.
Turning Haskell into UPLC is Plinth's job and Plinth's alone. Everything *after*
UPLC &mdash; serialising it, describing it with a blueprint, hashing it into an
address, and attaching it to a transaction &mdash; is shared Cardano
infrastructure that works identically for *any* UPLC, no matter which language
produced it. The ledger only ever sees opaque UPLC; it neither knows nor cares
that it came from Plinth.

## The big picture

![Plinth compiles Haskell source down to UPLC; everything after the UPLC boundary is shared by any UPLC script.](/assets/images/uplc-boundary.svg)

Above the boundary is language-specific. Below the boundary is where
[other languages]({% link explanation/languages.md %}) &mdash; Plutarch, Aiken,
OpShin, and the rest &mdash; converge: they reach UPLC by different routes, but
from there they all use exactly the same machinery shown below.

## Compiling to UPLC (Plinth-specific)

Plinth is a subset of Haskell, so it is compiled by GHC. A
[GHC plugin]({% link explanation/standalone-compiler.md %}) intercepts the
definitions marked for on-chain use and takes them down a pipeline of progressively
lower-level representations:

- **GHC Core** &mdash; the ordinary intermediate language GHC already uses. The
  plugin reads the Core that GHC produced for the marked definitions.
- **PIR (Plutus IR)** &mdash; a Plutus-level intermediate representation that
  still has high-level conveniences such as datatypes and `let` bindings.
- **Typed Plutus Core** &mdash; PIR compiled down to the typed core language.
- **UPLC** &mdash; the types are then *erased*, leaving the untyped program the
  ledger actually runs.

The result is wrapped in a `CompiledCode` value (the program, plus the PIR kept
around for debugging). This whole pipeline is the *only* Plinth-specific part of
the story. Because the plugin is built into `uplc-ghc`, compiling a module that
defines Plinth code yields this UPLC alongside the usual GHC outputs &mdash; see
[The Plinth standalone compiler]({% link explanation/standalone-compiler.md %}).

## Serialising the script (generic)

A UPLC program is an in-memory term; to store, hash, or transmit it, it has to
become bytes. Two steps turn it into the **serialised script**:

- **flat** &mdash; a compact, bit-level binary encoding of the UPLC term.
- **CBOR** &mdash; the flat bytes are then wrapped in CBOR.

Those CBOR bytes *are* "the script" as far as the ledger is concerned: it is what
gets hashed and what a node ultimately deserialises and runs. None of this
depends on the source language.

You will also see scripts on disk as a **`.plutus` file**. That is just a small
JSON *text envelope* &mdash; `{ "type": ..., "description": ..., "cborHex": ... }`
&mdash; used by `cardano-cli` and `cardano-api` to carry the CBOR bytes around.
It is a transport wrapper, nothing more.

## What a blueprint is (CIP-57)

A **blueprint** is *not* something the ledger consumes. It is an off-chain,
machine-readable description of a contract, standardised as
[CIP-57][cip57]. A blueprint is a JSON document that bundles:

- the serialised UPLC (as CBOR hex) &mdash; the same bytes from the previous
  section, and
- **metadata**: each validator's purpose and the **schemas** of the data it
  expects &mdash; its datum, redeemer, and any compile-time parameters.

It exists because off-chain code &mdash; wallets, dApp backends, `cardano-cli`
&mdash; needs two things to use a script: the script's bytes, *and* a precise
description of how to build the data the script expects. The blueprint is that
machine-readable interface.

Crucially, CIP-57 is **language-agnostic**: it is a Cardano-wide standard, and
tools for other languages (Aiken, for instance) emit blueprints too. What is
Plinth-specific is only the *library and generator programs* that produce one.

For a closer look at what a blueprint contains, how it is produced and used, and
where its limits lie, see [Contract blueprints]({% link explanation/blueprints.md %}).

## Script hash and script address (generic)

A script is identified by its **script hash**: a blake2b-224 hash of the
serialised script, prefixed by a tag for its Plutus language version (below). The
hash is purely a function of the bytes.

Placing that hash in the payment credential of a Cardano address yields a
**script address**. Funds sent to a script address are guarded by the
corresponding script: any transaction trying to spend them must satisfy the
validator. For a [minting policy]({% link explanation/cardano-blockchain.md %}),
the same hash serves as the **policy id** that namespaces the tokens it governs.

## Plutus ledger languages (generic)

The ledger distinguishes Plutus script versions &mdash; **V1, V2, V3**. The
version is tagged at the bytes level and determines which built-in functions are
available and the exact shape of the
[script context]({% link explanation/cardano-blockchain.md %}) a validator
receives. It is part of the shared infrastructure, independent of the source
language; Plinth simply targets one of these versions.

## Attaching a script to a transaction (generic)

To validate a transaction, a node needs the actual script bytes. There are two
ways to supply them:

- **Inline in the witness set** &mdash; the serialised script travels inside the
  transaction that uses it.
- **Reference script** &mdash; the script is stored once in an output and later
  transactions point at that output to reuse it, without re-transmitting the
  bytes. This keeps transactions small when a script is used repeatedly.

When the script then runs, it receives the runtime inputs described in
[The Cardano blockchain]({% link explanation/cardano-blockchain.md %}): the
**datum** attached to the output being spent, the **redeemer** supplied by the
transaction, and the **script context** &mdash; the ledger's view of the
transaction. (A minting policy is invoked with a redeemer and context but no
datum.)

All of this is generic. The ledger handles the script as opaque UPLC; the
mechanics of inline versus reference scripts, of datum and redeemer and context,
are the same whether the bytes came from Plinth or any other compiler.

## The dividing line

So the pipeline has a clean seam. Above the UPLC boundary is Plinth: Haskell
source compiled, via PIR and typed Plutus Core, down to UPLC. Below it is the
rest of Cardano: serialisation, blueprints, hashing, addresses, and transactions
&mdash; a shared substrate that every UPLC-producing language plugs into the same
way. Plinth's responsibility ends precisely where the UPLC begins.

## Further reading

- [How smart contracts run: Plutus Core and the CEK machine]({% link explanation/plutus-core.md %})
  &mdash; what UPLC is and how the ledger executes it.
- [The Cardano blockchain]({% link explanation/cardano-blockchain.md %}) &mdash;
  the eUTXO model, validators, datum, redeemer, and script context.
- [Languages for smart contracts]({% link explanation/languages.md %}) &mdash;
  the other languages that converge on UPLC.
- [Your first smart contract with Plinth]({% link tutorials/first-smart-contract.md %})
  &mdash; compile a validator and generate its blueprint, hands-on.
- [CIP-57: Plutus contract blueprints][cip57] &mdash; the blueprint standard.

[cip57]: https://cips.cardano.org/cip/CIP-0057
