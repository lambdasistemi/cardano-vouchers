# Lifecycle

A complete walkthrough of the protocol from coalition creation to a multi-certificate spend.

## Phase 1: Coalition Formation

```mermaid
sequenceDiagram
    participant CO as Coalition
    participant L1 as On-Chain
    CO->>L1: create trie root UTXO (three empty tries)
    Note over L1: spend trie: empty<br/>reificator trie: empty<br/>pending trie: empty
```

Anyone with the will to distribute reificators can create a coalition. The coalition's power is limited to manufacturing devices and registering shops.

## Phase 2: Shop Onboarding

```mermaid
sequenceDiagram
    participant S as Shop
    participant CO as Coalition
    participant CD as Card
    participant R as Reificator
    participant L1 as On-Chain

    S->>CO: request shop registration
    CO->>L1: register shop identity
    CO->>CD: manufacture cards (burn Jubjub + Ed25519 keys)
    CO->>S: deliver cards (2-3 per cashing point) + reificator
    CO->>L1: register card (jubjub_pk, ed25519_pk) under shop
    S->>R: insert card into reificator
    Note over R: Device ready<br/>Card provides all signing<br/>Reificator holds only payment key + UTXO
```

The shop funds the reificator's UTXO with ADA for transaction fees and data provider queries. Each card's Ed25519 public key derives a Cardano address visible in the coalition datum — the shop knows exactly which address to top up.

## Phase 3: Customer Enrollment

There is no enrollment. The user installs the app, which generates a random `user_secret`. That's it.

`user_id = Poseidon(user_secret)` — the user exists.

No registration, no account, no on-chain footprint until the first spend.

## Phase 4: First Topup

```mermaid
sequenceDiagram
    participant C as Casher
    participant R as Reificator + Card
    participant P as Phone
    participant H as Hydra Head

    C->>R: "give this customer 5 euros of rewards"
    R->>R: card signs cap certificate (Jubjub EdDSA): Poseidon(user_id, cap=5)
    R->>P: cap certificate
    Note over R: Build topup tx (same Cardano tx format)
    R->>R: card signs topup tx (Ed25519)
    R->>H: submit topup tx via WebSocket
    H->>H: certificate-store validator checks:<br/>1. MPF insert proof valid<br/>2. card Ed25519 key registered<br/>3. issuer Jubjub key matches card's shop
    H->>H: snapshot confirmed (irrevocable)
    H->>R: SnapshotConfirmed
    R->>P: snapshot confirmation
    Note over P: stores certificate + snapshot confirmation
```

The topup has two parts: (1) the cap certificate (Jubjub-signed, given to the user's phone) and (2) the certificate anchoring (Hydra transaction inserting `certificate_id` into the certificate-store MPF). Both happen atomically from the casher's perspective. The card must be inserted — the reificator alone cannot produce certificates or sign transactions.

If the Hydra node is unreachable, the cap certificate is still issued (the card signs it locally) but the anchoring is queued for retry. The certificate is not spendable until anchored and fanned out to L1.

## Phase 5: First Spend (Settlement)

The user is at home. They decide to spend 3 euros using shop A's card certificate.

```mermaid
sequenceDiagram
    participant P as Phone
    participant R as Reificator + Card B
    participant DP as Data Provider
    participant M as MPFS
    participant L1 as On-Chain

    Note over P: user chooses:<br/>d=3, acceptor=card B, certificate from card A (cap=5)
    R->>P: card B authenticates (Ed25519 challenge)<br/>+ proposed TxOutRef to consume
    P->>P: verify card B is registered in coalition datum
    P->>P: generate ZK proof<br/>binds: d=3, pk_c, issuer_A_jubjub_pk<br/>proves: 0 + 3 ≤ 5
    P->>P: Ed25519 sign signed_data =<br/>(TxOutRef ‖ card_B_ed25519_pk ‖ d=3)
    P->>R: ZK proof + pk_c + signature + signed_data
    R->>DP: Merkle proof for user_id in spend trie?
    DP->>R: non-membership proof (first spend)
    R->>M: settlement request (card B signs tx via Ed25519)
    M->>L1: settlement tx
    Note over L1: validator checks:<br/>1. Ed25519.verify(pk_c, signed_data, sig)<br/>2. signed_data.TxOutRef ∈ tx.inputs<br/>3. signed_data.d == redeemer.d<br/>4. customer_pubkey matches proof's pk_c inputs<br/>5. ZK proof valid (includes certificate_id at index 8)<br/>6. non-membership → s_old=0 accepted<br/>7. signed_data.acceptor_pk is a registered card<br/>8. tx is signed by acceptor_pk<br/>9. certificate_id has valid MPF membership proof<br/>   against certificate root (reference input)
    L1->>L1: spend trie: insert (issuer_A_jubjub, user_id) → commit(3)
    L1->>L1: pending trie: insert (card_B_ed25519_pk, nonce) → {user_id, 3}
    R->>P: reification certificate (nonce, d=3, card_B_ed25519_sig)
```

Note: the **issuer** (card A at shop A, which signed the cap certificate) and the **acceptor** (card B at shop B, whose reificator submits) are different cards, potentially at different shops. Both are cards registered in the coalition — "issuer" and "acceptor" are role labels for this transaction, not separate actor types. This is the coalition model.

## Phase 6: Subsequent Spend

The user wants to spend 2 more euros from the same certificate (cap=5, already spent 3).

```mermaid
sequenceDiagram
    participant P as Phone
    participant R as Reificator + Card C
    participant DP as Data Provider
    participant M as MPFS
    participant L1 as On-Chain

    P->>P: generate ZK proof<br/>d=2, issuer_A_jubjub_pk<br/>proves: 3 + 2 ≤ 5
    P->>P: Ed25519 sign (TxOutRef ‖ card_C_ed25519_pk ‖ d=2)
    P->>R: ZK proof + signature + signed_data
    R->>DP: Merkle proof for (issuer_A, user_id)?
    DP->>R: membership proof (commit(3))
    R->>M: settlement request (card C signs tx)
    M->>L1: settlement tx
    Note over L1: validator checks:<br/>1. ZK proof valid<br/>2. membership proof matches commit(3)<br/>3. acceptor_pk (card C) is registered<br/>4. tx signed by card C<br/>5. issuer_A_jubjub_pk registered
    L1->>L1: spend trie: update (issuer_A, user_id) → commit(5)
    L1->>L1: pending trie: insert new entry
    R->>P: reification certificate (card_C_ed25519_sig)
```

The user is now at cap (spent=5, cap=5). Further spends from this certificate fail the range check.

## Phase 7: Physical Redemption

The user has two reification certificates — one from card B's reificator, one from card C's. They visit shop B (card B inserted).

```mermaid
sequenceDiagram
    participant P as Phone
    participant R as Reificator + Card B
    participant DP as Data Provider
    participant C as Casher
    participant M as MPFS
    participant L1 as On-Chain

    P->>R: reification certificate (nonce, d=3, card_B_sig)
    R->>R: verify card B's Ed25519 signature
    R->>DP: Merkle proof for nonce in pending trie?
    DP->>R: membership proof (exists)
    R->>R: screen: "€3.00"
    Note over R: REIFICATION — abstract becomes physical
    C->>C: applies €3.00 discount
    C->>R: acknowledge
    R->>M: redemption request (card B signs tx)
    M->>L1: redemption tx
    L1->>L1: pending trie: remove entry
```

## Phase 8: Topup at Redemption

Same interaction continues — the casher rewards the customer. Card B must be inserted.

```mermaid
sequenceDiagram
    participant C as Casher
    participant R as Reificator + Card B
    participant P as Phone
    participant H as Hydra Head

    C->>R: "give 8 euros of rewards"
    R->>R: card B signs cap certificate (Jubjub EdDSA): Poseidon(user_id, cap=8)
    R->>P: new cap certificate from card B
    R->>R: card B signs topup tx (Ed25519)
    R->>H: submit topup tx via WebSocket
    H->>H: certificate-store validator: MPF insert
    H->>R: SnapshotConfirmed
    R->>P: snapshot confirmation
    Note over P: now holds:<br/>• cap=5 from card A (fully spent)<br/>• cap=8 from card B (0 spent, anchored on L2)<br/>• 1 reification certificate from card C
```

The customer walks away with new earning potential at shop B. The cap certificate is spendable once the current Hydra epoch fans out and the certificate root is promoted on L1.

## Phase 9: Multi-Certificate Spend (Future)

The user has small balances across several shops — 3 euros at A, 5 at B, 2 at C. None is enough alone for a 9 euro purchase. With multi-certificate spend:

```mermaid
graph LR
    A["Shop A: cap=5, spent=2<br/>available=3"] --> P[ZK Proof]
    B["Shop B: cap=8, spent=3<br/>available=5"] --> P
    C["Shop C: cap=4, spent=2<br/>available=2"] --> P
    P --> |"d=9, split: 3+5+1"| TX[Settlement TX]
    TX --> |"update 3 entries"| L1[Trie Root]
```

One proof, multiple certificates, atomic update. The circuit verifies N issuer signatures and proves each partial spend stays within its cap.

## Hydra Daily Cycle

The certificate anchoring layer runs on a daily cycle operated by the coalition. This cycle is orthogonal to the user-facing phases above — it runs continuously in the background.

### Epoch Open

```mermaid
sequenceDiagram
    participant CO as Coalition
    participant L1 as L1
    participant H as Hydra Head

    CO->>L1: read coalition datum (registered shops, cards)
    CO->>L1: read certificate-store UTxO (or create empty one)
    CO->>H: init head (coalition as sole participant)
    CO->>H: commit certificate-store UTxO
    CO->>H: commit coalition datum snapshot (reference input)
    Note over H: Head open — accepting topup transactions
```

If this is the first cycle ever, the coalition creates the certificate-store UTxO on L1 with an empty MPF root, then commits it.

### Topups Throughout the Day

Reificators submit topup transactions to the head via WebSocket (see Phase 4 and Phase 8). Each topup consumes and reproduces the certificate-store UTxO with an updated MPF root. The head processes these sequentially — one per snapshot.

### Changeset Publication

```mermaid
sequenceDiagram
    participant CO as Coalition
    participant IPFS as IPFS

    CO->>CO: collect all topup entries from this epoch
    CO->>IPFS: publish changeset JSON
    Note over IPFS: {headId, epoch, previousRoot,<br/>newRoot, entries: [{issuerJubjubPk,<br/>userId, certificateId, cardEd25519Pk,<br/>snapshotNumber}, ...]}
```

Each entry is independently verifiable against L1: the keys must be registered, and replaying all inserts from `previousRoot` must produce `newRoot`.

### Shop Audit

```mermaid
sequenceDiagram
    participant S as Shop
    participant IPFS as IPFS
    participant L1 as L1

    S->>IPFS: fetch changeset (CID from coalition)
    S->>L1: verify all keys are registered
    S->>S: replay inserts: previousRoot → newRoot
    S->>S: cross-check entries for own shop against reificator logs
    alt Everything valid
        S->>S: approve (ready to counter-sign promotion)
    else Discrepancy found
        S->>S: refuse to counter-sign
    end
```

### Close, Contestation, Fan-out

```mermaid
sequenceDiagram
    participant CO as Coalition
    participant H as Hydra Head
    participant L1 as L1

    CO->>H: close head
    H->>L1: post latest confirmed snapshot
    Note over L1: contestation period (12h)
    Note over L1: anyone can contest with a newer snapshot
    CO->>L1: fan-out
    Note over L1: certificate-store UTxO materializes on L1<br/>at the script address
```

The contestation period is 12 hours minimum (Cardano mainnet safe zone ≈ 10h, rounded up). After contestation, fan-out distributes the head's final UTxO set to L1.

### Certificate Root Promotion

```mermaid
sequenceDiagram
    participant CO as Coalition
    participant L1 as L1

    CO->>L1: promotion tx
    Note over L1: Input: provisional certificate-store UTxO (from fan-out)<br/>Output: certificate-root UTxO (reference input)<br/>Previous root remains active until promotion completes
```

The promotion transaction makes the fanned-out certificate root the active one for settlements. The previous certificate root remains active until promotion completes — no gap in service.

**Day-one**: the coalition is the sole promoter (no on-chain shop counter-signing). Shops audit off-chain and raise disputes out-of-band. On-chain K-of-N shop counter-signing is a future hardening step.

### Revocation During an Epoch

```mermaid
sequenceDiagram
    participant S as Shop
    participant L1 as L1
    participant CO as Coalition
    participant H as Hydra Head

    S->>L1: remove compromised card from coalition datum
    CO->>H: close head (coalition datum is stale)
    CO->>L1: fan-out + promote current root
    CO->>H: open new head with updated coalition datum
    Note over H: revoked card's Ed25519 key no longer registered<br/>new topups from revoked card rejected
```

When a card's Jubjub key is compromised, the shop revokes it on L1. The head must be closed and reopened with the updated coalition datum — the simplest approach for a rare event. Certificates anchored before revocation remain valid (they were legitimately signed). The damage window equals the time between compromise and revocation.
