/-
  Harvest.Transitions — State machine transitions for the Harvest
  prototype.

  Each `applyFoo : Harvest → ... → Harvest` function models one
  protocol-level action and is the Lean twin of a pure Haskell
  action of the same signature shape. The Haskell twins live off-
  chain and drive QuickCheck state-machine tests that mirror the
  theorems in Harvest.Invariants.

  Design choice: guarded transitions return the input state
  unchanged when the guard fails, rather than returning
  `Option Harvest`. This keeps preservation theorems stated as
  `applyFoo h ... = h` and makes the proofs close by `decide` /
  `simp` once the guard is false.
-/

import Harvest.Types

namespace Harvest

/-- Build an initial Harvest state for a freshly-deployed coalition. -/
def applyCreateCoalition
    (issuer : PubKey)
    (shops : List PubKey)
    (reificators : List PubKey) : Harvest :=
  { coalition :=
      { issuerPk      := issuer
      , shopPks       := shops
      , reificatorPks := reificators }
  , customers := []
  , revoked   := []
  }

/-- Onboard an additional shop into the coalition registry.

    No-op if the shop is already registered. Customers are never
    touched — this is a coalition-governance transaction.
-/
def applyOnboardShop (h : Harvest) (shop : PubKey) : Harvest :=
  if h.coalition.shopPks.elem shop then
    h
  else
    { h with
      coalition :=
        { h.coalition with
          shopPks := shop :: h.coalition.shopPks } }

/-- Onboard an additional reificator into the coalition registry.

    Also un-revokes the reificator: re-registering a revoked
    reificator drops it from the `revoked` list.
-/
def applyOnboardReificator (h : Harvest) (reif : PubKey) : Harvest :=
  let coal' :=
    if h.coalition.reificatorPks.elem reif then
      h.coalition
    else
      { h.coalition with
        reificatorPks := reif :: h.coalition.reificatorPks }
  { h with
    coalition := coal'
  , revoked   := h.revoked.filter (· ≠ reif) }

/--
  Precondition for `applySettle`.

  All four conditions must hold for a settlement to mutate state:

  * the shop is registered
  * the reificator is registered
  * the reificator is not revoked
  * if the customer already has an entry, the settlement tx
    declares the same shop/reificator as that entry (i.e.
    settlements for the same customer must stay at the same
    acceptor — this mirrors the per-customer script UTxO design).
-/
def canSettle
    (h : Harvest) (user : UserId) (_old _new : Commitment)
    (shop reif : PubKey) : Bool :=
  h.coalition.shopPks.elem shop
  && h.coalition.reificatorPks.elem reif
  && !h.revoked.elem reif
  && (match lookupCustomer h user with
      | none   => true
      | some e => e.shopPk = shop && e.reificatorPk = reif)

/-- Update-or-insert a customer entry in the association list.

    Linear scan preserves list order; a matching `UserId` is
    overwritten in place so a customer never has two entries.
-/
def upsertCustomer
    (xs : List (UserId × CustomerEntry))
    (entry : CustomerEntry) : List (UserId × CustomerEntry) :=
  match xs with
  | [] => [(entry.userId, entry)]
  | (u, e) :: rest =>
    if u = entry.userId then
      (entry.userId, entry) :: rest
    else
      (u, e) :: upsertCustomer rest entry

/--
  Apply a settlement.

  Guarded by `canSettle`: if the guard fails the state is
  returned unchanged. Otherwise the customer's entry is
  created (first settlement) or updated with the new
  `commit_spent` (subsequent settlement at the same acceptor).
-/
def applySettle
    (h : Harvest) (user : UserId) (old new : Commitment)
    (shop reif : PubKey) : Harvest :=
  if canSettle h user old new shop reif then
    let entry : CustomerEntry :=
      { userId := user
      , commitSpent := new
      , shopPk := shop
      , reificatorPk := reif }
    { h with customers := upsertCustomer h.customers entry }
  else
    h

/-- Apply a redemption. Removes the customer's entry.

    Requires the stored entry's `reificatorPk` to match the
    caller — redemption is authorised by the same reificator that
    accepted the settlements. If the guard fails, state is
    unchanged.
-/
def applyRedeem (h : Harvest) (user : UserId) (reif : PubKey) : Harvest :=
  match lookupCustomer h user with
  | none => h
  | some e =>
    if e.reificatorPk = reif ∧ !h.revoked.elem reif then
      { h with
        customers := h.customers.filter (fun p => p.fst ≠ user) }
    else
      h

/-- Apply a reificator revocation.

    Idempotent: re-revoking does nothing. Does *not* remove the
    reificator from `coalition.reificatorPks`; the `revoked` set
    is the authoritative "cannot settle" check. (On-chain, the
    spec removes the pk from the registry datum; modelling both
    as one `revoked` set is equivalent for the invariants we
    care about and keeps proofs simple.)
-/
def applyRevoke (h : Harvest) (reif : PubKey) : Harvest :=
  if h.revoked.elem reif then
    h
  else
    { h with revoked := reif :: h.revoked }

end Harvest
