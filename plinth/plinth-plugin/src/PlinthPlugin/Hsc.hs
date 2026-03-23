{-# LANGUAGE CPP #-}

module PlinthPlugin.Hsc
  ( addWarning,
    throwError,
  )
where

import qualified Control.Monad.IO.Class as IO
import qualified GHC as Ghc
import qualified GHC.Data.Bag as Ghc
import qualified GHC.Driver.Config.Diagnostic as Ghc
import qualified GHC.Driver.Errors as Ghc
import qualified GHC.Driver.Errors.Types as Ghc
import qualified GHC.Plugins as Ghc
import qualified GHC.Types.Error as Ghc
import qualified GHC.Utils.Error as Ghc
import qualified GHC.Utils.Logger as Ghc

-- | Adds a warning
addWarning :: Ghc.SrcSpan -> Ghc.SDoc -> Ghc.Hsc ()
addWarning srcSpan msgDoc = do
  logger <- Ghc.getLogger
  IO.liftIO $ Ghc.logMsg 
    logger 
    Ghc.MCOutput 
    srcSpan 
    msgDoc

-- | Throws an error
throwError :: Ghc.SrcSpan -> Ghc.SDoc -> Ghc.Hsc a
throwError srcSpan msgDoc = do
  dynFlags <- Ghc.getDynFlags
  let diagOpts = Ghc.initDiagOpts dynFlags
      -- 1. Create the plain diagnostic
      innerDiag = Ghc.mkPlainDiagnostic Ghc.WarningWithoutFlag [] msgDoc
      
      -- 2. Use the 'GhcUnknownMessage' wrapper with a 'Simple' constructor
      -- This bypasses the need for phase-specific types like DsMessage.
#if __GLASGOW_HASKELL__ >= 910
      diagnostic = Ghc.GhcUnknownMessage (Ghc.UnknownDiagnostic (const Ghc.NoDiagnosticOpts) innerDiag)
#else
      diagnostic = Ghc.GhcUnknownMessage (Ghc.UnknownDiagnostic innerDiag)
#endif
      
      -- 3. Create the envelope
      msg = Ghc.mkPlainMsgEnvelope diagOpts srcSpan diagnostic
          
  Ghc.throwErrors $ Ghc.mkMessages (Ghc.unitBag msg)
