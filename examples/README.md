# Example projects

Working copies of the projects built in the website tutorials
(https://input-output-hk.github.io/ghc-plinth/tutorials/). Keep each project's
files byte-identical to the code blocks of its tutorial page.

- `add/`: "Your first smart contract with Plinth". Compiles an addition
  function and writes it as readable UPLC text (`add.uplc`).
- `lock/`: "Lock and unlock funds on a local chain". Compiles a Plutus V3
  lock/unlock validator and writes it as a cardano-cli text envelope
  (`lock.plutus`), used against a Yaci DevKit devnet.
- `lock-ghci/`: "Lock and unlock funds from GHCi". Off-chain cardano-api
  helpers to use the lock validator interactively. Builds with a standard
  GHC 9.6.7, not with uplc-ghc; reads the `lock.plutus` that `lock/` wrote.
- `lock-ghci-exp/`: "Lock and unlock funds with the experimental
  cardano-api". The same helpers as `lock-ghci/`, rebuilt on
  Cardano.Api.Experimental.

`add/` and `lock/` build with the ghcup-installed compiler: `cabal build`
with `uplc-ghc` and `uplc-ghc-pkg` on PATH.
