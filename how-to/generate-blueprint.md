---
title: Generate a blueprint
permalink: /how-to/generate-blueprint/
---
This guide shows how to produce a [CIP-57
blueprint]({% link explanation/blueprints.md %}) for one or more of your scripts
from off-chain Haskell. A blueprint is built as an ordinary value and written to
a JSON file; the helpers live in `PlutusTx.Blueprint`.

It assumes you already have a compiled validator or minting policy (a
`CompiledCode`) &mdash; see
[The structure of a Plinth smart contract]({% link explanation/structure.md %}).

## Step 1: Give your types schema instances

`deriveDefinitions` and `definitionRef` (below) need a blueprint **schema** for
each datum, redeemer, and parameter type. Derive it alongside the `Data`
instances with `makeIsDataSchemaIndexed` (see
[The Plinth contract language]({% link explanation/plinth-language.md %})):

```haskell
PlutusTx.makeIsDataSchemaIndexed ''AuctionRedeemer [('NewBid, 0), ('Payout, 1)]
PlutusTx.makeIsDataSchemaIndexed ''AuctionParams   [('AuctionParams, 0)]
```

## Step 2: Describe the contract

Build the blueprint as a value. It has three parts: a preamble of metadata, a
set of validators, and the schema definitions.

The **preamble** is plain metadata:

```haskell
myPreamble :: Preamble
myPreamble = MkPreamble
  { preambleTitle         = "Auction Validator"
  , preambleDescription   = Just "Blueprint for a Plutus auction script"
  , preambleVersion       = "1.0.0"
  , preamblePlutusVersion = PlutusV3
  , preambleLicense       = Just "MIT"
  }
```

Each **validator** names its arguments and carries the compiled code. The
argument schemas are *references* (`definitionRef @T`) into the definitions
registry rather than inline schemas, and the code is the
[serialised script]({% link explanation/from-plinth-to-the-chain.md %}) wrapped
with `compiledValidator`, which also computes the hash:

```haskell
import PlutusLedgerApi.Common (serialiseCompiledCode)
import Data.ByteString.Short qualified as Short

myValidator :: ValidatorBlueprint referencedTypes
myValidator = MkValidatorBlueprint
  { validatorTitle       = "Auction Validator"
  , validatorDescription = Just "Validates auction transactions"
  , validatorParameters  =
      [ MkParameterBlueprint
          { parameterTitle   = Just "Parameters"
          , parameterDescription = Just "Compile-time validator parameters"
          , parameterPurpose = Set.singleton Spend
          , parameterSchema  = definitionRef @AuctionParams
          }
      ]
  , validatorRedeemer    = MkArgumentBlueprint
      { argumentTitle       = Just "Redeemer"
      , argumentDescription = Just "Redeemer for the auction validator"
      , argumentPurpose     = Set.fromList [Spend]
      , argumentSchema      = definitionRef @AuctionRedeemer
      }
  , validatorDatum       = Nothing
  , validatorCompiled    =
      let code = Short.fromShort (serialiseCompiledCode (auctionValidatorScript params))
       in Just (compiledValidator PlutusV3 code)
  }
```

## Step 3: Assemble the `ContractBlueprint`

Combine the preamble and validators, and generate the schema registry with
`deriveDefinitions` over every type the validators reference:

```haskell
myContractBlueprint :: ContractBlueprint
myContractBlueprint = MkContractBlueprint
  { contractId          = Just "auction-validator"
  , contractPreamble    = myPreamble
  , contractValidators  = Set.singleton myValidator
  , contractDefinitions = deriveDefinitions @[AuctionParams, AuctionDatum, AuctionRedeemer]
  }
```

The `definitionRef @T` in Step 2 and the type list given to `deriveDefinitions`
must agree: every type you reference must appear here so its schema is emitted.

## Step 4: Write it to a file

`writeBlueprint` serialises the whole thing to JSON. Wrap it in a small
executable so you can regenerate the blueprint with `cabal run`:

```haskell
main :: IO ()
main = do
  [path] <- getArgs
  writeBlueprint path myContractBlueprint
```

```console
$ cabal run gen-auction-validator-blueprint -- auction-validator.json
```

Use `encodeBlueprint :: ContractBlueprint -> LBS.ByteString` instead if you want
the JSON in memory rather than on disk.

## What is derived and what you fill in

A blueprint is part machine-derived, part hand-written:

- **Derived from the script:** the argument schemas (from your types'
  `makeIsDataSchemaIndexed` instances, via `deriveDefinitions`/`definitionRef`),
  the compiled code, and its hash (via `compiledValidator`).
- **Filled in explicitly:** all the descriptive metadata &mdash; titles,
  descriptions, version, license, the Plutus version, and each argument's
  purpose.

For **several scripts** in one blueprint, add more `ValidatorBlueprint` values to
`contractValidators` (it is a `Set`) and list all of their types in
`deriveDefinitions`.

One thing to check: the version passed to `compiledValidator` and set in
`preamblePlutusVersion` must match the [Plutus
version]({% link explanation/uplc.md %}) your script actually targets.

## See also

- [Contract blueprints (CIP-57)]({% link explanation/blueprints.md %}) &mdash;
  what a blueprint contains and how it is used.
- [The structure of a Plinth smart contract]({% link explanation/structure.md %})
  &mdash; where blueprint generation sits in the off-chain code.
- [The Plinth contract language]({% link explanation/plinth-language.md %})
  &mdash; deriving the `Data` and schema instances the blueprint needs.
