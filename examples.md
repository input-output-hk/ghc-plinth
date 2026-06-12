---
layout: default
title: Examples
nav_order: 5
---

# Examples

The repository bundles an example Plinth project under `plinth/test/`,
adapted from the [Plinth project template][plinth-template]. It is built and
exercised by [`plinth-test.sh`]({{ '/testing' | relative_url }}).

## Contracts

The example sources live in `plinth/test/src/`:

| File                       | What it demonstrates                                 |
| -------------------------- | ---------------------------------------------------- |
| `AuctionValidator.hs`      | A spending validator for a simple auction.           |
| `AuctionMintingPolicy.hs`  | A minting policy paired with the auction validator.  |
| `Examples.hs`              | Small standalone Plinth snippets used by the tests.  |
| `Utils.hs`                 | Shared helpers used across the examples.             |

A `gen-examples` executable (under `plinth/test/app/`) emits the compiled
Plutus Core for the snippets in `Examples.hs`.

## Generated Plutus Core

Running the test script regenerates the expected outputs under
`plinth/test/examples-output/`, for example:

- `eqCheck.uplc`
- `succ.uplc`

These `.uplc` files contain the Plutus Core that `uplc-ghc` produced for the
corresponding Plinth definitions, and serve as the golden outputs the test
script compares against.

[plinth-template]: https://github.com/IntersectMBO/plinth-template
