# Harvest Lean model

State-machine formalisation of the Harvest protocol, **prototype
scope only** (no MPF, no MPFS). See
[`specs/003-devnet-full-flow/spec.md`](../specs/003-devnet-full-flow/spec.md)
for the feature spec and
[`docs/journey.md`](../docs/journey.md) for the protocol narrative.

The scope decision is recorded in the project memory note
*"Harvest Lean model scope — prototype only, no MPF"*: on-chain
membership is a linear list scan, and the Lean model uses plain
`List`-backed sets/maps instead of a Merkle abstraction. MPF
refinement (issue #5) and MPFS mediation (issue #8) are deferred
indefinitely; when they land, this model grows an MPF module that
*refines* the set-based state, not one that replaces it.

## Layout

* `Harvest/Types.lean` — `CoalitionDatum`, `CustomerEntry`,
  `Harvest`, plus the `PubKey` / `UserId` / `Commitment` abbreviations.
* `Harvest/Transitions.lean` — `applyCreateCoalition`,
  `applyOnboardShop`, `applyOnboardReificator`, `canSettle`,
  `applySettle`, `applyRedeem`, `applyRevoke`. Each one is intended
  to have a pure Haskell twin with the same signature shape, per
  the workflow skill's "state machine formalization" rule.
* `Harvest/Invariants.lean` — preservation theorems:
  * `revoked_reificator_cannot_settle`
  * `applyOnboardShop_preserves_customers`
  * `applyOnboardReificator_preserves_customers`
  * `applyRevoke_preserves_customers`
  * `applyRevoke_idempotent`

No `sorry`, no custom axioms.

## Building

The `lean/` directory is a **standalone Lake project**. The
`lean-lsp` MCP server and `lake build` both expect it to live at
`lean/` relative to the repo root — do not move, rename, or
restructure it.

The toolchain is pinned in `lean-toolchain`:

```
leanprover/lean4:v4.15.0
```

`lake` / `elan` are not in the global `PATH` on dev machines. The
`lean-lsp` MCP server handles the toolchain automatically. For a
manual build:

1. Install `elan` once (`curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh`).
2. `cd lean && lake build`.

There is no mathlib dependency — proofs rely only on the Lean core
library, so builds are fast and hermetic.

## How this connects to tests

Each `applyFoo : Harvest → ... → Harvest` in
`Harvest/Transitions.lean` will later have a pure Haskell twin of
the same signature shape driving QuickCheck state-machine tests.
Each preservation theorem in `Harvest/Invariants.lean` maps to a
QuickCheck property. When a theorem statement changes during
design refinement, the corresponding Haskell property and, where
load-bearing, the on-chain validator rule must change in the same
PR. See the `workflow` skill, section *"From Lean to tests: state
machine formalization"*, for the full mapping.
