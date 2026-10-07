{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: reference to a function with no
-- unfolding (hidden by a NOINLINE pragma).
module NoUnfolding where

import NoUnfoldingHelper (opaque)
import PlutusTx

code :: CompiledCode Integer
code = $$(PlutusTx.compile [|| opaque 42 ||])
