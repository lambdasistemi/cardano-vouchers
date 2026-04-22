# Implementation Plan: Card-Based Identity Model + Certificate Anchoring

**Branch**: `023-card-identity` | **Date**: 2026-04-22 | **Spec**: [spec 004](../004-hydra-certificate-anchoring/spec.md)
**Input**: Constitution v6.0.0 §III-A, protocol docs (actors, lifecycle, security, semantics), architecture docs (on-chain, cryptography)

## Summary

Replace burned-in reificator keys with PIN-protected smart cards (Jubjub EdDSA + Ed25519). Anchor every topup in a SHA-256 MPF on a Hydra head. Fan out the certificate root daily to L1 as a reference input. The settlement validator gains a certificate MPF membership check. The ZK circuit gains `certificate_id` at public input index 8.

## Technical Context

**Language/Version**: Aiken 1.1.x (on-chain), Haskell GHC 9.10 (off-chain), Circom 2 (circuits), Rust (FFI)
**Primary Dependencies**: hydra-node (WebSocket API), aiken-lang/merkle-patricia-forestry (SHA-256 MPF), cardano-node-clients
**Storage**: On-chain UTxOs (L1 tries + certificate root), Hydra head (certificate-store UTxO), IPFS (daily changesets)
**Testing**: Aiken unit tests (validators), Haskell integration tests (off-chain), Circom witness tests (circuit)
**Target Platform**: Cardano mainnet (L1) + Hydra (L2)
**Project Type**: Smart contract protocol (on-chain + off-chain + circuit)
**Constraints**: Plutus V3 budget limits, Hydra head single-UTxO sequential processing, 12h contestation period

## Constitution Check

| Gate | Status |
|------|--------|
| §III-A Two-layer architecture | ✓ Plan follows Hydra+L1 split exactly |
| §V Proof soundness — certificate_id binding | ✓ Circuit exposes Poseidon(user_id, cap) as public input index 8, L1 validator checks MPF membership |
| §IV Privacy — cap stays hidden | ✓ Only Poseidon commitment on-chain, no Poseidon on-chain computation |
| §IX On-chain state — certificate root as reference input | ✓ Zero contention with settlement txs |
| §X Correct before optimized | ✓ Phased: prototype validators first, Hydra integration second |

## Project Structure

### Documentation (this feature)

```text
specs/023-card-identity/
├── plan.md              # This file
├── tasks.md             # Phase 2 output (next step)
specs/004-hydra-certificate-anchoring/
├── spec.md              # Detailed Hydra anchoring spec (written)
docs/protocol/
├── actors.md            # Updated with Hydra roles ✓
├── lifecycle.md         # Updated with Hydra phases ✓
├── security.md          # Updated with anchoring threats ✓
├── semantics.md         # Updated with Hydra terms ✓
docs/architecture/
├── on-chain.md          # Updated with certificate root ✓
├── cryptography.md      # Updated with certificate_id ✓
```

### Source Code (repository root)

```text
circuits/
├── voucher_spend.circom         # Add certificate_id public output (index 8)
├── build/fixtures/              # Updated fixtures with 9 public inputs

onchain/
├── validators/
│   ├── settlement.ak            # Add certMpfProof check + certificate_id cross-check
│   ├── certificate_store.ak     # NEW — Hydra head validator (MPF insert + card registration)
│   └── certificate_promotion.ak # NEW — L1 promotion validator
├── lib/
│   └── mpf.ak                   # SHA-256 MPF verification (existing infra)

offchain/
├── src/
│   ├── Hydra/
│   │   ├── Client.hs            # NEW — WebSocket client for Hydra node
│   │   ├── TopupTx.hs           # NEW — Build topup transactions for the head
│   │   └── Types.hs             # NEW — SnapshotConfirmed, HeadStatus, etc.
│   ├── Certificate/
│   │   ├── Store.hs             # NEW — Certificate MPF operations
│   │   └── Promotion.hs         # NEW — Build promotion transactions
│   └── Reificator.hs            # Update: submit topups via Hydra WebSocket

tests/
├── onchain/
│   ├── certificate_store_test.ak  # NEW
│   └── settlement_test.ak        # Update: certificate_id + MPF proof
├── offchain/
│   ├── Hydra/ClientSpec.hs        # NEW
│   └── Certificate/StoreSpec.hs   # NEW
```

## Implementation Phases

### Phase 1: Circuit — Add certificate_id (index 8)

Smallest possible change. The circuit already computes `Poseidon(user_id, cap)` internally. Expose it as public input index 8. Update all fixtures. Total public inputs: 9.

**Changes**: `circuits/voucher_spend.circom`, fixture generator, all test fixtures
**Risk**: Low — additive change, no existing inputs affected
**Validates**: The circuit correctly exposes the value; existing proofs still verify with 9 inputs

### Phase 2: On-chain — Certificate-store validator

New Aiken validator that runs inside the Hydra head (isomorphic — same Plutus semantics). Checks:
1. SHA-256 MPF insert proof valid
2. Signing Ed25519 key is a registered card (coalition datum reference input)
3. `issuerJubjubPk` matches the card's shop

**Changes**: `onchain/validators/certificate_store.ak`, unit tests
**Risk**: Medium — new validator, needs careful MPF proof verification
**Validates**: Insert proofs produce correct new roots; unregistered cards rejected

### Phase 3: On-chain — Settlement validator update

Add certificate MPF membership check to the existing settlement validator:
1. Read certificate root from reference input
2. Verify `MPF.member(certificate_id, certMpfProof, certRoot)`
3. Cross-check `certificate_id` matches circuit public input index 8

**Changes**: `onchain/validators/settlement.ak`, updated tests
**Risk**: Medium — modifying critical path validator
**Validates**: Settlements with valid certificate proofs pass; unanchored certificates rejected

### Phase 4: On-chain — Certificate root promotion validator

New validator for the L1 promotion transaction (fan-out → active root):
1. Input at certificate-store address
2. Output at certificate-root reference-input address
3. MPF root preserved
4. Signed by coalition (day-one, K-of-N shops future)

**Changes**: `onchain/validators/certificate_promotion.ak`, unit tests
**Risk**: Low — simple transfer validator
**Validates**: Promotion correctly moves root; unauthorized promotions rejected

### Phase 5: Off-chain — Hydra WebSocket client

Haskell WebSocket client for the Hydra node API:
- Connect to `ws://hydra-node:4001`
- Submit `NewTx` messages
- Parse `SnapshotConfirmed`, `TxInvalid`, lifecycle events
- Connection management (reconnect, queue on disconnect)

**Changes**: `offchain/src/Hydra/Client.hs`, `offchain/src/Hydra/Types.hs`, tests
**Risk**: Medium — new external dependency (Hydra node), network handling
**Validates**: Can submit tx and receive confirmation from a local Hydra node

### Phase 6: Off-chain — Topup transaction builder

Build Hydra topup transactions:
- Consume certificate-store UTxO
- Compute MPF insert proof
- Attach coalition datum as reference input
- Card signs via Ed25519

**Changes**: `offchain/src/Hydra/TopupTx.hs`, `offchain/src/Certificate/Store.hs`, tests
**Risk**: Medium — MPF proof construction off-chain
**Validates**: Built transactions pass the certificate-store validator

### Phase 7: Off-chain — Reificator Hydra integration

Update the reificator to:
- Connect to Hydra node at startup
- Submit topup txs after card signs certificate
- Wait for `SnapshotConfirmed`
- Queue topups if Hydra node unreachable
- Pass snapshot confirmation to user's phone

**Changes**: `offchain/src/Reificator.hs`, integration tests
**Risk**: High — changes the topup flow end-to-end
**Validates**: Full topup cycle: casher → card signs → Hydra anchoring → user gets confirmation

### Phase 8: Off-chain — Certificate root promotion + IPFS changeset

- Build promotion transaction (after fan-out)
- Publish IPFS changeset JSON
- Changeset verification tool for shops

**Changes**: `offchain/src/Certificate/Promotion.hs`, IPFS publishing code
**Risk**: Low — straightforward L1 tx + JSON publication
**Validates**: Fan-out produces certificate-store UTxO; promotion makes it active; changeset is verifiable

## Dependencies

```
Phase 1 (circuit) ──┐
                     ├── Phase 3 (settlement update) ── Phase 7 (reificator integration)
Phase 2 (cert-store) ┤                                        │
                     ├── Phase 6 (topup tx builder) ──────────┘
Phase 4 (promotion)  ┤
                     └── Phase 8 (promotion + IPFS)
Phase 5 (WS client) ── Phase 6 ── Phase 7
```

Phases 1, 2, 4, 5 can proceed in parallel. Phase 3 depends on Phase 1. Phase 6 depends on 2 and 5. Phase 7 depends on 3 and 6. Phase 8 depends on 4.
