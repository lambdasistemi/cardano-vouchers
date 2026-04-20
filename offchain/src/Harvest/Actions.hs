{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{- |
Module      : Harvest.Actions
Description : Pure state-machine twin of the Aiken validators.

Lean ↔ Haskell twin per
`specs/003-devnet-full-flow/contracts/actions.md`. The Lean side
(`lean/Harvest/Actions.lean`) owns the invariants; this module mirrors
the signatures and guard semantics shape-for-shape.

T008 — state types only (@HarvestState@, @VoucherEntry@, @Reject@,
@Step@, @ProofEvidence@). Transitions are filled in by T013 / T014.
-}
module Harvest.Actions (
    -- * Opaque identifiers
    PubKey (..),
    UserId (..),
    Commit (..),
    Sig (..),
    ProofEvidence (..),

    -- * State
    HarvestState (..),
    VoucherEntry (..),

    -- * Result
    Reject (..),
    Step,
) where

import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Set (Set)

-- | Opaque Ed25519 public key.
newtype PubKey = PubKey {unPubKey :: ByteString}
    deriving newtype (Eq, Ord, Show)

-- | Opaque customer identifier (the Poseidon hash of @user_secret@).
newtype UserId = UserId {unUserId :: Integer}
    deriving newtype (Eq, Ord, Show)

-- | Opaque Poseidon commitment. Internal structure is not needed at
-- this abstraction level.
newtype Commit = Commit {unCommit :: Integer}
    deriving newtype (Eq, Ord, Show)

-- | Opaque Ed25519 signature.
newtype Sig = Sig {unSig :: ByteString}
    deriving newtype (Eq, Ord, Show)

-- | Opaque bundle of customer-side proof material (Groth16 proof +
-- Ed25519 signature over @signed_data@). The pure model treats it as
-- a black box; its validity is an abstract predicate resolved by the
-- real validator.
newtype ProofEvidence = ProofEvidence {unProofEvidence :: ByteString}
    deriving newtype (Eq, Ord, Show)

-- | Per-customer voucher entry in the off-chain state mirror.
data VoucherEntry = VoucherEntry
    { veCommitSpent :: Commit
    , veShop :: PubKey
    , veReificator :: PubKey
    }
    deriving stock (Eq, Show)

-- | Off-chain mirror of the coalition + per-customer registry.
data HarvestState = HarvestState
    { hsShops :: Set PubKey
    , hsReificators :: Set PubKey
    , hsIssuer :: PubKey
    , hsEntries :: Map UserId VoucherEntry
    }
    deriving stock (Eq, Show)

-- | Transition rejection reasons — one constructor per validator
-- failure mode.
data Reject
    = ShopAlreadyRegistered
    | ShopNotRegistered
    | ReificatorAlreadyRegistered
    | ReificatorNotRegistered
    | IssuerSigInvalid
    | CustomerSigInvalid
    | CustomerProofInvalid
    | BindingMismatch
    | NoEntryToRedeem
    | NoEntryToRevert
    | WrongShopForRevert
    | WrongReificatorForRedeem
    deriving stock (Eq, Show)

-- | Transition result: either a rejection or a new state.
type Step = Either Reject HarvestState
