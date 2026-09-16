{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: Char literal.
module LitChar where

import PlutusTx

code :: CompiledCode Char
code = $$(PlutusTx.compile [|| 'x' ||])
