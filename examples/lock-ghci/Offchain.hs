{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}

-- | Helpers to use the lock validator from GHCi against a local
-- devnet: query funds, lock them at the script address, unlock them
-- with a redeemer.
module Offchain where

import Cardano.Api
import Cardano.Api.Network qualified as Net
import Cardano.Ledger.Compactible (fromCompact)

import Data.Function ((&))
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
import Data.Set qualified as Set
import Data.Text qualified as Text
import System.Directory (doesFileExist)

-- The devnet constants: Conway era, network magic 42.
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
-- project wrote.
lockScript :: IO (PlutusScript PlutusScriptV3)
lockScript = orDie =<< readFileTextEnvelope (File "lock.plutus")

-- | The script address: the hash of the script, as an address.
scriptAddress :: IO (Address ShelleyAddr)
scriptAddress = do
  script <- lockScript
  let scriptHash = hashScript (PlutusScript PlutusScriptV3 script)
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

-- | Lock an amount at the script address, with the secret number
-- stored as the inline datum.
lockFunds :: Coin -> Integer -> IO TxId
lockFunds amount secret = do
  scriptAddr <- shelleyAddressInEra sbe <$> scriptAddress
  (walletIn, _) : _ <- utxosAt =<< walletAddress
  let datum = unsafeHashableScriptData (ScriptDataNumber secret)
      lockedOutput =
        TxOut
          scriptAddr
          (lovelaceToTxOutValue sbe amount)
          (TxOutDatumInline BabbageEraOnwardsConway datum)
          ReferenceScriptNone
  submit [walletIn] $
    defaultTxBodyContent sbe
      & setTxIns [(walletIn, BuildTxWith (KeyWitness KeyWitnessForSpending))]
      & setTxOuts [lockedOutput]

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
        PlutusScriptWitness
          PlutusScriptV3InConway
          PlutusScriptV3
          (PScript script)
          InlineScriptDatum
          redeemer
          (ExecutionUnits 0 0)
  submit [scriptIn, collateralIn] $
    defaultTxBodyContent sbe
      & setTxIns
          [(scriptIn, BuildTxWith (ScriptWitness ScriptWitnessForSpending witness))]
      & setTxInsCollateral (TxInsCollateral AlonzoEraOnwardsConway [collateralIn])

-- Note [Balancing a transaction]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- constructBalancedTx computes the fee, adds the change output, runs
-- the Plutus scripts to measure their budget, and signs. It needs the
-- current chain state (protocol parameters, the resolved inputs, the
-- start of time to convert slots): queryStateForBalancedTx fetches
-- all of it in one connection. One trap: constructBalancedTx does not
-- put the protocol parameters in the transaction body itself, and
-- without them the node rejects the transaction with
-- "ScriptIntegrityHashMismatch", so we set them explicitly.

-- | Balance, sign and submit a transaction; return its id.
submit :: [TxIn] -> TxBodyContent BuildTx ConwayEra -> IO TxId
submit inputs content = do
  skey <- walletKey
  changeAddr <- shelleyAddressInEra sbe <$> walletAddress
  queried <-
    executeLocalStateQueryExpr conn Net.VolatileTip $
      queryStateForBalancedTx (toCardanoEra sbe) inputs []
  (utxo, pparams, eraHistory, systemStart, stakePools, stakeDeposits, drepDeposits, _) <-
    orDie =<< orDie queried
  tx <-
    orDieBalance $
      constructBalancedTx
        sbe
        (content & setTxProtocolParams (BuildTxWith (Just pparams)))
        changeAddr
        Nothing
        utxo
        pparams
        (toLedgerEpochInfo eraHistory)
        systemStart
        stakePools
        stakeDeposits
        (Map.map fromCompact drepDeposits)
        [WitnessPaymentKey skey]
  submitTxToNodeLocal conn (TxInMode sbe tx) >>= \case
    TxSubmitSuccess -> pure (getTxId (getTxBody tx))
    failure -> fail (show failure)

orDie :: Show e => Either e a -> IO a
orDie = either (fail . show) pure

-- Render a validator rejection by its trace messages, not by the
-- full Show dump of the balancing error.
orDieBalance :: Either (TxBodyErrorAutoBalance ConwayEra) a -> IO a
orDieBalance = \case
  Right a -> pure a
  Left (TxBodyScriptExecutionError [(_, ScriptErrorEvaluationFailed failure)]) ->
    fail ("the validator rejected the transaction: "
          <> show (dpfExecutionLogs failure))
  Left err -> fail (show err)
