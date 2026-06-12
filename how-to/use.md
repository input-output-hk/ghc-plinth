---
title: Use uplc-ghc in a project
permalink: /how-to/use/
---

The recommended way to use the Plinth standalone compiler is to set its path once in `cabal.project`.

```haskell
with-compiler: /path/to/uplc-ghc
packages: .
```

The same file also needs the Cardano package repository (CHaP), which provides
the Cardano dependencies of the Plinth libraries:

```haskell
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
```

Adapt the two `index-state` dates to your project: they pin the CHaP and Hackage
package sets.

The Plinth libraries themselves (`plutus-tx`, `plutus-core`, `plutus-tx-plugin`)
are neither bundled with the compiler nor taken from CHaP. Pull them from the
`ghc-plinth-plutus` fork that `uplc-ghc` was built against:

```haskell
source-repository-package
  type: git
  location: https://github.com/hsyl20/ghc-plinth-plutus
  tag: 33decd91baf18e76927ffd97a6c3d0ab571bbdb6
  subdir: plutus-tx
          plutus-core
          plutus-tx-plugin
```

Use the `ghc-plinth-plutus` commit that matches your `uplc-ghc`: the compiler
and these libraries are released together as a matched set, built from the same
commit.

In addition you may want to add the following `source-repository-package` blocks
that build the C crypto libraries used by Cardano (`libsodium`, `secp256k1`,
`blst`) from source, so you do not need them installed on your system.

**Not for production.** The vendored crypto C libraries pulled in by the
`*-clib` `source-repository-package`s below have not been audited. Use this
setup for learning and experimentation only &mdash; never for contracts that
handle real funds.
{:.warning}

```haskell
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

Then refresh the package index and build:

```console
$ cabal update
$ cabal build
```
