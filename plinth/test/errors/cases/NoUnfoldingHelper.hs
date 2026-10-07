-- Helper for the NoUnfolding case: NOINLINE stops uplc-ghc from
-- exposing the unfolding of this function.
module NoUnfoldingHelper (opaque) where

opaque :: Integer -> Integer
opaque x = x + 1
{-# NOINLINE opaque #-}
