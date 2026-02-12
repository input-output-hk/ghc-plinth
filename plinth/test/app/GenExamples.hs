module Main where

import Prettyprinter (layoutPretty, defaultLayoutOptions)
import Prettyprinter.Render.Text (renderStrict)
import Data.Text (unpack)
import System.FilePath ((</>), (<.>))
import System.Directory (createDirectoryIfMissing)
import qualified PlutusTx.Code as Code
import PlutusCore.Pretty (prettyPlcReadableSimple)

import qualified Examples

prettyScript :: Code.CompiledCode a -> String
prettyScript = unpack .
               renderStrict .
               layoutPretty defaultLayoutOptions .
               prettyPlcReadableSimple .
               Code.getPlcNoAnn

writeScript :: FilePath -> Code.CompiledCode a -> IO ()
writeScript file script = do
  createDirectoryIfMissing True outDir
  writeFile (outDir </> file <.> "uplc") (prettyScript script)

outDir :: FilePath
outDir = "examples-output"

main :: IO ()
main = do
  writeScript "succ"    Examples.succScript
  writeScript "eqCheck" Examples.eqCheckScript


