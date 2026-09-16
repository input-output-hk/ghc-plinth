{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: (<) from the Haskell Ord class
-- (use PlutusTx.Ord).
module HaskellOrd where

import PlutusTx

code :: CompiledCode (Integer -> Bool)
code = $$(PlutusTx.compile [|| \x -> x < (42 :: Integer) ||])
