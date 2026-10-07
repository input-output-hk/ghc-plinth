{-# LANGUAGE NoImplicitPrelude #-}
-- In uplc-ghc, -O0 does not imply -fomit-interface-pragmas.
{-# OPTIONS_GHC -O0 #-}
-- On-chain helper without INLINABLE pragma, compiled with -O0.
-- See Note [No INLINABLE pragmas] in no-pragmas/Main.hs.
module NoPragmasO0 (productTo) where

import PlutusTx.Prelude

-- Self-recursive function: GHC never exposes its unfolding on its own.
productTo :: Integer -> Integer
productTo n = if n <= 1 then 1 else n * productTo (n - 1)
