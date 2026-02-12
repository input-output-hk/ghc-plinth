module Utils where

import PlutusTx.Prelude qualified as PlutusTx

-- not inlineable, to test that we don't need that anymore?
plusInteger :: Integer -> Integer -> Integer
plusInteger x y = x PlutusTx.+ y
