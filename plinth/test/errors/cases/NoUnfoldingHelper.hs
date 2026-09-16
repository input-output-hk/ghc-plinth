-- Helper for the NoUnfolding case: a function without an
-- INLINABLE pragma and with an unfolding hidden by NOINLINE.
module NoUnfoldingHelper (opaque) where

opaque :: Integer -> Integer
opaque x = x + 1
{-# NOINLINE opaque #-}
