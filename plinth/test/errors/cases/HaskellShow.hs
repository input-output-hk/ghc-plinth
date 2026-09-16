{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: show from the Haskell Show class
-- (use PlutusTx.Show).
module HaskellShow where

import PlutusTx

code :: CompiledCode (Integer -> [Char])
code = $$(PlutusTx.compile [|| \x -> show (x :: Integer) ||])
