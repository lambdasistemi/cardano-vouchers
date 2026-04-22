# Actors

## Trust Relationships

```mermaid
graph TD
    CO[Coalition] -->|manufactures| CD[Card]
    CO -->|registers| S[Shop]
    CO -->|operates| HH[Hydra Head]
    S -->|inserts card into| R[Reificator]
    CD -->|signs certificates + transactions| R
    R -->|settles proofs| L1[On-Chain]
    R -->|submits topup txs via WebSocket| HH
    R -->|queries| DP[Data Provider]
    HH -->|fan-out → certificate root| L1
    U[User] -->|sends proofs to| R
    U -->|redeems at| R
    C[Casher] -->|operates| R
    S -->|audits IPFS changeset| HH
    DP -->|serves Merkle proofs from| L1

    style CO fill:#445,stroke:#889
    style S fill:#454,stroke:#898
    style CD fill:#534,stroke:#978
    style R fill:#544,stroke:#988
    style U fill:#345,stroke:#689
    style C fill:#453,stroke:#896
    style DP fill:#435,stroke:#879
    style L1 fill:#554,stroke:#998
    style HH fill:#446,stroke:#88a
```

## Coalition

Creates the protocol infrastructure and operates the Hydra head. Minimal ongoing authority over user funds.

| Power | Constraint |
|-------|-----------|
| Create on-chain state (three tries) | One-time |
| Manufacture cards (burn key pairs into secure element) | Cards distributed to shops |
| Register shops and cards on-chain | On request |
| Remove shops | Requires multi-sig from other shops |
| Operate Hydra head (open, close, fan-out) | Coalition-only participants |
| Publish IPFS changeset after each epoch | Auditable by all shops |
| Promote certificate root on L1 | After fan-out + shop audit |

The coalition **cannot**: alter spend state, access user data, forge certificates, submit transactions on behalf of shops, or unilaterally remove members.

### Hydra Head Operator Role

The coalition is the sole participant in the Hydra head. This is a deliberate design choice: unanimous consensus requires every participant to sign every snapshot. Adding N shops would mean N+1 parties must be online — a single unresponsive shop blocks all topups coalition-wide.

The coalition operates a daily cycle:

1. **Open** the head each morning (commit certificate-store UTxO + coalition datum snapshot)
2. **Accept topup transactions** throughout the day (submitted by reificators via WebSocket)
3. **Publish IPFS changeset** at end of day (all entries, independently verifiable)
4. **Close** the head, wait for contestation period (12h)
5. **Fan-out** the certificate-store UTxO to L1
6. **Promote** the new certificate root on L1

The coalition cannot forge certificates (it lacks any shop's Jubjub key) and cannot fabricate changeset entries (each entry references a registered card's Ed25519 key that signed the Hydra transaction). Shops audit the IPFS changeset and can refuse to counter-sign if anything is wrong.

## Shop

A business in the coalition. Sovereign once onboarded.

| Has | Purpose |
|-----|---------|
| Cards (2-3 per cashing point) | Sign certificates and transactions via secure element |
| Master key (held separately, never on any device) | Revert pending entries after device loss/theft |
| Fleet of reificators | Physical cashing points (commodity hardware) |

The shop receives cards from the coalition. One card is inserted into a reificator to activate it. Spare cards are kept in a safe. The master key is the recovery authority — it can revert pending entries but cannot sign certificates or submit settlements.

### IPFS Changeset Audit

After each Hydra epoch, the shop audits the IPFS changeset published by the coalition:

1. Fetches the changeset (CID broadcast by coalition)
2. Verifies all entries reference registered keys on L1
3. Verifies the MPF root transition is correct (replaying all inserts)
4. Checks entries attributed to their shop match their own reificator logs
5. If anything is wrong: refuses to counter-sign the certificate root promotion

A single honest shop catches any forgery. The coalition cannot fabricate entries because it lacks any shop's Jubjub private key.

### Role terminology: issuer vs acceptor

In a given spend transaction, one card plays the **issuer** role (signed the cap certificate) and one card plays the **acceptor** role (its reificator submits the proof). Issuer and acceptor can be cards at the same shop or different shops — these are per-transaction role labels, not separate actor types. The circuit's public inputs include the issuer card's Jubjub key (`issuer_Ax`, `issuer_Ay`). The customer's `signed_data` includes the acceptor card's Ed25519 key (`acceptor_pk`).

## Card

A PIN-protected smart card with a secure element. The shop's complete identity.

```mermaid
graph LR
    subgraph "Secure Element (PIN-protected)"
        JK[Jubjub EdDSA Key<br/>signs cap certificates]
        EK[Ed25519 Key<br/>signs transactions + reification certificates]
    end
    subgraph "Capabilities"
        JK --> SIGN_CAP[Sign cap certificates<br/>verified in ZK circuit]
        EK --> SIGN_TX[Sign Cardano transactions<br/>verified by Plutus validator]
        EK --> SIGN_REIF[Sign reification certificates<br/>verified by customer phone]
    end
```

| Property | Value |
|----------|-------|
| Secure element | Two key pairs (Jubjub EdDSA + Ed25519), PIN-protected |
| PIN lockout | N failed attempts → permanently locked |
| Distribution | Manufactured by coalition, 2-3 per shop |
| Spare cards | Kept in shop's safe, same shop different keys |
| On-chain registration | Both public keys registered as a pair under a shop |

## Reificator

A stateless commodity hardware device. Inert without a card.

```mermaid
graph LR
    subgraph "Device Hardware"
        SCREEN[Screen<br/>dormant between interactions]
        NET[Network interface]
        SLOT[Card slot]
    end
    subgraph "Funded"
        PK[Cardano Payment Key<br/>+ UTXO for fees]
    end
    subgraph "Capabilities (only with card inserted)"
        SLOT --> SETTLE[Settlement<br/>card signs tx]
        SLOT --> TOPUP[Topup<br/>card signs certificate +<br/>Hydra tx via WebSocket]
        SLOT --> REDEEM[Redemption<br/>card signs tx]
    end
```

| Property | Value |
|----------|-------|
| State | None — all state is on-chain |
| Screen | Dormant between interactions, lights up for reification |
| Background | Continuously settles proofs on-chain (only while card is inserted) |
| Identity keys | None — all signing delegated to the inserted card |
| Payment key | Cardano payment key + UTXO (for transaction fees only) |
| Interchangeable | A shop's card works in any compatible reificator |
| Hydra connectivity | WebSocket to coalition's Hydra node (`ws://hydra-node:4001`) |

### Hydra Topup Submission

During a topup, the reificator builds a Hydra transaction (same Cardano tx format) that consumes the certificate-store UTxO inside the head. The card signs the transaction via its Ed25519 key. The reificator submits the tx to the Hydra node via WebSocket (`{"tag": "NewTx", "transaction": {...}}`), and receives a `SnapshotConfirmed` event as confirmation. The confirmed snapshot is irrevocable.

If the Hydra node is unreachable, the topup is queued locally and retried. The customer receives the signed cap certificate immediately (the card's Jubjub key signs it regardless) but cannot spend it until the topup is anchored on L2 and fanned out to L1.

## User

Anonymous. No registration, no identity beyond `Poseidon(user_secret)`.

| Holds (on phone) | Purpose |
|-------------------|---------|
| `user_secret` | Proves identity in ZK proofs |
| Ed25519 keypair (`sk_c`, `pk_c`) | Signs per-tx authorisation (`acceptor_pk`, TxOutRef, `d`) for the validator's Ed25519 check |
| Spend randomness (`r_old`, `r_new`) | Opens commitments |
| Cap certificates (per shop) | Proves spending allowance |
| Reification certificates (per spend) | Redeems at cashing points |
| Hydra snapshot confirmations (per topup) | Proves certificate is anchored on L2 |

The user **never** interacts with the blockchain. The phone generates proofs, the reificator submits them. At topup time, the user receives both the cap certificate (signed by the card's Jubjub key) and a Hydra snapshot confirmation (proving the certificate is anchored). The certificate is not spendable until its corresponding topup has been fanned out to L1 and the certificate root promoted.

## Key Ceremony

```mermaid
sequenceDiagram
    participant CO as Coalition
    participant S as Shop
    participant CD as Card
    participant R as Reificator
    participant L1 as On-Chain

    Note over CO: Card Manufacturing
    CO->>CD: burn Jubjub EdDSA + Ed25519 key pairs into secure element
    CO->>CO: store both public keys

    Note over S: Onboarding
    S->>CO: request shop registration
    CO->>L1: register shop identity
    CO->>S: deliver cards (2-3 per cashing point)

    Note over S: Card Registration
    CO->>L1: register card (jubjub_pk, ed25519_pk) under shop

    Note over S: Activation
    S->>R: insert card into reificator
    Note over R: Ready — card provides all signing capability
```

The reificator has no keys burned in. All identity and signing capability comes from the card. Device breaks? Plug the card into a new reificator. No re-registration needed.
