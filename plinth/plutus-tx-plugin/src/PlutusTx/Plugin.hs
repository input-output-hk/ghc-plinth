module PlutusTx.Plugin (plugin, plc, mkCompiledCode) where

import PlutusTx.Plugin.Common (mkCompiledCode)

plugin :: a -> a
plugin x = x

plc :: a -> a
plc x = x
