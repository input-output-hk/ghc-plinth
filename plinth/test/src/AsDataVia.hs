-- | Regression test for the @deriving AsData via Plinth@ syntax.
--
-- If the plugin's parsed-AST matcher fails to fire on the @Plinth@ sentinel,
-- this module fails to compile: the @AsData@ deriving clause survives to the
-- renamer, where @AsData@ is not a real class, and the pattern synonyms below
-- are never generated.
module AsDataVia (Shape (..), area) where

import PlutusTx.Prelude

-- | The plugin replaces this declaration with a @newtype@ over
-- @BuiltinData@ and generates bidirectional pattern synonyms @Circle@ and
-- @Rectangle@ (keeping the original constructor names) plus a @COMPLETE@
-- pragma covering them.
data Shape
  = Circle Integer
  | Rectangle Integer Integer
  deriving AsData via Plinth

-- | Uses the generated pattern synonyms. The @COMPLETE@ pragma the plugin
-- emits makes this @\case@ exhaustive.
area :: Shape -> Integer
area = \case
  Circle r      -> r * r * 3
  Rectangle w h -> w * h
