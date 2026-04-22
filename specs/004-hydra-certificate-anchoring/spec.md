# Spec: Hydra Certificate Anchoring

**Issue**: #23 (card-based identity model + certificate anchoring)
**Status**: Design — resolves open research questions from WIP.md
**Constitution**: v6.0.0 §III-A

## Problem

Off-chain cap certificates are incompatible with coalition revocation.
A leaked Jubjub key produces unlimited forged certificates
indistinguishable from legitimate ones. All forged certificates are
spendable across the entire coalition — a money printer for the
attacker.

Certificate anchoring solves this by requiring every topup to be
recorded on-chain. A revoked key cannot anchor new certificates.
Existing certificates before revocation remain valid (they were
legitimately signed); the damage window is bounded.

One topup per L1 transaction is economically prohibitive.
Hydra provides the same validator semantics at near-zero cost.

## Architecture

### Layers

| Layer | Transactions | State |
|-------|-------------|-------|
| **L1** | settlement, redemption, revert, shop/card registration, certificate root promotion | Spend trie, card trie, pending trie, certificate root (reference input) |
| **L2 (Hydra)** | topup only | Certificate MPF (SHA-256) |

### Hydra Head Configuration

**Participants**: coalition only. Shops do NOT participate in the head.

**Rationale**: unanimous consensus requires all participants to sign
every snapshot. Adding N shops means N+1 parties must be online and
responsive. A single unresponsive shop blocks all topups coalition-wide.
Coalition-only (1 party or a small coalition-operated committee) keeps
the head operational. Shop audit happens *after* fan-out via IPFS
changeset verification and L1 counter-signing.

**Contestation period**: 12 hours minimum (Cardano mainnet safe zone =
`3 * k / f` ≈ 36,000 slots ≈ 10 hours; round up to 12h for safety).

**Hydra scripts**: published once on L1 via `--hydra-scripts-tx-id`.
The head uses standard Hydra validators — no custom head logic.

### Certificate MPF on the Hydra Head

The Hydra head maintains one UTxO at a **certificate-store script
address**. This UTxO's datum is the SHA-256 Merkle Patricia Forestry
root of all anchored certificates.

```
CertificateStoreDatum
  { mpfRoot :: ByteString    -- SHA-256 MPF root (32 bytes)
  , epoch   :: Integer        -- daily epoch counter
  }
```

The certificate-store validator allows spending only if:
1. The transaction includes a valid MPF insert proof in the redeemer
2. The inserted key is `(issuer_jubjub_pk, user_id)`
3. The inserted value is `certificate_id` (raw bytes, 32)
4. The Ed25519 key that signed the topup transaction is a registered
   card (checked against a reference input from L1 — the coalition
   datum snapshot committed into the head)
5. Output at the same address carries the updated `mpfRoot`

This validator runs **inside the Hydra head** — same Plutus semantics
as L1, zero L1 fees.

### Topup Transaction (L2)

A topup is a single Hydra transaction:

**Inputs:**
- Certificate-store UTxO (consumed, updated)
- Coalition datum UTxO (reference input — committed into head at init)

**Redeemer:**
```
TopupRedeemer
  { issuerJubjubPk :: ByteString   -- 32 bytes
  , userId         :: Integer
  , certificateId  :: ByteString   -- Poseidon(user_id, cap), 32 bytes
  , mpfProof       :: MpfProof     -- SHA-256 insert proof
  }
```

**Outputs:**
- Certificate-store UTxO with updated `mpfRoot`

**Signatures:**
- Transaction signed by the card's Ed25519 key (reificator submits,
  card signs via secure element)

**What the validator does NOT check:**
- It does not verify that `certificateId == Poseidon(userId, cap)`.
  Poseidon is not available on-chain. The binding is enforced later:
  at spend time, the ZK circuit computes `certificate_id` from its
  private inputs and exposes it as a public input. The L1 settlement
  validator checks that this value has a valid MPF membership proof
  against the certificate root.
- It does not verify the Jubjub signature on the cap certificate.
  That is the ZK circuit's job at spend time.

**What the validator DOES check:**
- MPF insert proof is valid (new root derives correctly)
- The signing Ed25519 key is a registered card in the coalition datum
- The `issuerJubjubPk` matches the Jubjub key registered for that
  card's shop in the coalition datum

This is sufficient: a registered card signed the topup, and the card's
Jubjub key matches. The actual cap validity is deferred to the ZK
circuit. If someone anchors a garbage `certificateId`, it will never
pass the ZK proof at spend time.

### Daily Cycle

#### 1. Head Opens (morning)

The coalition opens a Hydra head with:
- The certificate-store UTxO (committed from L1 or carried from
  previous cycle)
- A snapshot of the coalition datum (committed as reference input)

If this is the first cycle, the certificate-store UTxO is created
on L1 with an empty MPF root, then committed into the head.

#### 2. Topups Throughout the Day

Reificators connect to the Hydra node via the WebSocket API:
- Submit topup transactions (same Cardano tx format)
- Receive `SnapshotConfirmed` events as confirmation
- Each confirmed snapshot is irrevocable (unanimous consensus)

The reificator gives the customer a Hydra snapshot confirmation as
proof of inclusion. The customer can verify the snapshot signature
against the known participant keys.

#### 3. Changeset Publication (end of day)

Before closing the head, the coalition publishes to IPFS:

```json
{
  "headId": "<head currency symbol>",
  "epoch": 42,
  "previousRoot": "<hex 32 bytes>",
  "newRoot": "<hex 32 bytes>",
  "entries": [
    {
      "issuerJubjubPk": "<hex 32 bytes>",
      "userId": "<integer>",
      "certificateId": "<hex 32 bytes>",
      "cardEd25519Pk": "<hex 32 bytes>",
      "snapshotNumber": 17
    }
  ]
}
```

Each entry is independently verifiable:
- `issuerJubjubPk` is a registered Jubjub key (check L1 coalition datum)
- `cardEd25519Pk` is a registered card for that shop (check L1)
- The full set of entries, applied in order to `previousRoot`, must
  produce `newRoot`

#### 4. Shop Audit

Each shop:
1. Fetches the IPFS changeset (CID is broadcast by coalition)
2. Verifies all entries match registered keys on L1
3. Verifies the MPF root transition is correct
4. Checks that entries attributed to their shop match their records
   (reificator logs)
5. If anything is wrong: refuses to counter-sign

A single honest shop catches any forgery. The coalition cannot
fabricate entries because it lacks any shop's Jubjub private key.

#### 5. Close and Fan-out

The coalition closes the head. The latest confirmed snapshot is
posted to L1. After the contestation period (12h), anyone can
fan-out.

Fan-out produces the certificate-store UTxO on L1.

#### 6. Certificate Root Promotion (L1)

A separate L1 transaction promotes the fan-out's certificate-store
UTxO to the active certificate root:

**Certificate Root Promotion Validator:**
- Input: provisional certificate-store UTxO (from fan-out)
- Output: certificate-root UTxO (at the reference-input address)
- Required signatures: K-of-N shop signatures (configurable threshold)
- Redeemer: IPFS CID of the changeset + shop signatures

This two-step (fan-out → promotion) ensures shops explicitly approve
the root before it becomes active for settlements. The previous
certificate root remains active until promotion completes — no gap
in service.

**Alternative (simpler, day-one)**: coalition is the sole promoter
(no shop counter-signing on-chain). Shops audit off-chain and raise
disputes out-of-band. Counter-signing is added as a hardening step
in a later issue.

### L1 Settlement Changes

The settlement validator gains one additional check:

**New check**: the redeemer includes a SHA-256 MPF membership proof
for `certificate_id` against the certificate root (reference input).
The validator verifies this proof on-chain.

```
SettlementRedeemer (extends existing)
  { ...existing fields...
  , certificateId      :: Integer     -- from circuit public inputs
  , certMpfProof       :: MpfProof   -- SHA-256 membership proof
  }
```

The validator:
1. Reads the certificate root from the reference input
2. Verifies `MPF.member(certificateId, certMpfProof, certRoot)`
3. Cross-checks that `certificateId` matches the circuit's
   `certificate_id` public input (index 8)

### Circuit Changes

Add one public input: `certificate_id` at index 8.

```
public input [8]: certificate_id = Poseidon(user_id, cap)
```

The circuit already computes `Poseidon(user_id, cap)` internally
(it verifies the issuer's Jubjub signature over this value). The
change is: expose it as a public input instead of keeping it
internal.

Total public inputs: 9 (was 8).

### Reificator Hydra Connectivity

The reificator connects to the Hydra node via WebSocket:

```
ws://<hydra-node>:4001
```

**Submit topup**: `{"tag": "NewTx", "transaction": {...}}`
**Confirm**: listen for `SnapshotConfirmed` containing the tx

The reificator builds the topup transaction using the same
`cardano-cli transaction build-raw` format. The card signs via
secure element. The reificator submits to the head.

**Fallback**: if the Hydra node is unreachable, the topup is
queued locally and retried. The customer receives the signed
cap certificate immediately (signed by the card's Jubjub key)
but cannot spend it until the topup is anchored and fanned out.

### Revocation Under Anchoring

When a card's Jubjub key is compromised:

1. Shop revokes the card on L1 (removes from coalition datum)
2. The Hydra head's coalition-datum reference becomes stale —
   the revoked card's Ed25519 key is no longer registered
3. New topup transactions from the revoked card are rejected
   by the certificate-store validator (card not registered)
4. Certificates anchored before revocation remain valid and
   spendable — they were legitimately signed
5. The damage window = time between compromise and revocation

This is the fundamental improvement over unanchored certificates:
revocation actually works. Without anchoring, a leaked key produces
unlimited forged certificates forever.

**Coalition datum refresh**: the head must see the updated coalition
datum after a revocation. Options:
- (a) Close and reopen the head with the new datum committed
- (b) Use incremental commit to add the updated datum
- (c) The head validator checks a secondary reference (L1 datum
  via the chain component)

Option (a) is simplest and acceptable for the rare revocation event.
The head closes, fans out, the certificate root is promoted, and a
new head opens with the updated coalition datum.

## Open Design Decisions

1. **Shop counter-signing**: on-chain (K-of-N multisig on promotion)
   vs off-chain (dispute-based). Day-one recommendation: off-chain
   audit, on-chain counter-signing in a later issue.

2. **Head lifecycle across days**: does the head close and reopen
   daily, or stay open with incremental decommits? Daily close is
   simpler and provides a natural audit boundary. Incremental
   decommit would require the certificate-store UTxO to be
   decommitted (materialized on L1) without closing the head.

3. **Multiple reificators**: the Hydra head is single-party
   (coalition). Multiple reificators submit to the same head via
   WebSocket. The head serializes transactions via the snapshot
   leader. No contention — each topup consumes and reproduces the
   same certificate-store UTxO, but the head handles this
   sequentially within its UTxO set.

4. **Certificate-store UTxO contention inside the head**: with many
   concurrent topups, all consuming the same UTxO, the head processes
   them sequentially (one per snapshot). This is fine for the expected
   volume (hundreds/day, not thousands/second). If throughput becomes
   an issue, the MPF can be sharded across multiple UTxOs.

## Non-Goals

- Multi-certificate spend circuit (separate issue)
- Native Rust prover (issue #2)
- MPFS integration for L1 contention (issue #8)
- On-chain shop counter-signing of certificate root (future hardening)
