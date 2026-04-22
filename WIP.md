# WIP: Issue #23 — Card-based identity model + certificate anchoring

## Status
Design phase — spec written at `specs/004-hydra-certificate-anchoring/spec.md`.
All five open research questions resolved. Ready for review.

## What's done
- Constitution v6.0.0 with two-layer Hydra+L1 architecture
- All protocol docs updated for card model (actors, lifecycle, security, semantics)
- All architecture docs updated (cryptography — signed_data 74 bytes)
- All spec contracts updated (coalition-metadata-datum, voucher-datum, actions, signed-data-layout)
- Poseidon Merkle tree ruled out (on-chain Poseidon blows Plutus budget)
- SHA-256 MPF on Hydra + L1 reference input identified as viable alternative
- **Hydra research complete** — knowledge graph with 15 nodes merged
- **Spec 004 written** — full certificate anchoring design

## Research Questions — RESOLVED

1. **Hydra snapshot finality**: YES — signed snapshots are irrevocable.
   All participants must multi-sign every snapshot. Once confirmed,
   the state cannot be rolled back. Contestation can only present a
   *newer* snapshot, never invalidate a confirmed one.

2. **Fan-out mechanics**: fan-out distributes the head's final UTxO
   set to L1. The certificate-store UTxO is one of these UTxOs.
   It materializes on L1 at the script address, then a separate
   promotion transaction makes it the active certificate root.

3. **Shop counter-signing**: NOT part of the Hydra protocol.
   Shops audit via IPFS changesets after fan-out. Counter-signing
   happens on L1 (promotion transaction) or off-chain (day-one).
   Fan-out is a single L1 tx — cannot include shop signatures.

4. **Participant model**: coalition-only. Adding shops to the head
   means every shop must be online for every snapshot — a single
   unresponsive shop blocks all topups. Coalition-only keeps the
   head operational. Shop trust is enforced via audit + promotion.

5. **IPFS changeset format**: JSON with entries keyed by
   (issuerJubjubPk, userId, certificateId, cardEd25519Pk,
   snapshotNumber). Each entry independently verifiable against
   L1 coalition datum. Full set replays to produce newRoot.

## Key Design Decisions

- Certificate-store validator runs inside the Hydra head (isomorphic)
- Topup = single Hydra tx consuming/reproducing certificate-store UTxO
- Daily close/reopen cycle (natural audit boundary)
- Coalition datum committed into head as reference input
- Revocation = close head, reopen with updated datum
- Certificate root promotion is a separate L1 tx after fan-out
- Day-one: no on-chain shop counter-signing (off-chain audit only)

## What's NOT done
- Review spec with user
- Plan and tasks
- ~~Protocol docs update for Hydra layer~~ ✓ Done
- On-chain validator changes (certificate-store, settlement MPF check)
- Off-chain code changes (reificator Hydra connectivity)
- Circuit changes (add certificate_id public input at index 8)
- Hydra integration (head management, WebSocket client)
