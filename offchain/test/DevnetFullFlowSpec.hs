{- |
Module      : DevnetFullFlowSpec
Description : End-to-end documentation of the #9 full protocol flow.

== Reading this module as documentation

This test file is the executable narrative of the full harvest
protocol flow against a real Cardano devnet:

  1. Coalition bootstrap on an empty devnet.
  2. Shop + reificator onboarding via governance txs.
  3. First settlement — non-membership branch of the voucher
     validator (customer has no prior entry).
  4. Second settlement — membership branch (customer's prior entry
     is reused, @commit_spent@ rotates).

Follows the @DevnetSpendSpec@ layout from #15 — own @withDevnet@
bracket, one actor per 'it' block, no matching on error text.

Per @specs/003-devnet-full-flow/tasks.md@ T015 this is a skeleton;
scenarios land in T016-T020.
-}
module DevnetFullFlowSpec (spec) where

import DevnetEnv (DevnetEnv (..), withEnv)
import Test.Hspec (Spec, around, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "Devnet full protocol flow (US1 — #9)" $ do
    around withEnv $ do
        it "devnet comes up with a funded genesis address" $ \env ->
            deGenesisUtxos env `shouldSatisfy` (not . null)
