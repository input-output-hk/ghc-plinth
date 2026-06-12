---
title: The Cardano blockchain
permalink: /explanation/cardano-blockchain/
---
This page gives the background needed to understand *why* Plinth exists. It
explains what a distributed ledger is, what makes [Cardano][cardano]'s ledger
distinctive (the extended UTXO model), and where smart contracts fit in. No
prior blockchain knowledge is assumed.

## A distributed ledger

At its core, a blockchain is a **ledger**: a record of who owns what. What makes
it a *distributed* ledger is that no single party holds the authoritative copy.
Instead, the ledger is replicated across many independent computers (*nodes*),
and the network agrees on its contents through a **consensus** protocol &mdash;
Cardano uses a proof-of-stake protocol called Ouroboros.

The ledger is built from **transactions**, which are grouped into **blocks** and
chained together in order. A few properties follow from this design:

- **Append-only.** New transactions are added; past ones are never edited.
- **Replicated.** Every node can independently check and store the full history.
- **No central authority.** Agreement comes from the consensus protocol rather
  than from a trusted operator.

Because every node must agree on the outcome, the rules for deciding whether a
transaction is valid have to be **deterministic**: the same transaction, checked
against the same ledger state, must always give the same answer on every node.

## What is special about Cardano: the extended UTXO model

How a blockchain represents "who owns what" is a central design choice. Two
broad families exist:

- **Account-based** (used by Ethereum, for example). The ledger is a set of
  accounts with balances, much like bank accounts. A transaction mutates those
  balances.
- **UTXO-based** (used by Bitcoin). The ledger is instead a set of *unspent
  transaction outputs* (UTXOs). Each output carries a **value** (an amount of
  ada, and possibly other tokens) and an **address** saying who may spend it.

In the UTXO model there are no balances stored anywhere: your "balance" is just
the sum of the UTXOs you control. A transaction **consumes** some existing
outputs as its *inputs* and **produces** new outputs. An output can be spent
exactly once; once consumed it is gone, and new outputs take its place.

Cardano uses the **extended UTXO (EUTXO)** model, which generalises plain UTXO
in two ways:

- **Outputs can carry arbitrary data (a *datum*).** A plain UTXO only holds a
  value and an address. An EUTXO output can additionally attach a piece of
  application data, letting a UTXO represent the state of an on-chain
  application rather than just a coin.
- **Outputs can be locked by a *script* instead of a public key.** A plain UTXO
  is unlocked by a signature from the owning key. An EUTXO output can instead be
  guarded by a program &mdash; a **validator script** &mdash; that decides
  whether a given transaction is allowed to spend it.

Crucially, EUTXO keeps the determinism of plain UTXO. A validator only sees the
transaction it is validating and that transaction's own data; it cannot depend
on global, mutable state. This means the outcome of validation can be computed
**off-chain, in advance** &mdash; you can know whether your transaction will
succeed before you submit it, and what it will cost.

## Why smart contracts are needed

A signature-locked output answers only one question: "did the right person sign
this?" That is enough to send coins from one party to another, but not enough to
express richer conditions &mdash; for example, "these funds may be spent only by
the highest bidder, and only after the auction has closed."

**Smart contracts** fill that gap. On Cardano a smart contract is, concretely, a
**validator script** attached to an EUTXO output. When a transaction tries to
spend that output, every node runs the validator as part of checking the
transaction. The validator is given:

- the **datum** attached to the output being spent (the on-chain state),
- a **redeemer** supplied by the transaction (the spender's argument, such as
  "I am bidding 100 ada"), and
- the **script context** &mdash; a view of the transaction itself: its inputs,
  outputs, signatures, validity interval, and so on.

From these the validator returns success or failure. If it fails, the whole
transaction is rejected and the output stays put. In other words, the contract
does not "move funds" itself; it decides whether a *proposed* transaction is
allowed to. This keeps validation local and deterministic, exactly as the EUTXO
model requires.

This is where Plinth comes in: it is the language you write these validators in.
Plinth code is compiled down to **Plutus Core**, the low-level language the
Cardano ledger actually executes.

## Further reading

- [How smart contracts run: Plutus Core and the CEK machine]({% link explanation/plutus-core.md %})
  &mdash; what validators are compiled to, and how the ledger evaluates them.
- [The Plinth standalone compiler]({% link explanation/standalone-compiler.md %})
- [Cardano][cardano]

[cardano]: https://cardano.org/
