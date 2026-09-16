{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: String literal at type [Char]
-- (without OverloadedStrings).
module LitString where

import PlutusTx

code :: CompiledCode [Char]
code = $$(PlutusTx.compile [|| "hello" ||])
