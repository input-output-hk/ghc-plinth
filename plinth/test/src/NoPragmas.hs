{-# LANGUAGE NoImplicitPrelude #-}
-- On-chain helpers without INLINABLE pragmas, used by the no-pragmas
-- test-suite from another package component.
-- See Note [No INLINABLE pragmas] in no-pragmas/Main.hs.
module NoPragmas
  ( Shape (..)
  , Area (..)
  , sumAreas
  , sumTo
  , isEven
  , applyN
  ) where

import PlutusTx.Foldable (foldr)
import PlutusTx.Prelude

data Shape = Square Integer | Rect Integer Integer

class Area a where
  area :: a -> Integer

instance Area Shape where
  area (Square s) = s * s
  area (Rect w h) = w * h

-- Function with a class constraint.
sumAreas :: Area a => [a] -> Integer
sumAreas = foldr (\s acc -> area s + acc) 0

-- Self-recursive function: GHC never exposes its unfolding on its own.
sumTo :: Integer -> Integer
sumTo n = if n <= 0 then 0 else n + sumTo (n - 1)

-- Mutually recursive functions.
isEven :: Integer -> Bool
isEven n = n == 0 || isOdd (n - 1)

isOdd :: Integer -> Bool
isOdd n = n /= 0 && isEven (n - 1)

-- Polymorphic function with a local recursive binding.
applyN :: forall a. Integer -> (a -> a) -> a -> a
applyN k f = go k
  where
    go :: Integer -> a -> a
    go i v = if i <= 0 then v else go (i - 1) (f v)
