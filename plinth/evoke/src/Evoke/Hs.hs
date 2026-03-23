module Evoke.Hs
  ( app,
    bindStmt,
    doExpr,
    explicitList,
    explicitTuple,
    fieldOcc,
    funBind,
    grhs,
    grhss,
    importDecls,
    lam,
    lastStmt,
    lit,
    match,
    mg,
    opApp,
    par,
    qual,
    qualTyVar,
    qualVar,
    recField,
    recFields,
    recordCon,
    string,
    tupArg,
    tyVar,
    unqual,
    var,
    varPat,
  )
where

import qualified GHC.Hs as Ghc
import qualified GHC.Plugins as Ghc
import qualified GHC.Types.SourceText as Ghc

app ::
  Ghc.SrcSpan ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs
app s f x = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.HsApp Ghc.noAnn f x

bindStmt ::
  Ghc.SrcSpan ->
  Ghc.LPat Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LStmt Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
bindStmt s p e =
  Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.BindStmt Ghc.noAnn p e

doExpr :: Ghc.SrcSpan -> [Ghc.ExprLStmt Ghc.GhcPs] -> Ghc.LHsExpr Ghc.GhcPs
doExpr s stmts =
  Ghc.L (Ghc.noAnnSrcSpan s) $
    Ghc.HsDo Ghc.noAnn (Ghc.DoExpr Nothing) (Ghc.L (Ghc.noAnnSrcSpan s) stmts)

explicitList ::
  Ghc.SrcSpan -> [Ghc.LHsExpr Ghc.GhcPs] -> Ghc.LHsExpr Ghc.GhcPs
explicitList s xs = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.ExplicitList Ghc.noAnn xs

explicitTuple ::
  Ghc.SrcSpan -> [Ghc.HsTupArg Ghc.GhcPs] -> Ghc.LHsExpr Ghc.GhcPs
explicitTuple s xs = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.ExplicitTuple Ghc.noAnn xs Ghc.Boxed

fieldOcc :: Ghc.SrcSpan -> Ghc.RdrName -> Ghc.LFieldOcc Ghc.GhcPs
fieldOcc s r = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.FieldOcc
  { Ghc.foExt = Ghc.noExtField
  , Ghc.foLabel = Ghc.L (Ghc.noAnnSrcSpan s) r
  }

funBind ::
  Ghc.SrcSpan ->
  Ghc.OccName ->
  Ghc.MatchGroup Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs) ->
  Ghc.LHsBind Ghc.GhcPs
funBind s f g =
  Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.FunBind Ghc.noExtField (unqual s f) g

grhs ::
  Ghc.SrcSpan ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LGRHS Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
grhs s e = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.GRHS Ghc.noAnn [] e

grhss ::
  Ghc.SrcSpan ->
  [Ghc.LGRHS Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)] ->
  Ghc.GRHSs Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
grhss _ xs =
  Ghc.GRHSs Ghc.emptyComments xs $ Ghc.EmptyLocalBinds Ghc.noExtField

importDecl ::
  Ghc.SrcSpan ->
  Ghc.ModuleName ->
  Ghc.ModuleName ->
  Ghc.LImportDecl Ghc.GhcPs
importDecl s m n =
  Ghc.L (Ghc.noAnnSrcSpan s) $
    Ghc.ImportDecl
      { Ghc.ideclExt = Ghc.XImportDeclPass
          { Ghc.ideclAnn = Ghc.noAnn
          , Ghc.ideclSourceText = Ghc.NoSourceText
          , Ghc.ideclImplicit = False
          }
      , Ghc.ideclName = Ghc.L (Ghc.noAnnSrcSpan s) m
      , Ghc.ideclPkgQual = Ghc.NoRawPkgQual
      , Ghc.ideclSource = Ghc.NotBoot
      , Ghc.ideclSafe = False
      , Ghc.ideclQualified = Ghc.QualifiedPre
      , Ghc.ideclAs = Just $ Ghc.L (Ghc.noAnnSrcSpan s) n
      , Ghc.ideclImportList = Nothing
      }

importDecls ::
  Ghc.SrcSpan ->
  [(Ghc.ModuleName, Ghc.ModuleName)] ->
  [Ghc.LImportDecl Ghc.GhcPs]
importDecls = fmap . uncurry . importDecl

lam ::
  Ghc.SrcSpan ->
  Ghc.MatchGroup Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs) ->
  Ghc.LHsExpr Ghc.GhcPs
lam s mg_ = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.HsLam Ghc.noExtField mg_

lastStmt ::
  Ghc.SrcSpan ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LStmt Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
lastStmt s e = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.LastStmt Ghc.noExtField e Nothing noSyntaxExpr

lit :: Ghc.SrcSpan -> Ghc.HsLit Ghc.GhcPs -> Ghc.LHsExpr Ghc.GhcPs
lit s l = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.HsLit Ghc.noAnn l

noSyntaxExpr :: Ghc.SyntaxExpr Ghc.GhcPs
noSyntaxExpr = Ghc.noSyntaxExpr

match ::
  Ghc.SrcSpan ->
  Ghc.HsMatchContext Ghc.GhcPs ->
  [Ghc.LPat Ghc.GhcPs] ->
  Ghc.GRHSs Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs) ->
  Ghc.LMatch Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
match s c ps g =
  Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.Match Ghc.noAnn c ps g

mg ::
  Ghc.Located [Ghc.LMatch Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)] ->
  Ghc.MatchGroup Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
mg ms = Ghc.MG Ghc.Generated (Ghc.reLocA ms)

opApp ::
  Ghc.SrcSpan ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs
opApp s l o r = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.OpApp Ghc.noAnn l o r

par :: Ghc.SrcSpan -> Ghc.LHsExpr Ghc.GhcPs -> Ghc.LHsExpr Ghc.GhcPs
par s e = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.HsPar Ghc.noAnn Ghc.noHsTok e Ghc.noHsTok

qual :: Ghc.SrcSpan -> Ghc.ModuleName -> Ghc.OccName -> Ghc.LIdP Ghc.GhcPs
qual s m n = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.mkRdrQual m n

qualTyVar ::
  Ghc.SrcSpan -> Ghc.ModuleName -> Ghc.OccName -> Ghc.LHsType Ghc.GhcPs
qualTyVar s m = tyVar s . qual s m

qualVar ::
  Ghc.SrcSpan -> Ghc.ModuleName -> Ghc.OccName -> Ghc.LHsExpr Ghc.GhcPs
qualVar s m = var s . qual s m

recFields ::
  [Ghc.LHsRecField Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)] ->
  Ghc.HsRecFields Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
recFields fs = Ghc.HsRecFields fs Nothing

recField ::
  Ghc.SrcSpan ->
  Ghc.LFieldOcc Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsRecField Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
recField s f e = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.HsFieldBind Ghc.noAnn f e False

recordCon ::
  Ghc.SrcSpan ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.HsRecordBinds Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs
recordCon s c fs = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.RecordCon Ghc.noAnn c fs

string :: String -> Ghc.HsLit Ghc.GhcPs
string = Ghc.HsString Ghc.NoSourceText . Ghc.mkFastString

tupArg :: Ghc.LHsExpr Ghc.GhcPs -> Ghc.HsTupArg Ghc.GhcPs
tupArg = Ghc.Present Ghc.noAnn

tyVar :: Ghc.SrcSpan -> Ghc.LIdP Ghc.GhcPs -> Ghc.LHsType Ghc.GhcPs
tyVar s x = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.HsTyVar Ghc.noAnn Ghc.NotPromoted x

unqual :: Ghc.SrcSpan -> Ghc.OccName -> Ghc.LIdP Ghc.GhcPs
unqual s n = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.mkRdrUnqual n

var :: Ghc.SrcSpan -> Ghc.LIdP Ghc.GhcPs -> Ghc.LHsExpr Ghc.GhcPs
var s x = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.HsVar Ghc.noExtField x

varPat :: Ghc.SrcSpan -> Ghc.LIdP Ghc.GhcPs -> Ghc.LPat Ghc.GhcPs
varPat s x = Ghc.L (Ghc.noAnnSrcSpan s) $ Ghc.VarPat Ghc.noExtField x
