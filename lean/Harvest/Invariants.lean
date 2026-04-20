/-
  Harvest.Invariants — Preservation theorems for Harvest
  transitions.

  Each theorem below is the Lean side of a property that should
  also hold in Haskell (QuickCheck) and, eventually, on-chain.
  When a theorem is proved here, the corresponding Haskell
  property becomes a regression harness for the implementation;
  when the proof breaks during design refactoring, the
  corresponding property and the on-chain validator rule must
  change in the same PR.
-/

import Harvest.Types
import Harvest.Transitions

namespace Harvest

/--
  A settlement submitted under a revoked reificator cannot
  change state.

  Direct consequence of the `canSettle` guard: revocation is
  load-bearing — the registry-trie membership vs. non-membership
  branch of the validator is mirrored here as a boolean guard
  that short-circuits the state update.

  This is FR-010's negative assertion (story 4, reificator
  revocation) in theorem form.
-/
theorem revoked_reificator_cannot_settle
    (h : Harvest) (user : UserId) (old new : Commitment)
    (shop reif : PubKey)
    (hrev : h.revoked.elem reif = true) :
    applySettle h user old new shop reif = h := by
  have hc : canSettle h user old new shop reif = false := by
    simp only [canSettle, hrev, Bool.not_true, Bool.and_false,
               Bool.false_and, Bool.and_false]
  simp [applySettle, hc]

/--
  Onboarding a shop never touches the customer list.

  Mirrors the off-chain claim that coalition-governance
  transactions do not perturb per-customer script UTxOs.
-/
theorem applyOnboardShop_preserves_customers
    (h : Harvest) (shop : PubKey) :
    (applyOnboardShop h shop).customers = h.customers := by
  unfold applyOnboardShop
  split <;> rfl

/--
  Onboarding a reificator never touches the customer list.
-/
theorem applyOnboardReificator_preserves_customers
    (h : Harvest) (reif : PubKey) :
    (applyOnboardReificator h reif).customers = h.customers := by
  unfold applyOnboardReificator
  rfl

/--
  Revocation never touches the customer list directly.

  (Existing entries authorised by the now-revoked reificator
  remain on-chain until explicitly redeemed or reverted; they
  simply cannot be *settled* against — see
  `revoked_reificator_cannot_settle`.)
-/
theorem applyRevoke_preserves_customers
    (h : Harvest) (reif : PubKey) :
    (applyRevoke h reif).customers = h.customers := by
  unfold applyRevoke
  split <;> rfl

/--
  Revocation is idempotent.
-/
theorem applyRevoke_idempotent
    (h : Harvest) (reif : PubKey) :
    applyRevoke (applyRevoke h reif) reif = applyRevoke h reif := by
  unfold applyRevoke
  split <;> simp_all

end Harvest
