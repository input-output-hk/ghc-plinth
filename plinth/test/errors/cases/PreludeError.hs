{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: Prelude.error
-- (use PlutusTx.Prelude.error).
module PreludeError where

import PlutusTx

code :: CompiledCode Integer
code = $$(PlutusTx.compile [|| error "boom" ||])
