{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}

-- | Helpers to use the lock validator from GHCi against a local
-- devnet, built on the experimental cardano-api interface
-- (Cardano.Api.Experimental).
module Offchain where

import Cardano.Api
import Cardano.Api.Experimental qualified as Exp
import Cardano.Api.Experimental.AnyScriptWitness
  (AnyPlutusScriptWitness (AnyPlutusSpendingScriptWitness),
   PlutusSpendingScriptWitness (PlutusSpendingScriptWitnessV3))
import Cardano.Api.Experimental.Plutus qualified as EP
import Cardano.Api.Experimental.Tx qualified as Exp
import Cardano.Api.Ledger qualified as L
import Cardano.Api.Network qualified as Net
import Cardano.Ledger.Babbage.TxBody qualified as L
import Cardano.Ledger.Plutus.Data qualified as L
import Cardano.Ledger.Plutus.Language qualified as Plutus

import Data.Function ((&))
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
import Data.Set qualified as Set
import Data.Text qualified as Text
import System.Directory (doesFileExist)

-- The devnet constants: Conway era, network magic 42. The
-- experimental interface has its own era witness type.
era :: Exp.Era Exp.ConwayEra
era = Exp.ConwayEra

sbe :: ShelleyBasedEra ConwayEra
sbe = ShelleyBasedEraConway

network :: NetworkId
network = Testnet (NetworkMagic 42)

-- | Connection to the devnet node through the local socket.
conn :: LocalNodeConnectInfo
conn =
  LocalNodeConnectInfo
    { localConsensusModeParams = CardanoModeParams (EpochSlots 21600)
    , localNodeNetworkId = network
    , localNodeSocketPath = File "node.sock"
    }

-- | Load the wallet key, generating and saving it on first use.
walletKey :: IO (SigningKey PaymentKey)
walletKey = do
  let path = "user.skey"
  exists <- doesFileExist path
  if exists
    then orDie =<< readFileTextEnvelope (File path)
    else do
      skey <- generateSigningKey AsPaymentKey
      _ <- orDie =<< writeFileTextEnvelope (File path) Nothing skey
      pure skey

-- | The wallet address (fund it with topup).
walletAddress :: IO (Address ShelleyAddr)
walletAddress = do
  skey <- walletKey
  let vkeyHash = verificationKeyHash (getVerificationKey skey)
  pure (makeShelleyAddress network (PaymentCredentialByKey vkeyHash) NoStakeAddress)

-- | The compiled validator, read from the envelope the on-chain
-- project wrote, as the experimental script type.
lockScript :: IO (EP.PlutusScriptInEra Plutus.PlutusV3 (Exp.LedgerEra Exp.ConwayEra))
lockScript = do
  envelope <- orDie =<< readTextEnvelopeFromFile "lock.plutus"
  orDie (EP.deserialisePlutusScriptInEra Plutus.SPlutusV3 (textEnvelopeRawCBOR envelope))

-- | The script address: the hash of the script, as an address.
scriptAddress :: IO (Address ShelleyAddr)
scriptAddress = do
  script <- lockScript
  let scriptHash = fromShelleyScriptHash (EP.hashPlutusScriptInEra script)
  pure (makeShelleyAddress network (PaymentCredentialByScript scriptHash) NoStakeAddress)

-- | An address in its text form (to paste in a topup command).
bech32 :: Address ShelleyAddr -> String
bech32 = Text.unpack . serialiseAddress

-- | The unspent outputs at an address, largest first.
utxosAt :: Address ShelleyAddr -> IO [(TxIn, TxOut CtxUTxO ConwayEra)]
utxosAt addr = do
  let query = queryUtxo sbe (QueryUTxOByAddress (Set.singleton (toAddressAny addr)))
  result <- executeLocalStateQueryExpr conn Net.VolatileTip query
  UTxO utxo <- orDie =<< orDie =<< orDie result
  pure
    $ sortOn (\(_, TxOut _ v _ _) -> Down (txOutValueToLovelace v))
    $ Map.toList utxo

-- | Print the unspent outputs at an address, one per line.
showUtxos :: Address ShelleyAddr -> IO ()
showUtxos addr = do
  utxos <- utxosAt addr
  mapM_ render utxos
  where
    render (TxIn txid (TxIx ix), TxOut _ value datum _) =
      putStrLn $
        Text.unpack (serialiseToRawBytesHexText txid)
          <> "#" <> show ix
          <> ": " <> show (unCoin (txOutValueToLovelace value)) <> " lovelace"
          <> case datum of
               TxOutDatumInline _ d -> ", datum " <> show (getScriptData d)
               _ -> ""

-- The transaction body type of the experimental interface uses ledger
-- types directly: a ledger address, a ledger value, a ledger datum.
type LedgerConway = Exp.LedgerEra Exp.ConwayEra

ledgerAddress :: Address ShelleyAddr -> L.Addr
ledgerAddress addr = toShelleyAddr (shelleyAddressInEra sbe addr)

ledgerDatum :: HashableScriptData -> L.Datum LedgerConway
ledgerDatum d = L.Datum (L.dataToBinaryData (L.Data (toPlutusData (getScriptData d))))

-- | Lock an amount at the script address, with the secret number
-- stored as the inline datum.
lockFunds :: Coin -> Integer -> IO TxId
lockFunds amount secret = do
  scriptAddr <- scriptAddress
  (walletIn, _) : _ <- utxosAt =<< walletAddress
  let datum = unsafeHashableScriptData (ScriptDataNumber secret)
      lockedOutput =
        Exp.TxOut $
          L.BabbageTxOut
            (ledgerAddress scriptAddr)
            (L.MaryValue amount mempty)
            (ledgerDatum datum)
            L.SNothing
  submit [walletIn] $
    Exp.defaultTxBodyContent
      & Exp.setTxIns [(walletIn, Exp.AnyKeyWitnessPlaceholder)]
      & Exp.setTxOuts [lockedOutput]

-- | Spend the output at the script address, giving a guess as the
-- redeemer. The transaction validates only if the guess equals the
-- stored secret.
unlockFunds :: Integer -> IO TxId
unlockFunds guess = do
  script <- lockScript
  (scriptIn, _) : _ <- utxosAt =<< scriptAddress
  (collateralIn, _) : _ <- utxosAt =<< walletAddress
  let redeemer = unsafeHashableScriptData (ScriptDataNumber guess)
      witness =
        Exp.AnyPlutusScriptWitness $
          AnyPlutusSpendingScriptWitness $
            PlutusSpendingScriptWitnessV3 $
              Exp.PlutusScriptWitness
                Plutus.SPlutusV3
                (EP.PScript script)
                Exp.InlineDatum
                redeemer
                (ExecutionUnits 0 0)
  submit [scriptIn, collateralIn] $
    Exp.defaultTxBodyContent
      & Exp.setTxIns [(scriptIn, witness)]
      & Exp.setTxInsCollateral [collateralIn]

-- Note [Balancing with the experimental interface]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- There is no single balancing function. The steps are explicit:
--
-- 1. makeUnsignedTx turns the body content into a transaction. The
--    protocol parameters must be in the content (the script integrity
--    hash is computed from them).
-- 2. calcMinFeeRecursive computes the fee and appends the change
--    output. We run it once on a draft with zero execution units,
--    only to give the transaction its final shape.
-- 3. evaluateTransaction runs the Plutus scripts against the current
--    chain state and measures their execution units. It takes a
--    signed transaction, so we sign the draft. Measuring on the
--    SHAPED transaction matters: the validator receives the whole
--    transaction as its ScriptContext, so a change output appended
--    after the measurement would make the real cost higher than the
--    measured one, and the chain would reject the transaction.
-- 4. substituteExecutionUnits writes the measured units into the
--    content; makeUnsignedTx and calcMinFeeRecursive rebuild and
--    rebalance with them.
-- 5. Sign and submit. The experimental transaction converts to the
--    submission type with the ShelleyTx constructor.

-- | Balance, sign and submit a transaction; return its id.
submit :: [TxIn] -> Exp.TxBodyContent LedgerConway -> IO TxId
submit inputs content = do
  skey <- walletKey
  changeAddr <- walletAddress
  queried <-
    executeLocalStateQueryExpr conn Net.VolatileTip $
      queryStateForBalancedTx (toCardanoEra sbe) inputs []
  (utxo, lpp, eraHistory, systemStart, _, _, _, _) <-
    orDie =<< orDie queried
  let pparams = unLedgerProtocolParameters lpp
      ledgerUtxo = toLedgerUTxO sbe utxo
      contentWithParams = content & Exp.setTxProtocolParams pparams
      balance unsigned =
        Exp.calcMinFeeRecursive
          (ledgerAddress changeAddr)
          unsigned
          ledgerUtxo
          pparams
          mempty
          mempty
          mempty
          0

  -- Balance a zero-units draft to give the transaction its final
  -- shape, then sign it and run the scripts to measure their budget.
  draft <- orDie . balance =<< orDie (Exp.makeUnsignedTx era contentWithParams)
  let evaluation =
        Exp.evaluateTransaction
          systemStart
          (toLedgerEpochInfo eraHistory)
          pparams
          mempty
          mempty
          mempty
          ledgerUtxo
          (signedLedgerTx skey draft)
  exUnits <- traverse budgetOrDie (Exp.txEvalExecutionUnits evaluation)

  -- Rebuild with the measured budget, rebalance, sign.
  measured <- orDie (Exp.substituteExecutionUnits exUnits contentWithParams)
  balanced <- orDie . balance =<< orDie (Exp.makeUnsignedTx era measured)
  let tx = ShelleyTx sbe (signedLedgerTx skey balanced)
  submitTxToNodeLocal conn (TxInMode sbe tx) >>= \case
    TxSubmitSuccess -> pure (getTxId (getTxBody tx))
    failure -> fail (show failure)

-- | Sign with the wallet key, as a ledger-level transaction.
signedLedgerTx
  :: SigningKey PaymentKey
  -> Exp.UnsignedTx LedgerConway
  -> L.Tx L.TopTx LedgerConway
signedLedgerTx skey unsigned =
  let wit = Exp.makeKeyWitness era unsigned (WitnessPaymentKey skey)
      Exp.SignedTx tx = Exp.signTx era [] [wit] unsigned
   in tx

orDie :: Show e => Either e a -> IO a
orDie = either (fail . show) pure

-- Render a validator rejection by its trace messages, not by the
-- full Show dump of the evaluation error.
budgetOrDie
  :: Either ScriptExecutionError ([Text.Text], ExecutionUnits)
  -> IO ExecutionUnits
budgetOrDie = \case
  Right (_, units) -> pure units
  Left (ScriptErrorEvaluationFailed failure) ->
    fail ("the validator rejected the transaction: "
          <> show (dpfExecutionLogs failure))
  Left err -> fail (show err)
