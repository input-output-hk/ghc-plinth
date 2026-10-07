module Utils where

import PlutusTx.Prelude qualified as PlutusTx

-- No INLINABLE pragma: uplc-ghc does not need it.
plusInteger :: Integer -> Integer -> Integer
plusInteger x y = x PlutusTx.+ y
