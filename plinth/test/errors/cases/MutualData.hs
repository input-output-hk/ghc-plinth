{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: mutually recursive data types.
module MutualData where

import PlutusTx
import qualified PlutusTx.Prelude as P

data Rose = Rose Forest
data Forest = Forest [Rose]

depth :: Rose -> Integer
depth (Rose (Forest [])) = 1
depth (Rose (Forest (r : _))) = 1 P.+ depth r
{-# INLINABLE depth #-}

code :: CompiledCode (Rose -> Integer)
code = $$(PlutusTx.compile [|| depth ||])
