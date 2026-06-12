---
title: "How smart contracts run: Plutus Core and the CEK machine"
permalink: /explanation/plutus-core/
---
[The Cardano blockchain]({% link explanation/cardano-blockchain.md %}) explained
that a smart contract on Cardano is a validator script. This page explains what
those scripts actually *are* at the lowest level, and how the ledger *executes*
them.

## What runs on-chain: Untyped Plutus Core

The Cardano ledger executes **Untyped Plutus Core (UPLC)**: a small, low-level
language based on the lambda calculus. UPLC is deliberately tiny &mdash; it has
little more than:

- **functions and application** (the lambda-calculus core),
- a fixed set of **built-in functions** (arithmetic, comparisons, hashing,
  cryptographic checks, operations on the ledger's data, and so on), and
- **constants and built-in data** that those functions operate on.

This minimalism is on purpose. The on-chain language is the part every node must
agree on and re-execute, so it is kept small enough to specify precisely and
implement consistently. Higher-level languages are not run directly by the
ledger; they are compiled down to UPLC, and it is the resulting UPLC that goes
on-chain.

## How it runs: the CEK machine

UPLC is evaluated by an abstract machine called the **CEK machine**. The name
comes from its three pieces of state:

- **C**ontrol &mdash; the term currently being evaluated.
- **E**nvironment &mdash; the bindings of variables currently in scope.
- **K**ontinuation &mdash; what to do next once the current term is reduced (the
  pending work, like a stack of "and then...").

The machine repeatedly takes a small step that transforms this state, reducing
the term until it reaches a final value (or fails). Specifying evaluation as an
abstract machine rather than as informal prose matters here: every Cardano node
must evaluate a given script to *exactly* the same result, so the semantics have
to be precise and deterministic.

## Metered execution

Execution is not free, and it must be bounded &mdash; a node cannot run a
validator that loops forever, and users must pay for the resources they consume.
The CEK machine is therefore **metered**: each step it takes consumes from a
budget of **execution units**, measured along two axes:

- **CPU units** &mdash; roughly, computation time.
- **Memory units** &mdash; roughly, space used.

A transaction declares a budget for each script it runs, and that budget feeds
into the transaction's fee. If a validator exceeds its budget, evaluation is
aborted and the transaction is rejected. Because evaluation is deterministic and
local (see the [EUTXO model]({% link explanation/cardano-blockchain.md %})), the
exact cost can be computed off-chain before submission &mdash; so you know what a
transaction will cost, and whether it will succeed, in advance.

## What the result means

The CEK machine reduces a script to a value, but **the ledger never looks at that
value.** A script is run only to find out whether its evaluation *succeeds*, and
the verdict is binary:

- if the program terminates **without error and within budget**, the script
  **passes** &mdash; whatever value it produced (by convention, unit) is simply
  discarded;
- if it reaches `(error)`, fails because the term is malformed, or exceeds its
  execution budget, the script **fails**.

A validator therefore does not *return* its decision as data; it *signals* it by
either finishing or erroring. There is no boolean for the ledger to read. (A
Plinth validator written to return `Bool` is compiled through a wrapper that
turns `False` into an `(error)` before the code reaches the ledger, precisely so
it fits this succeed-or-fail contract.)

A transaction's script validation succeeds only if **every** script it triggers
passes, and how a failure is handled is worth knowing:

- A **phase-1** failure &mdash; a malformed transaction, bad signatures,
  inconsistent fees &mdash; is rejected before any script runs and never reaches
  the chain.
- A **phase-2** failure &mdash; a script that errors or runs out of budget
  &mdash; is still **recorded on-chain as a failed transaction**: it produces
  none of its intended outputs, but its **collateral** inputs are forfeited to
  pay for the validation work. That forfeiture is the deterrent against
  submitting transactions whose scripts fail.

## Further reading

- [The UPLC language]({% link explanation/uplc.md %}) &mdash; what UPLC programs
  look like, the built-in functions they use, and how the language has grown.
- [The Cardano blockchain]({% link explanation/cardano-blockchain.md %}) &mdash;
  the ledger model these scripts run against.
- [From Plinth to the chain]({% link explanation/from-plinth-to-the-chain.md %})
  &mdash; how Plinth source becomes this UPLC, and how the UPLC reaches a
  transaction.
