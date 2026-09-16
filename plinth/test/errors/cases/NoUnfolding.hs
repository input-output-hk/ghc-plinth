{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: reference to a function with no
-- unfolding (missing INLINABLE pragma).
module NoUnfolding where

import NoUnfoldingHelper (opaque)
import PlutusTx

code :: CompiledCode Integer
code = $$(PlutusTx.compile [|| opaque 42 ||])
