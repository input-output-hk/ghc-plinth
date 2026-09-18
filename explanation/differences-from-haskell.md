---
title: "Differences from Haskell"
permalink: /explanation/differences-from-haskell/
---
[The Plinth contract language]({% link explanation/plinth-language.md %}) said
that Plinth *is* Haskell, restricted to the part the compiler can translate to
[UPLC]({% link explanation/uplc.md %}). This page maps out that restriction:
which Haskell features Plinth does not support, the error message each one
triggers, and &mdash; because none of these limits is arbitrary &mdash; the
reason behind each one.

Almost every reason traces back to two properties of the target language. UPLC
is a small, strict lambda calculus with a fixed set of builtin types and
functions; and a script is re-evaluated by every node in the network, possibly
years after it was written, where it must produce bit-identical results within
a fixed execution budget. Features are unsupported either because UPLC has no
counterpart for them, or because they would break that determinism.

## Semantic differences

Before the unsupported features, two things that *compile* but behave
differently from Haskell:

- **Function applications are strict.** Evaluating `(\x -> 42) (3 + 4)`
  evaluates `3 + 4` first, even though `x` is unused. A lazy pattern on the
  parameter does not change this.
- **Bindings are non-strict, but not lazy.** A `let` binding is by default not
  evaluated until used &mdash; but it is re-evaluated on *every* use, not
  memoized as in Haskell. A bang pattern (`let !x = ...`) makes a binding
  strict; under the `Strict` extension (which the standard Plinth flags turn
  on) bindings are strict by default and a lazy pattern (`~`) opts out.

Keep the re-evaluation in mind: a non-strict binding used three times costs
its evaluation three times of the script budget.

## How the compiler reports an unsupported feature

The Plinth compiler runs after GHC's type checker, so these errors appear when
the module is compiled, not in an IDE that only type-checks. An error carries a
source location, a `PLINTH` error code, the reason, and usually a suggestion:

```
Auction.hs:9:10: error: [PLINTH-00004]
    Plinth Compilation Error:
    Context: Compiling code at Auction.hs:9:10-62:
             GHC.Num.Integer.integerEq
    Error: Unsupported feature: GHC.Classes.Eq.==, use PlutusTx.Eq.Eq
  |
9 | code = $$(PlutusTx.compile [|| \x -> x == (42 :: Integer) ||])
  |          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

The `Context:` lines show the chain of code the compiler was processing,
innermost last. They show GHC Core &mdash; the intermediate language the
compiler consumes &mdash; so the code can look different from the source
(`==` above appears as `integerEq`, the function GHC resolved it to).

The error codes are:

| Code           | Meaning                                              |
|----------------|------------------------------------------------------|
| `PLINTH-00001` | Error from the Plutus Core compiler                  |
| `PLINTH-00002` | Error from the PIR compiler                          |
| `PLINTH-00003` | Internal error; please report it to the Plutus team  |
| `PLINTH-00004` | Unsupported feature                                  |
| `PLINTH-00005` | Reference to a name without an accessible definition |
| `PLINTH-00006` | Misused compiler marker                              |
| `PLINTH-00007` | Internal name lookup error; please report it         |

The plugin option `-fplugin-opt Plinth.Plugin:preserve-source-locations` makes
locations more precise: the compiler then tracks the locations of variables,
class methods and literals through the compilation, at a small compile-time
cost.

## The unsupported features, and why

Each section names a feature, shows the error it triggers, and explains the
reason.

### Machine integers: `Int`, `Word`, `Word8`, ..., `Word64`

```
Error: Unsupported feature: Int: use Integer instead
```

UPLC has one integer type: arbitrary-precision `integer`, which `Integer` maps
onto. Fixed-width types silently wrap around on overflow &mdash; behavior you
do not want anywhere near code that moves funds &mdash; and UPLC has no
fixed-width arithmetic to compile them to. Use `Integer`.

### Floating point: `Double`, `Float`

```
Error: Unsupported feature: Type GHC.Types.Double is not supported in Plinth; use Integer or PlutusTx.Ratio.Rational instead
```

UPLC has no floating-point builtins, deliberately: floating-point results can
differ between platforms and optimization levels, while every node must compute
exactly the same result. Use `Integer`, or `PlutusTx.Ratio.Rational` for exact
fractions.

### Characters and `String` literals

```
Error: Unsupported feature: Literal string (maybe you need to use OverloadedStrings)
Error: Unsupported feature: Literal char
```

Haskell's `String` is a linked list of `Char`, and UPLC has no character type.
Text on-chain is the builtin `string` type, surfaced as `BuiltinString`.
Enable `OverloadedStrings` so string literals produce `BuiltinString` values;
use them mainly for trace messages, and `BuiltinByteString` for data.

### `Data.Text` and `Data.ByteString`

```
Error: Unsupported feature: Type Data.Text.Internal.Text is not supported in Plinth; use BuiltinString instead
Error: Unsupported feature: Type Data.ByteString.Internal.Type.ByteString is not supported in Plinth; use BuiltinByteString instead
```

These types wrap memory buffers managed by the GHC runtime, and there is no
GHC runtime on-chain. Their on-chain equivalents are the builtins
`BuiltinString` and `BuiltinByteString`.

### Type classes from `base`: `Eq`, `Ord`, `Show`, `Enum`

```
Error: Unsupported feature: GHC.Classes.Eq.==, use PlutusTx.Eq.Eq
Error: Unsupported feature: GHC.Show.Show.show, use PlutusTx.Show.Show
```

The `base` instances of these classes are compiled for the GHC runtime: they
work on machine integers, produce `String` values, and usually ship without
the unfoldings the Plinth compiler needs (see
[below](#functions-without-unfoldings)). `PlutusTx.Prelude` provides on-chain
versions &mdash; `PlutusTx.Eq`, `PlutusTx.Ord`, `PlutusTx.Show`,
`PlutusTx.Enum` &mdash; whose methods compile to UPLC builtins. Import it and
you keep writing `==` and `compare`; they simply resolve to the on-chain
classes.

### Range syntax

```
Error: Unsupported feature: Range syntax, use PlutusTx.Enum.enumFromTo or PlutusTx.Enum.enumFromThenTo
Error: Unsupported feature: Unbounded range syntax: unbounded ranges are not supported
```

`[a .. b]` is sugar for methods of the `base` `Enum` class, which is
unsupported. Use `PlutusTx.Enum.enumFromTo` or `enumFromThenTo` &mdash; and
note they build the whole list, at a budget cost proportional to its length.
An unbounded range such as `[a ..]` describes an infinite list; under strict,
budgeted evaluation an infinite structure can never be evaluated, so there is
no useful way to compile one.

### `error` and `undefined` from `Prelude`

```
Error: Unsupported feature: GHC.Err.error, use PlutusTx.Prelude.error or PlutusTx.Prelude.traceError
```

`Prelude.error` takes a `String` message and an implicit call stack, and
raises a Haskell runtime exception. None of that exists on-chain: script
failure is the UPLC `error` term, and diagnostic messages are trace strings.
Use `PlutusTx.Prelude.error`, or `traceError` to attach a message.

### `IO` and FFI

```
Error: Unsupported feature: IO actions are not supported in Plinth
```

A validator is a pure function. Every node re-runs it and must reach the same
verdict, and there is no runtime system on-chain to perform effects. Do
effectful work off-chain and pass the results to the script as arguments.

### Pattern matching on `Integer` literals

```
Error: Unsupported feature: Cannot pattern match on a value of type 'Integer'.
```

Pattern matching compiles to case analysis on data constructors, and the
builtin `integer` type has no constructors. A literal pattern like `f 42 = ...`
desugars into matches on the internal representation of `Integer`, which
exposes machine words. Use equality with guards instead:

```haskell
f n | n == 42   = ...
    | otherwise = ...
```

GHC optimizations can also produce such matches from innocent-looking code;
the full error message lists the flags that prevent this (the standard Plinth
flags include them).

### Recursive newtypes

```
Error: Unsupported feature: Recursive newtypes, use data: Auction.Stream
```

A `newtype` compiles to a transparent type alias, which is what makes it free
at runtime &mdash; and a recursive alias would unfold forever. A `data` type
compiles to a real datatype, which supports recursion; use `data` for
recursive types.

### Mutually recursive data types

```
Error: Error from the PIR compiler:
       Unsupported construct: Mutually recursive datatypes: Forest, Rose ({ Auction.hs:9:1-9:27 })
```

The compiler's intermediate language encodes a recursive datatype as a fixed
point of a single type. There is no encoding for a group of types that recurse
through each other yet. Merge the group into a single datatype, or break the
cycle by inlining one type into the other.

### Existential types and GADTs

```
Error: Unsupported feature: Existential quantification in data constructor Auction.Box
Error: Unsupported feature: Following extensions are not supported: GADTs
```

On-chain datatypes are plain sums of products: a constructor takes value
arguments whose types only mention the datatype's own type parameters. A
constructor cannot bind its own type variables (existentials) or refine the
result type (GADTs) &mdash; the datatype encoding has no representation for
either. The `GADTs` extension is rejected as a whole in modules that contain
compiled code.

### Type families

```
Error: Unsupported feature: Irreducible type family application: Auction.F
```

There is no type-level computation on-chain. A type family application
compiles only when GHC fully reduces it during type checking; an application
that remains &mdash; an open family with no matching instance, say &mdash;
cannot be translated.

### Kind polymorphism (`PolyKinds`)

```
Error: Unsupported feature: Following extensions are not supported: PolyKinds
```

On-chain kinds are `*` and arrow kinds only; there are no kind variables.

### Functions without unfoldings

```
Error: Reference to a name which is not a local, a builtin, or an external INLINABLE function: Variable Auction.opaque
       No unfolding
```

The compiler translates the GHC Core definition (the "unfolding") of every
function the compiled code references, and GHC only stores unfoldings in
interface files under certain conditions. Mark on-chain functions
`{-# INLINEABLE #-}` and build with the standard Plinth flags &mdash; see
[`INLINEABLE` and the plugin]({% link explanation/plinth-language.md %}) and
[Use uplc-ghc in a project]({% link how-to/use.md %}). This is also the error
you get when calling a `base` or third-party function that was never meant to
go on-chain: prefer the `PlutusTx.Prelude` counterpart.

## Further reading

- [The Plinth contract language]({% link explanation/plinth-language.md %})
  &mdash; the overview of what writing Plinth looks like.
- [The UPLC language]({% link explanation/uplc.md %}) &mdash; the builtin
  types and functions everything must compile down to.
- [Plutus Core and the CEK machine]({% link explanation/plutus-core.md %})
  &mdash; the evaluator and its budget.
- [Plinth user guide][plinth] &mdash; the complete language reference.

[plinth]: https://plutus.cardano.intersectmbo.org/docs/
