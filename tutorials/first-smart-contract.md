---
title: Your first smart contract with Plinth (Linux)
permalink: /tutorials/first-smart-contract/
---
Before writing a real validator, it helps to get the whole toolchain working
end to end with the simplest possible Plinth program: a function that adds two
numbers. In this tutorial you will create a tiny project from scratch, compile
it with `uplc-ghc`, run it, and read the Plutus Core it produced.

This tutorial targets **Linux**. Windows and macOS walkthroughs will follow
later.

## Before you start

You need a built `uplc-ghc`. If you have not built it yet, follow
[Install Plinth standalone compiler]({% link how-to/build.md %}) first &mdash;
this tutorial waits for you here. Note where the `uplc-ghc` binary ended up;
throughout this tutorial, replace `/path/to/uplc-ghc` with its actual path.

You will also need a recent `cabal` (3.8 or newer) on your `PATH`.

## Step 1: Create the project

Make a new directory and add the three files below.

**`cabal.project`** wires up the build. It points cabal at `uplc-ghc`; pulls the
Plinth libraries (`plutus-tx`, `plutus-core`, `plutus-tx-plugin`) from the
`ghc-plinth-plutus` fork the compiler was built against; uses the Cardano
package repository (CHaP) for the remaining dependencies; and builds the Cardano
crypto C libraries (`libsodium`, `secp256k1`, `blst`) from source via the
`*-clib` blocks, so you do not need them installed on your system:

```haskell
with-compiler: /path/to/uplc-ghc

packages: .

repository cardano-haskell-packages
  url: https://chap.intersectmbo.org/
  secure: True
  root-keys:
    3e0cce471cf09815f930210f7827266fd09045445d65923e6d0238a6cd15126f
    443abb7fb497a134c343faf52f0b659bd7999bc06b7f63fa76dc99d631f9bea1
    a86a1f6ce86c449c46666bda44268677abf29b5b2d2eb5ec7af903ec2f117a82
    bcec67e8e99cabfa7764d75ad9b158d72bfacf70ca1d0ec8bc6b4406d1bf8413
    c00aae8461a256275598500ea0e187588c35a5d5d7454fb57eac18d9edb86a56
    d4a35cd3121aa00d18544bb0ac01c3e1691d618f462c46129271bccf39f7e8ee

index-state:
  , hackage.haskell.org 2025-09-21T21:31:06Z
  , cardano-haskell-packages 2026-01-24T11:25:12Z

-- The Plinth libraries, from the fork uplc-ghc was built against.
source-repository-package
  type: git
  location: https://github.com/input-output-hk/ghc-plinth-plutus
  tag: 33decd91baf18e76927ffd97a6c3d0ab571bbdb6
  subdir: plutus-tx
          plutus-core
          plutus-tx-plugin

source-repository-package
  type: git
  location: https://github.com/hsyl20/cardano-base
  tag: 8ea819bb548583b63b4926170a891e91e4f7c17b
  subdir: cardano-crypto-class
          cardano-crypto-praos

source-repository-package
  type: git
  location: https://github.com/haskell-cryptography/blst-clib
  tag: 0fd1d38d5ceed5529ac646efae3095b493a97927

source-repository-package
  type: git
  location: https://github.com/haskell-cryptography/libsodium-clib
  tag: 985c18f75a71ff721370940666d71fda53edbb14

source-repository-package
  type: git
  location: https://github.com/haskell-cryptography/secp256k1-clib
  tag: 211b95baad422966c9e719ed70cbc189c58eaae5

package secp256k1-clib
  flags: +schnorrsig +recovery +ecdh +extrakeys

package cardano-crypto-class
  flags: +use-haskell-clibs

package cardano-crypto-praos
  flags: +use-haskell-clibs

package sodium-clib
  -- disable -fPIE: the static boot libraries are not built with it, so the
  -- link phase fails otherwise.
  configure-options: --enable-pie=no
```

Use the `ghc-plinth-plutus` commit that matches your `uplc-ghc`: the compiler and
these libraries are released together as a matched set, built from the same
commit. The commit above matches this guide's compiler; for a different
`uplc-ghc`, use the plutus commit it was built from.

**Not for production.** The vendored crypto C libraries pulled in by the
`*-clib` `source-repository-package`s above have not been audited. Use this
setup for learning and experimentation only &mdash; never for contracts that
handle real funds.
{:.warning}

**`plinth-add.cabal`** describes the single executable. The `ghc-options` are
the flags Plinth needs to compile predictably (turning off optimisations that
would reshape the code before the plugin sees it) and to select the Plutus Core
version to target:

```haskell
cabal-version: 3.0
name:          plinth-add
version:       0.1.0.0
build-type:    Simple

executable plinth-add
  main-is:            Main.hs
  default-language:   Haskell2010
  default-extensions: DataKinds
  build-depends:
    , base
    , text
    , prettyprinter
    , plutus-tx        ^>=1.57
    , plutus-core      ^>=1.57
    , plutus-tx-plugin
  ghc-options:
    -fexternal-interpreter
    -fobject-code -fno-full-laziness -fno-ignore-interface-pragmas
    -fno-omit-interface-pragmas -fno-spec-constr -fno-specialise
    -fno-strictness -fno-unbox-small-strict-fields
    -fno-unbox-strict-fields
    -fplugin-opt PlutusTx.Plugin:target-version=1.1.0
```

**`Main.hs`** is the whole program. It defines the on-chain function, compiles
it to Plutus Core with a Template Haskell splice, and writes the result out as
readable UPLC:

```haskell
{-# LANGUAGE TemplateHaskell #-}

module Main where

import PlutusTx
import qualified PlutusTx.Prelude as Tx
import qualified PlutusTx.Code as Code
import PlutusCore.Pretty (prettyPlcReadableSimple)
import Prettyprinter (defaultLayoutOptions, layoutPretty)
import Prettyprinter.Render.Text (renderStrict)
import Data.Text (unpack)

-- The on-chain function: add two integers.
addTyped :: Integer -> Integer -> Integer
addTyped x y = x Tx.+ y

-- Compile it to Plutus Core at compile time.
addScript :: CompiledCode (Integer -> Integer -> Integer)
addScript = $$(compile [|| addTyped ||])

-- Render compiled code as readable UPLC text.
renderUPLC :: CompiledCode a -> String
renderUPLC =
    unpack
  . renderStrict
  . layoutPretty defaultLayoutOptions
  . prettyPlcReadableSimple
  . Code.getPlcNoAnn

main :: IO ()
main = writeFile "add.uplc" (renderUPLC addScript)
```

The typed quote `[|| addTyped ||]` and the `compile` splice are the only
Plinth-specific pieces; `PlutusTx.Prelude` (imported as `Tx`) supplies the
on-chain `+`, and everything else is ordinary Haskell.

## Step 2: Build it

```console
$ cabal update
$ cabal build
```

The first run clones and builds the Plinth libraries and the crypto C libraries
from source, so expect it to take a while. Because the Plinth plugin is built
into `uplc-ghc`, no extra plugin configuration is required: the `compile` splice
is translated to Plutus Core as part of the normal build.

## Step 3: Run it

```console
$ cabal run plinth-add
```

`main` runs and writes the compiled program to `add.uplc` in the current
directory.

## Step 4: Look at the Plutus Core

```console
$ cat add.uplc
```

You should see something like:

```
program 1.1.0 (\x y -> addInteger x y)
```

That is the [UPLC]({% link explanation/uplc.md %}) your two-line Haskell function
compiled to &mdash; the `+` became the `addInteger` builtin, wrapped in a
`program` with its [language version]({% link explanation/uplc.md %}). This is
exactly the kind of code the Cardano ledger executes, produced from Haskell by
`uplc-ghc`.

## Where to go next

- [Use uplc-ghc in a project]({% link how-to/use.md %}) &mdash; the same compiler
  setup, described on its own.
- [The Plinth contract language]({% link explanation/plinth-language.md %})
  &mdash; how a real validator is written, beyond this toy function.
- [Generate a blueprint]({% link how-to/generate-blueprint.md %}) &mdash; package
  a compiled script for off-chain tooling. (A tutorial walking through it on a
  small example is coming.)
- [Test a Plinth contract locally]({% link how-to/test.md %}) &mdash; evaluate a
  compiled validator and measure its execution budget, with no node.
