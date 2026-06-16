---
title: "The UPLC language: terms, builtins, and versions"
permalink: /explanation/uplc/
---
[How smart contracts run]({% link explanation/plutus-core.md %}) explained that
the ledger executes **Untyped Plutus Core (UPLC)** and how the CEK machine
evaluates it. This page looks at the language itself: what a UPLC program looks
like, the built-in functions ("primops") it provides, and how the language has
grown across Cardano's hard forks.

You do not write UPLC by hand &mdash; it is a compilation target, the assembly
of Cardano. But knowing its shape makes the rest of the system legible: it is a
very small language, and almost all of its real capability lives in its
builtins.

## What a program looks like

A UPLC program is a version number wrapped around a single **term**:

```
(program 1.1.0 <term>)
```

The term language is tiny. It is the untyped lambda calculus plus a handful of
extras:

- **variables** &mdash; `x`
- **lambda abstraction** &mdash; `(lam x <body>)`
- **application** &mdash; `[ <fun> <arg> ]` (note the square brackets; it is
  curried, so `[ [ f x ] y ]` applies `f` to two arguments)
- **constants** &mdash; `(con <type> <value>)`, e.g. `(con integer 42)`
- **builtins** &mdash; `(builtin addInteger)`
- **delay / force** &mdash; `(delay <term>)` suspends evaluation; `(force <term>)`
  resumes it
- **error** &mdash; `(error)`, which aborts evaluation and fails the script

A small complete program that adds two integers:

```
(program 1.1.0
  [ [ (builtin addInteger) (con integer 2) ] (con integer 3) ]
)
```

Because the language is *untyped*, nothing stops a nonsensical term such as
applying an integer as if it were a function; the machine simply evaluates such
a term to `(error)` when it reaches it. The `delay` and `force` forms above look
odd in isolation; they are tied to *how* UPLC evaluates, which the next section
explains.

## Evaluation order: strictness, `delay`, and `force`

UPLC is **strict** &mdash; call-by-value. When the [CEK
machine]({% link explanation/plutus-core.md %}) evaluates an application
`[ f x ]`, it reduces `f` to a function and then reduces `x` to a *value* before
performing the call; the argument is always evaluated first. The same holds for
the fields of a `constr` and the operands of a builtin: a subterm is evaluated as
soon as it is reached. Only a few forms are values in their own right and are
*not* evaluated until used &mdash; a `(lam ...)`, a `(con ...)`, a
partially-applied `(builtin ...)`, and, crucially, a `(delay ...)`.

Strictness has a sharp consequence: there is no built-in laziness. If you express
a conditional by passing both outcomes as ordinary arguments, *both* are
evaluated before the conditional can choose &mdash; wasted work at best, and an
outright failure if the branch not taken contains an `(error)`. UPLC's answer is
to make suspension explicit:

- `(delay M)` packages `M` as a value **without** evaluating it &mdash; a thunk.
- `(force t)` runs a thunk: it resumes evaluation of the `M` inside a `delay`.

So `force (delay M)` evaluates `M`, and that round trip is the only way to defer
a computation and later resume it.

### Two jobs, one pair of operators

`delay` and `force` end up doing two distinct things, which is why compiled UPLC
is so full of them:

1. **Laziness.** Wrap a term in `delay` to stop strict evaluation from running it
   too early, and `force` it at the point you actually want it.
2. **Type instantiation.** The typed languages that compile to UPLC are
   *polymorphic*: a function like `ifThenElse` has type
   `forall a. bool -> a -> a -> a`, and before use you must pick the concrete
   type `a` &mdash; in a typed language, by a **type application**. UPLC has no
   types, so there is nothing to pass; but the type applications cannot simply be
   deleted, because that would change *when* subterms evaluate. So type erasure
   rewrites every type abstraction to a `(delay ...)` and every type application
   to a `(force ...)`. A polymorphic builtin is therefore *instantiated by forcing
   it*.

The standard conditional shows both jobs at once. `ifThenElse` is polymorphic, so
it is forced once to instantiate it; and because evaluation is strict, the two
branches are wrapped in `delay` so that only the chosen one runs, after which the
result is forced:

```
(force
  [ [ [ (force (builtin ifThenElse)) <cond> ]
      (delay <then>) ]
    (delay <else>) ])
```

The inner `(force (builtin ifThenElse))` instantiates the builtin (job 2); the
two `(delay ...)` keep both branches unevaluated (job 1); `ifThenElse` returns
whichever thunk matches `<cond>`; and the outer `(force ...)` runs just that one.

### The builtin checklist

Because forces are real evaluation steps, the machine is exact about how many it
expects. Every builtin carries a fixed sequence of steps, read off its type: each
`->` is a "supply an argument" step, each `forall` is a "force me" step.

```
addInteger : integer -> integer -> integer    steps: arg, arg
ifThenElse : forall a. bool -> a -> a -> a     steps: force, arg, arg, arg
```

The machine walks this sequence and expects exactly the next item. Supply an
argument where a `force` is due (or force where an argument is due) and the
builtin application is malformed: evaluation raises an error and the script
fails. Stop early &mdash; never completing the sequence &mdash; and you are left
with an unsaturated builtin value that simply never computes. Either way, a
missing or stray `force` is never silently ignored: it is the erased type
instantiation, and the machine counts every one.

## Built-in types

Constants are drawn from a fixed set of built-in types:

- `integer` (arbitrary precision), `bytestring`, `string`, `unit`, `bool`
- `(list T)` and `(pair T T)` of other built-in types
- `data` &mdash; the universal tree used for script arguments (see below)
- the BLS12-381 elements `bls12_381_G1_element`, `bls12_381_G2_element`, and
  `bls12_381_mlresult`

The `data` type is the most important in practice. It is the encoding every
[datum and redeemer]({% link explanation/cardano-blockchain.md %}) uses on the
wire: a tree of tagged **constructors**, **maps**, **lists**, **integers**
(`I`), and **byte strings** (`B`). The [blueprint
schema]({% link explanation/blueprints.md %}) is precisely a description of which
`data` shape a given script expects.

## Built-in functions (primops)

The bulk of UPLC's power is its **default builtins**. The original set, present
since the first version, groups into:

- **Integers** &mdash; `addInteger`, `subtractInteger`, `multiplyInteger`,
  `divideInteger`, `quotientInteger`, `remainderInteger`, `modInteger`,
  `equalsInteger`, `lessThanInteger`, `lessThanEqualsInteger`
- **Byte strings** &mdash; `appendByteString`, `consByteString`,
  `sliceByteString`, `lengthOfByteString`, `indexByteString`,
  `equalsByteString`, `lessThanByteString`, `lessThanEqualsByteString`
- **Hashing and signatures** &mdash; `sha2_256`, `sha3_256`, `blake2b_256`,
  `verifyEd25519Signature`
- **Strings** &mdash; `appendString`, `equalsString`, `encodeUtf8`, `decodeUtf8`
- **Control** &mdash; `ifThenElse`, `chooseUnit`, `trace`
- **Pairs** &mdash; `fstPair`, `sndPair`
- **Lists** &mdash; `chooseList`, `mkCons`, `headList`, `tailList`, `nullList`
- **Data** &mdash; `chooseData`, `constrData`, `mapData`, `listData`, `iData`,
  `bData`, `unConstrData`, `unMapData`, `unListData`, `unIData`, `unBData`,
  `equalsData`, `mkPairData`, `mkNilData`, `mkNilPairData`

Each builtin carries a fixed cost in [CPU and memory
units]({% link explanation/plutus-core.md %}), which is what makes metered
execution possible. Later versions add more builtins, covered next.

## Sum-of-products terms

UPLC language version **1.1.0** adds two term forms for sums of products,
letting datatypes be encoded directly rather than via Scott encoding:

- `(constr i <term> ...)` &mdash; build the `i`-th variant with the given fields
- `(case <term> <branch> ...)` &mdash; branch on a `constr` value

These usually produce smaller, cheaper code than the lambda encodings they
replace. Whether one of your datatypes is represented this way or directly as
`data` is a choice &mdash; see [Data
representation]({% link explanation/data-representation.md %}).

## How the language has grown

There are *two* version numbers in play, and they are easy to conflate:

- The **UPLC language version** &mdash; the number in `(program X.Y.Z ...)`.
  `1.0.0` is the original language; `1.1.0` adds the `constr`/`case` terms above.
- The **Plutus ledger language version** &mdash; `PlutusV1`, `PlutusV2`,
  `PlutusV3`. This is what a script *tags itself as* on-chain, and it governs
  which builtins are allowed and what the [script
  context]({% link explanation/cardano-blockchain.md %}) looks like.

On top of that, individual builtins are switched on at specific Cardano **hard
forks** (protocol versions), and the same builtin can become available to
different ledger languages at different times. For the current `PlutusV3`
language the introductions run:

| Hard fork (protocol version) | Introduced for PlutusV3 |
|------------------------------|--------------------------|
| Chang &mdash; 2024 (PV 9)    | UPLC `1.1.0` (`constr`/`case`); BLS12-381 G1/G2 and pairing ops, `keccak_256`, `blake2b_224`; `integerToByteString`, `byteStringToInteger`; plus the original set and `serialiseData`, `verifyEcdsaSecp256k1Signature`, `verifySchnorrSecp256k1Signature` |
| Plomin &mdash; 2025 (PV 10)  | logical/bitwise byte-string ops (`andByteString`, `orByteString`, `xorByteString`, `complementByteString`, `shiftByteString`, `rotateByteString`, `readBit`, `writeBits`, `replicateByte`, `countSetBits`, `findFirstSetBit`); `ripemd_160` |
| van Rossem &mdash; upcoming (PV 11) | *(planned)* `expModInteger`, `dropList`, array ops (`lengthOfArray`, `listToArray`, `indexArray`), BLS multi-scalar multiplication, and `Value` operations |

The older ledger languages started smaller:

- **PlutusV1** (Alonzo, 2021) launched with the original builtin set and UPLC
  `1.0.0` only.
- **PlutusV2** (Vasil, 2022) added `serialiseData`, and at the Valentine hard
  fork (2023) the two Secp256k1 signature builtins.

The **van Rossem** hard fork (protocol version 11, targeted for 2026 and not yet
live at the time of writing) is set to *unify* the builtins: it makes the full
set available across `PlutusV1`, `PlutusV2`, and `PlutusV3` and brings UPLC
`1.1.0` to all three. After it, the languages will differ chiefly in their
script context rather than in which builtins they offer.

A few of these have specific motivations worth noting: `keccak_256` and
`ripemd_160` provide Ethereum- and Bitcoin-compatible hashing; the BLS12-381
operations enable pairing-based cryptography (threshold signatures, zero-knowledge
proofs); and `integerToByteString`/`byteStringToInteger` plus the bitwise ops let
contracts implement cryptographic primitives efficiently in-script.

## Ledger language versions and the script context

What now most distinguishes `PlutusV1`, `PlutusV2`, and `PlutusV3` is the shape
of the script context the validator receives:

- **PlutusV1** &mdash; the original transaction view: inputs, outputs, fee, mint,
  certificates, withdrawals, validity interval, signatories, datums, and the
  transaction id.
- **PlutusV2** &mdash; extends it with the features the Vasil ledger introduced:
  **reference inputs**, **inline datums**, **reference scripts**, and the full
  map of redeemers.
- **PlutusV3** &mdash; reworks the context for **governance**: it adds votes,
  proposal procedures, and treasury fields, and generalises the notion of what a
  script can be invoked for (spending, minting, rewarding, certifying, plus the
  new voting and proposing purposes).

A script must pick one of these languages; the ledger supplies the matching
context and enforces the matching set of allowed builtins.

## Further reading

- [How smart contracts run: Plutus Core and the CEK machine]({% link explanation/plutus-core.md %})
  &mdash; what UPLC is and how it is executed and metered.
- [From Plinth to the chain]({% link explanation/from-plinth-to-the-chain.md %})
  &mdash; how this UPLC is produced, serialised, and attached to a transaction.
- [The Cardano blockchain]({% link explanation/cardano-blockchain.md %}) &mdash;
  the script context and the eUTXO model behind it.
- [Plutus Core specification][plc-spec] &mdash; the formal grammar and semantics.

[plc-spec]: https://plutus.cardano.intersectmbo.org/resources/plutus-core-spec.pdf
