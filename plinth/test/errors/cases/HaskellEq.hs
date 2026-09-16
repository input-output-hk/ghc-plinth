{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: (==) from the Haskell Eq class
-- (use PlutusTx.Eq).
module HaskellEq where

import PlutusTx

code :: CompiledCode (Integer -> Bool)
code = $$(PlutusTx.compile [|| \x -> x == (42 :: Integer) ||])
