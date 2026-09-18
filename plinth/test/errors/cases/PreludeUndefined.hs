{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: Prelude.undefined
-- (use PlutusTx.Prelude.error).
module PreludeUndefined where

import PlutusTx

code :: CompiledCode Integer
code = $$(PlutusTx.compile [|| undefined ||])
