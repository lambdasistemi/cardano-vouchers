/-
  Harvest.Types — Core state types for the Harvest prototype.

  Scope: the *prototype* architecture described in
  specs/003-devnet-full-flow/spec.md. There is no MPF, no MPFS,
  no Merkle abstraction. On-chain membership is a linear scan.

  The Lean model therefore uses `List`-backed sets/maps, not
  hash-committed structures. See
  the project memory note "Harvest Lean model scope -- prototype
  only, no MPF" for the decision record.

  Every transition `applyFoo : Harvest → ... → Harvest` in
  Harvest.Transitions is intended to have a pure Haskell twin with
  the same signature shape (workflow skill,
  "state machine formalization" section).
-/

namespace Harvest

/-- Abstract public key. No cryptography modelled — identity only. -/
abbrev PubKey := Nat

/-- Abstract user identifier. -/
abbrev UserId := Nat

/-- Poseidon commitment to the customer's running spend counter.
    Abstract: all we need is an equality type. -/
abbrev Commitment := Nat

/--
  The coalition-metadata datum.

  Corresponds on-chain to the reference-input UTxO enumerating
  registered shops, registered reificators, and the issuer key.
  Consumed only by coalition-governance transactions; referenced
  (never consumed) by settlement / redemption / revert.
-/
structure CoalitionDatum where
  issuerPk      : PubKey
  shopPks       : List PubKey
  reificatorPks : List PubKey
  deriving Repr, DecidableEq

/--
  The per-customer script UTxO datum.

  Each customer that has any pending (non-redeemed) spending has
  exactly one of these. `shopPk` / `reificatorPk` record who
  authorised the entry; both must still be registered (and the
  reificator must not be revoked) for a settlement against it to
  be accepted.
-/
structure CustomerEntry where
  userId       : UserId
  commitSpent  : Commitment
  shopPk       : PubKey
  reificatorPk : PubKey
  deriving Repr, DecidableEq

/--
  The full Harvest state at a point in time.

  * `coalition` — current coalition datum (issuer, shops, reificators).
  * `customers` — association list from `UserId` to that user's
    single pending `CustomerEntry`. Modelled as `List (UserId ×
    CustomerEntry)` rather than a finite map so we stay
    dependency-free; lookups are linear scans.
  * `revoked` — reificator public keys that have been revoked.
    A revoked reificator's entries cannot be settled against.
-/
structure Harvest where
  coalition : CoalitionDatum
  customers : List (UserId × CustomerEntry)
  revoked   : List PubKey
  deriving Repr

/-- Membership in a list-as-set, decidable by `DecidableEq`. -/
@[inline] def memSet {α : Type} [DecidableEq α] (x : α) (xs : List α) : Bool :=
  xs.elem x

/-- Find a customer entry by user id, linear scan. -/
def lookupCustomer
    (h : Harvest) (user : UserId) : Option CustomerEntry :=
  (h.customers.find? (fun p => p.fst == user)).map Prod.snd

end Harvest
