{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : DevnetRevertSpec
Description : End-to-end documentation of voucher revert (US3 — #9).

== Reading this module as documentation

This test file exercises the shop-master revert path against a real
Cardano devnet. Each scenario bootstraps a full coalition, settles
one or two vouchers, then reverts — proving the shop master key can
roll back or fully remove a voucher entry.

Scenarios:

  1. Rollback — revert a two-settlement entry to the first
     settlement's @commit_spent@. One voucher UTxO remains.
  2. Full removal — revert the only settlement. No voucher UTxO
     remains at the script address for this @user_id@.
  3. Negative: revert signed by a non-shop key is rejected.

Each @it@ block gets a fresh devnet via @around withEnv@.
-}
module DevnetRevertSpec (spec) where

import Cardano.Crypto.DSIGN (
    deriveVerKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.Hash.Class (hashToBytes)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Scripts.Data (Datum (Datum))
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, datumTxOutL)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (AlonzoScript)
import Cardano.Ledger.Hashes (extractHash)
import Cardano.Ledger.Keys (
    KeyHash,
    KeyRole (..),
    VKey (..),
    hashKey,
 )
import Cardano.Ledger.Mary.Value (MaryValue)
import Cardano.Ledger.Plutus.Data (
    binaryDataToData,
    getPlutusData,
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Ledger.Val (inject)
import Cardano.Node.Client.E2E.Setup (
    Ed25519DSIGN,
    SignKeyDSIGN,
    addKeyWitness,
    deriveVerKeyDSIGN,
    genesisAddr,
    genesisSignKey,
    mkSignKey,
 )
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (
    SubmitResult (..),
    Submitter (..),
 )
import Cardano.Node.Client.TxBuild (
    BuildError (..),
    Convergence (..),
    InterpretIO (..),
    TxBuild,
    build,
    payTo,
    peek,
    requireSignature,
    spend,
 )
import Control.Concurrent (threadDelay)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Short as SBS
import Data.Char (isHexDigit)
import qualified Data.Map.Strict as Map
import DevnetEnv (DevnetEnv (..), withEnv)
import Fixtures (SpendBundle (..), fixturesDir, loadBundle)
import qualified Harvest.Script as Script
import Harvest.Transaction (revertVoucher)
import Harvest.Types (VoucherDatum (..))
import HarvestFlow (
    GovOp (..),
    HarvestFlow (..),
    bootstrapCoalition,
    bumpExUnits,
    submitGovernance,
 )
import Lens.Micro ((^.))
import PlutusTx.IsData.Class (fromData)
import SpendScenario (CoalitionEnv (..), identityMutations, submitSpend)
import SpendSetup (DeployedSpend (..), deploySpendState)
import Test.Hspec (
    Spec,
    around,
    describe,
    expectationFailure,
    it,
    runIO,
    shouldBe,
    shouldSatisfy,
 )

-- | Empty query type.
data NoQ a
    deriving ()

loadCoalitionAddr :: IO (SBS.ShortByteString, Addr)
loadCoalitionAddr = do
    raw <- BS.readFile (fixturesDir <> "/applied-coalition-metadata.hex")
    let sbs = decodeHex raw
    pure (sbs, Script.coalitionAddr Testnet sbs)

{- | Load the unified voucher script (spend/redeem/revert share the same
applied script and address).
-}
loadVoucherScript :: IO (AlonzoScript ConwayEra, Addr)
loadVoucherScript = do
    raw <- BS.readFile (fixturesDir <> "/applied-voucher-spend.hex")
    let sbs = decodeHex raw
        script = Script.loadScript sbs
        addr = Script.scriptAddr Testnet script
    pure (script, addr)

decodeHex :: BS.ByteString -> SBS.ShortByteString
decodeHex bs = case Base16.decode (BS8.filter isHexDigit bs) of
    Right decoded -> SBS.toShort decoded
    Left e -> error ("decodeHex: " <> e)

spec :: Spec
spec = describe "Devnet revert flow (US3 — #9)" $ do
    (coalitionBytes, coalitionAddr) <- runIO loadCoalitionAddr
    (voucherScript, _voucherAddr) <- runIO loadVoucherScript
    bundle <- runIO loadBundle

    around withEnv $ do
        -- == Rollback branch (T032, invariant #6) ==
        --
        -- The shop master reverts a settlement, rolling back
        -- commit_spent to the initial value. One voucher UTxO
        -- remains with the prior commitment.
        it "shop reverts settlement (rollback branch)" $ \env -> do
            coalEnv <- setupCoalition env coalitionBytes coalitionAddr

            -- Settle c1 to create the voucher entry
            deployed <- deploySpendState env bundle
            settleResult <-
                submitSpend env bundle deployed coalEnv identityMutations
            case settleResult of
                Rejected reason ->
                    expectationFailure
                        ("settlement rejected: " <> show reason)
                Submitted _txId -> pure ()

            -- Wait for the rotated voucher UTxO
            voucherUtxos <-
                waitForNewUtxo
                    (deProvider env)
                    (dsScriptAddr deployed)
                    (dsScriptTxIn deployed)
                    30
            (voucherIn, voucherOut) <- case voucherUtxos of
                (u : _) -> pure u
                [] -> error "no rotated voucher UTxO after settlement"

            -- Revert: roll back to the initial commit_spent
            let priorCommit = sbPublicInputs bundle !! 1
            revertResult <-
                submitRevert
                    env
                    voucherScript
                    _voucherAddr
                    coalEnv
                    voucherIn
                    voucherOut
                    priorCommit
                    (Just (dsScriptAddr deployed))
                    (deShopKey env)
            case revertResult of
                Rejected reason ->
                    expectationFailure
                        ("revert rejected: " <> show reason)
                Submitted _txId -> pure ()

            -- Assert: one voucher UTxO with rolled-back commit_spent
            reverted <-
                waitForNewUtxo
                    (deProvider env)
                    (dsScriptAddr deployed)
                    voucherIn
                    30
            case reverted of
                ((_, out) : _) ->
                    assertVoucherCommit out priorCommit
                [] ->
                    expectationFailure
                        "no voucher UTxO after rollback"

        -- == Full removal branch (T033, invariant #5) ==
        --
        -- The shop master reverts the only settlement, fully
        -- removing the entry. No voucher UTxO remains.
        it "shop fully removes voucher entry (full removal branch)" $ \env -> do
            coalEnv <- setupCoalition env coalitionBytes coalitionAddr

            -- Settle c1
            deployed <- deploySpendState env bundle
            settleResult <-
                submitSpend env bundle deployed coalEnv identityMutations
            case settleResult of
                Rejected reason ->
                    expectationFailure
                        ("settlement rejected: " <> show reason)
                Submitted _txId -> pure ()

            voucherUtxos <-
                waitForNewUtxo
                    (deProvider env)
                    (dsScriptAddr deployed)
                    (dsScriptTxIn deployed)
                    30
            (voucherIn, voucherOut) <- case voucherUtxos of
                (u : _) -> pure u
                [] -> error "no rotated voucher UTxO after settlement"

            -- Full removal: no output at script address
            let priorCommit = sbPublicInputs bundle !! 1
            revertResult <-
                submitRevert
                    env
                    voucherScript
                    _voucherAddr
                    coalEnv
                    voucherIn
                    voucherOut
                    priorCommit
                    Nothing
                    (deShopKey env)
            case revertResult of
                Rejected reason ->
                    expectationFailure
                        ("full removal rejected: " <> show reason)
                Submitted _txId -> pure ()

            -- Assert: no voucher UTxOs
            threadDelay 2_000_000
            remaining <- queryUTxOs (deProvider env) (dsScriptAddr deployed)
            remaining `shouldBe` []

        -- == Negative: non-shop key (T034, SC-005) ==
        --
        -- A revert signed by a key not matching datum.shop_pk
        -- is rejected by the validator's membership check.
        it "revert rejected when signed by non-shop key" $ \env -> do
            coalEnv <- setupCoalition env coalitionBytes coalitionAddr

            deployed <- deploySpendState env bundle
            settleResult <-
                submitSpend env bundle deployed coalEnv identityMutations
            case settleResult of
                Rejected reason ->
                    expectationFailure
                        ("settlement rejected: " <> show reason)
                Submitted _txId -> pure ()

            voucherUtxos <-
                waitForNewUtxo
                    (deProvider env)
                    (dsScriptAddr deployed)
                    (dsScriptTxIn deployed)
                    30
            (voucherIn, voucherOut) <- case voucherUtxos of
                (u : _) -> pure u
                [] -> error "no rotated voucher UTxO after settlement"

            -- Use a bogus key (not the shop master)
            let bogusKey = mkSignKey (BS8.pack (replicate 32 'Z'))
                priorCommit = sbPublicInputs bundle !! 1
            revertResult <-
                submitRevert
                    env
                    voucherScript
                    _voucherAddr
                    coalEnv
                    voucherIn
                    voucherOut
                    priorCommit
                    Nothing
                    bogusKey
            revertResult `shouldSatisfy` isRejected
  where
    setupCoalition ::
        DevnetEnv ->
        SBS.ShortByteString ->
        Addr ->
        IO CoalitionEnv
    setupCoalition env coalitionBytes' coalitionAddr' = do
        let shopPk =
                rawSerialiseVerKeyDSIGN
                    (Cardano.Crypto.DSIGN.deriveVerKeyDSIGN (deShopKey env))
            reificatorPk =
                rawSerialiseVerKeyDSIGN
                    (Cardano.Crypto.DSIGN.deriveVerKeyDSIGN (deReificatorKey env))
        flow0 <- bootstrapCoalition env coalitionAddr'
        flow1 <-
            submitGovernance
                env
                coalitionBytes'
                coalitionAddr'
                flow0
                (GovAddShop shopPk)
        flow2 <-
            submitGovernance
                env
                coalitionBytes'
                coalitionAddr'
                flow1
                (GovAddReificator reificatorPk)
        pure
            CoalitionEnv
                { ceCoalitionTxIn = hfCoalitionIn flow2
                , ceCoalitionTxOut = hfCoalitionOut flow2
                , ceReificatorKey = deReificatorKey env
                }

{- | Build and submit a revert tx. The shop master signs
@own_ref.transaction_id || "REVERT" || prior_bytes@ and submits.
-}
submitRevert ::
    DevnetEnv ->
    AlonzoScript ConwayEra ->
    Addr ->
    CoalitionEnv ->
    TxIn ->
    TxOut ConwayEra ->
    Integer ->
    -- | 'Nothing' for full removal, 'Just addr' for rollback
    Maybe Addr ->
    SignKeyDSIGN Ed25519DSIGN ->
    IO SubmitResult
submitRevert env voucherScript _voucherAddr coalEnv voucherIn voucherOut priorCommit mOutput shopKey_ = do
    (feeIn, feeOut, colIn, _colOut) <-
        fundShop env

    let TxIn (TxId txIdHash) _ = voucherIn
        txIdBytes = hashToBytes (extractHash txIdHash)
        -- prior_bytes: 32-byte big-endian zero-padded
        priorBytes = integerTo32BytesBE priorCommit
        message = txIdBytes <> "REVERT" <> priorBytes
        shopSig =
            rawSerialiseSigDSIGN
                (signDSIGN () message shopKey_)

        shopKeyHash :: KeyHash Guard
        shopKeyHash =
            hashKey
                (VKey (Cardano.Crypto.DSIGN.deriveVerKeyDSIGN shopKey_))

        -- Parse the existing voucher datum to get user_id, shop_pk, reificator_pk
        voucherDatum :: VoucherDatum
        voucherDatum = case voucherOut ^. datumTxOutL of
            Datum bd ->
                case fromData (getPlutusData (binaryDataToData bd)) of
                    Just vd -> vd
                    Nothing -> error "submitRevert: datum parse failed"
            _ -> error "submitRevert: no inline datum"

        lockedValue :: MaryValue
        lockedValue = inject (voucherOut ^. coinTxOutL)

        rollbackOutput = case mOutput of
            Nothing -> Nothing
            Just addr ->
                Just
                    ( addr
                    , lockedValue
                    , VoucherDatum
                        { vdUserId = vdUserId voucherDatum
                        , vdCommitSpent = priorCommit
                        , vdShopPk = vdShopPk voucherDatum
                        , vdReificatorPk = vdReificatorPk voucherDatum
                        }
                    )

        prog :: TxBuild NoQ () ()
        prog = do
            _ <-
                revertVoucher
                    voucherIn
                    colIn
                    (ceCoalitionTxIn coalEnv)
                    shopKeyHash
                    voucherScript
                    priorCommit
                    shopSig
                    rollbackOutput
            _ <- spend feeIn
            pure ()

        interpret :: InterpretIO NoQ
        interpret = InterpretIO (\case {})

        eval tx =
            fmap
                (Map.map (either (Left . show) (Right . bumpExUnits)))
                (evaluateTx (deProvider env) tx)

        -- Coalition UTxO is a reference input only — must NOT be in
        -- inputUtxos to avoid BabbageNonDisjointRefInputs.
        inputUtxos =
            [ (voucherIn, voucherOut)
            , (feeIn, feeOut)
            ]

    result <-
        build
            (dePParams env)
            interpret
            eval
            inputUtxos
            (deShopAddr env)
            prog
    case result of
        Left (EvalFailure _purpose msg) -> pure (Rejected (BS8.pack msg))
        Left err -> error ("submitRevert: build failed: " <> show err)
        Right tx -> do
            let signed = addKeyWitness shopKey_ tx
            submitTx (deSubmitter env) signed

{- | Encode an integer as 32-byte big-endian zero-padded ByteString.

Matches the on-chain @builtin.integer_to_bytearray(True, 32, n)@.
-}
integerTo32BytesBE :: Integer -> BS.ByteString
integerTo32BytesBE n
    | n < 0 = error "integerTo32BytesBE: negative"
    | n == 0 = BS.replicate 32 0
    | otherwise =
        let bytes = go n []
            padLen = 32 - length bytes
         in BS.pack (replicate padLen 0 ++ bytes)
  where
    go 0 acc = acc
    go x acc = go (x `div` 256) (fromIntegral (x `mod` 256) : acc)

-- | Fund the shop master with fee and collateral UTxOs from genesis.
fundShop ::
    DevnetEnv ->
    IO (TxIn, TxOut ConwayEra, TxIn, TxOut ConwayEra)
fundShop env = do
    utxos <- queryUTxOs (deProvider env) genesisAddr
    seed <- case utxos of
        (u : _) -> pure u
        [] -> error "fundShop: no genesis UTxOs"
    let (seedIn, _) = seed
        feePay = Coin 50_000_000
        collateralPay = Coin 10_000_000

        signerHash :: KeyHash Guard
        signerHash = hashKey (VKey (Cardano.Node.Client.E2E.Setup.deriveVerKeyDSIGN genesisSignKey))

        interpret :: InterpretIO NoQ
        interpret = InterpretIO (\case {})

        eval tx =
            fmap
                (Map.map (either (Left . show) Right))
                (evaluateTx (deProvider env) tx)

        prog :: TxBuild NoQ () ()
        prog = do
            _ <- spend seedIn
            _ <- payTo (deShopAddr env) (inject feePay :: MaryValue)
            _ <- payTo (deShopAddr env) (inject collateralPay :: MaryValue)
            requireSignature signerHash
            _ <- peek (const (Ok ()))
            pure ()

    result <-
        build
            (dePParams env)
            interpret
            eval
            [seed]
            genesisAddr
            prog
    case result of
        Left err -> error ("fundShop: build failed: " <> show err)
        Right tx -> do
            let signed = addKeyWitness genesisSignKey tx
            submitTx (deSubmitter env) signed >>= \case
                Rejected reason ->
                    error
                        ("fundShop: rejected: " <> show reason)
                Submitted _txId -> pure ()

    shopUtxos <- waitForUtxos (deProvider env) (deShopAddr env) 30
    (fIn, fOut) <- pickByValue "fee" feePay shopUtxos
    (cIn, cOut) <- pickByValue "collateral" collateralPay shopUtxos
    pure (fIn, fOut, cIn, cOut)
  where
    pickByValue ::
        String ->
        Coin ->
        [(TxIn, TxOut ConwayEra)] ->
        IO (TxIn, TxOut ConwayEra)
    pickByValue label expected us =
        case filter (\(_, o) -> o ^. coinTxOutL == expected) us of
            (u : _) -> pure u
            [] ->
                error
                    ("fundShop: no " <> label <> " UTxO with " <> show expected)

assertVoucherCommit :: TxOut ConwayEra -> Integer -> IO ()
assertVoucherCommit out expectedCommit =
    case out ^. datumTxOutL of
        Datum bd ->
            case fromData (getPlutusData (binaryDataToData bd)) of
                Just vd ->
                    vdCommitSpent vd `shouldBe` expectedCommit
                Nothing ->
                    error
                        "voucher output datum did not parse as VoucherDatum"
        _ ->
            error "voucher output has no inline datum"

waitForNewUtxo ::
    Provider IO ->
    Addr ->
    TxIn ->
    Int ->
    IO [(TxIn, TxOut ConwayEra)]
waitForNewUtxo provider addr oldIn attempts
    | attempts <= 0 =
        error ("waitForNewUtxo: timed out at " <> show addr)
    | otherwise = do
        utxos <- queryUTxOs provider addr
        let fresh = filter (\(i, _) -> i /= oldIn) utxos
        if null fresh
            then do
                threadDelay 1_000_000
                waitForNewUtxo provider addr oldIn (attempts - 1)
            else pure fresh

waitForUtxos ::
    Provider IO ->
    Addr ->
    Int ->
    IO [(TxIn, TxOut ConwayEra)]
waitForUtxos provider addr attempts
    | attempts <= 0 =
        error ("waitForUtxos: timed out at " <> show addr)
    | otherwise = do
        utxos <- queryUTxOs provider addr
        if null utxos
            then do
                threadDelay 1_000_000
                waitForUtxos provider addr (attempts - 1)
            else pure utxos

isRejected :: SubmitResult -> Bool
isRejected (Rejected _) = True
isRejected _ = False
