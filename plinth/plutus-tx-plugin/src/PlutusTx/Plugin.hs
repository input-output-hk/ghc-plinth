module PlutusTx.Plugin (plugin, plc, mkCompiledCode) where

import Data.ByteString qualified as BS
import PlutusTx.Code
import PlutusPrelude

import PlutusCore.Flat.Run (unflat)
-- import PlutusTx.Foldable (fold)

plugin :: a -> a
plugin x = x

plc :: a -> a
plc x = x

-- | Helper to avoid doing too much construction of Core ourselves
mkCompiledCode :: forall a. BS.ByteString -> BS.ByteString -> BS.ByteString -> CompiledCode a
mkCompiledCode plcBS pirBS ci = SerializedCode plcBS (Just pirBS) (fold . unflat $ ci)
