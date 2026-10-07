{-# LANGUAGE TemplateHaskell #-}
-- Error deep inside nested functions: the error must point
-- at the offending code inside 'inner', with context frames for the
-- chain of definitions, not only at the splice.
module DeepChain where

import NoUnfoldingHelper (opaque)
import PlutusTx
import qualified PlutusTx.Prelude as P

inner :: Integer -> Integer
inner i = opaque i

outer :: Integer -> Integer
outer i = inner (i P.+ 1)

code :: CompiledCode (Integer -> Integer)
code = $$(PlutusTx.compile [|| outer ||])
