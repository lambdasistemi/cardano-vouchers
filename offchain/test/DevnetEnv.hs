{-# LANGUAGE DataKinds #-}

{- |
Module      : DevnetEnv
Description : 'around'-bracket that spins up a devnet and yields the
              handles the devnet spend scenarios need.

Centralises the boilerplate so 'DevnetSpendSpec' can stay focused on
the E2E narrative and not on cardano-node-clients plumbing.
-}
module DevnetEnv (
    DevnetEnv (..),
    withEnv,
) where

-- The ledger packages (cardano-ledger-core / -api / -conway) are
-- the expected low-level seam: harvest's library and the
-- cardano-node-clients:devnet sub-library both import from them
-- directly. The invariant harvest preserves is NOT using
-- cardano-api — the higher-level wrapper — and this test file
-- honours it (no cardano-api imports; confirmed empty grep).
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.E2E.Setup (
    Ed25519DSIGN,
    SignKeyDSIGN,
    addKeyWitness,
    enterpriseAddr,
    genesisAddr,
    genesisSignKey,
    keyHashFromSignKey,
    mkSignKey,
    withDevnet,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (Submitter (..))
import qualified Data.ByteString.Char8 as BS8

{- | Everything a single spend-scenario needs: a running node it can
query and submit to, the protocol parameters for balancing, the
genesis seed UTxO, and the coalition actor key pairs.

The @#15@ single-spend flow only uses @deReificator*@ — those fields
keep their original names. @#9@ adds the issuer, shop, and shop-master
keys on top: four pairwise-distinct Ed25519 keys generated from
disjoint 32-byte seeds.
-}
data DevnetEnv = DevnetEnv
    { dePParams :: PParams ConwayEra
    , deProvider :: Provider IO
    , deSubmitter :: Submitter IO
    , deGenesisUtxos :: [(TxIn, TxOut ConwayEra)]
    , deReificatorKey :: SignKeyDSIGN Ed25519DSIGN
    , deReificatorAddr :: Addr
    , deIssuerKey :: SignKeyDSIGN Ed25519DSIGN
    , deIssuerAddr :: Addr
    , deShopKey :: SignKeyDSIGN Ed25519DSIGN
    , deShopAddr :: Addr
    , deShopMasterKey :: SignKeyDSIGN Ed25519DSIGN
    , deShopMasterAddr :: Addr
    }

-- | hspec 'around'-compatible bracket.
withEnv :: (DevnetEnv -> IO ()) -> IO ()
withEnv action =
    withDevnet $ \lsq ltxs -> do
        let provider = mkN2CProvider lsq
            submitter = mkN2CSubmitter ltxs
            mkActor seed =
                let k = mkSignKey (BS8.pack (replicate 32 seed))
                 in (k, enterpriseAddr (keyHashFromSignKey k))
            (reificatorKey, reificatorAddr) = mkActor 'R'
            (issuerKey, issuerAddr) = mkActor 'I'
            (shopKey, shopAddr) = mkActor 'S'
            (shopMasterKey, shopMasterAddr) = mkActor 'M'
        pp <- queryProtocolParams provider
        utxos <- queryUTxOs provider genesisAddr
        action
            DevnetEnv
                { dePParams = pp
                , deProvider = provider
                , deSubmitter = submitter
                , deGenesisUtxos = utxos
                , deReificatorKey = reificatorKey
                , deReificatorAddr = reificatorAddr
                , deIssuerKey = issuerKey
                , deIssuerAddr = issuerAddr
                , deShopKey = shopKey
                , deShopAddr = shopAddr
                , deShopMasterKey = shopMasterKey
                , deShopMasterAddr = shopMasterAddr
                }

-- Keep tooling imports reachable even though this module only
-- constructs the env. Helpers for submitting txs live in their own
-- module next to the DSL program.
_unused :: ()
_unused = seq addKeyWitness () `seq` seq genesisSignKey ()
