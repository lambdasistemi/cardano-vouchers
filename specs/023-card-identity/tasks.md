# Tasks: Card-Based Identity Model + Certificate Anchoring

**Plan**: [plan.md](plan.md) | **Spec**: [spec 004](../004-hydra-certificate-anchoring/spec.md)

## Phase 1: Circuit — Add certificate_id (index 8)

- [ ] **1.1** Add `certificate_id` output signal to `voucher_spend.circom`
  - Compute `certificate_id = Poseidon(user_id, cap)` (already computed internally for EdDSA verification)
  - Expose as public output mapped to index 8
  - Total public inputs becomes 9
- [ ] **1.2** Update fixture generator to include `certificate_id` in public inputs
- [ ] **1.3** Update all existing test fixtures for 9 public inputs
- [ ] **1.4** Run circuit tests — verify existing proofs still validate with the additional output

## Phase 2: On-chain — Certificate-store validator

- [ ] **2.1** Create `certificate_store.ak` validator
  - Datum: `CertificateStoreDatum { mpf_root: ByteArray, epoch: Int }`
  - Redeemer: `TopupRedeemer { issuer_jubjub_pk: ByteArray, user_id: Int, certificate_id: ByteArray, mpf_proof: MpfProof }`
  - Checks: MPF insert proof valid, Ed25519 signer is registered card, issuer Jubjub key matches card's shop
  - Reference input: coalition datum (committed into head)
  - Output: same address, updated `mpf_root`
- [ ] **2.2** Write unit tests for certificate-store validator
  - Valid insert (registered card, correct proof)
  - Reject: unregistered Ed25519 key
  - Reject: issuer Jubjub key doesn't match card's shop
  - Reject: invalid MPF proof
  - Reject: output mpf_root doesn't match proof result
- [ ] **2.3** Verify the validator compiles within Plutus budget for a single insert

## Phase 3: On-chain — Settlement validator update

- [ ] **3.1** Add `certificate_id` and `cert_mpf_proof` fields to settlement redeemer
  - Per spec: `certificateId :: Integer, certMpfProof :: MpfProof`
- [ ] **3.2** Add certificate root reference input reading
  - Read certificate root UTxO by script address or NFT marker
- [ ] **3.3** Add MPF membership verification
  - `MPF.member(certificate_id, certMpfProof, certRoot)` using SHA-256
- [ ] **3.4** Cross-check `certificate_id` against circuit public input index 8
- [ ] **3.5** Update settlement validator tests
  - Valid settlement with certificate proof
  - Reject: certificate_id not in MPF (unanchored certificate)
  - Reject: certificate_id mismatch with circuit public input
  - Reject: wrong certificate root (stale reference input)

## Phase 4: On-chain — Certificate root promotion validator

- [ ] **4.1** Create `certificate_promotion.ak` validator
  - Input: provisional certificate-store UTxO (from fan-out, at certificate-store address)
  - Output: certificate-root UTxO (at reference-input address)
  - Check: MPF root preserved, signed by coalition
- [ ] **4.2** Write unit tests
  - Valid promotion (correct root, coalition signature)
  - Reject: MPF root tampered
  - Reject: unauthorized signer

## Phase 5: Off-chain — Hydra WebSocket client

- [ ] **5.1** Define Hydra API types in `Hydra/Types.hs`
  - `SnapshotConfirmed { headId, snapshot, signatures }`
  - `Snapshot { number, version, confirmed, utxo }`
  - `TxInvalid { headId, utxo, transaction, validationError }`
  - Head lifecycle events: `HeadIsOpen`, `HeadIsClosed`, `ReadyToFanout`
  - `NewTx { transaction }` (client → server)
- [ ] **5.2** Implement WebSocket client in `Hydra/Client.hs`
  - Connect to `ws://host:port`
  - Send `NewTx` messages
  - Parse incoming events (JSON)
  - Callback-based event handling
  - Reconnection with exponential backoff
- [ ] **5.3** Write tests against a mock WebSocket server
  - Submit tx → receive SnapshotConfirmed
  - Submit invalid tx → receive TxInvalid
  - Reconnection after disconnect

## Phase 6: Off-chain — Topup transaction builder

- [ ] **6.1** Implement certificate MPF operations in `Certificate/Store.hs`
  - `insertCertificate :: MpfRoot -> IssuerJubjubPk -> UserId -> CertificateId -> (MpfRoot, MpfProof)`
  - `memberCertificate :: MpfRoot -> CertificateId -> Maybe MpfProof`
  - SHA-256 MPF using existing MPF library
- [ ] **6.2** Implement topup transaction builder in `Hydra/TopupTx.hs`
  - Build Cardano tx consuming certificate-store UTxO
  - Attach TopupRedeemer with MPF insert proof
  - Attach coalition datum as reference input
  - Card signs via Ed25519 (reificator delegates to card)
- [ ] **6.3** Test: built transaction passes certificate-store validator (round-trip)

## Phase 7: Off-chain — Reificator Hydra integration

- [ ] **7.1** Update reificator topup flow
  - After card signs cap certificate (Jubjub): build topup tx, card signs (Ed25519), submit to Hydra via WebSocket
  - Wait for `SnapshotConfirmed`
  - Pass snapshot confirmation to user's phone alongside cap certificate
- [ ] **7.2** Implement topup queue for Hydra disconnections
  - Queue locally if Hydra node unreachable
  - Retry on reconnect
  - Cap certificate still given to user immediately (spendable after anchoring)
- [ ] **7.3** Integration test: full topup cycle
  - Casher sets reward → card signs certificate → Hydra anchoring → user gets certificate + confirmation

## Phase 8: Off-chain — Certificate root promotion + IPFS changeset

- [ ] **8.1** Implement promotion transaction builder in `Certificate/Promotion.hs`
  - Build L1 tx: input from fan-out, output at certificate-root address
  - Coalition signs (day-one)
- [ ] **8.2** Implement IPFS changeset publisher
  - Collect all topup entries from the epoch
  - Format as JSON per spec (headId, epoch, previousRoot, newRoot, entries)
  - Publish to IPFS, return CID
- [ ] **8.3** Implement changeset verification tool
  - Fetch changeset by CID
  - Verify all keys registered on L1
  - Replay inserts: previousRoot → newRoot
  - Per-shop entry cross-check
- [ ] **8.4** Integration test: daily cycle
  - Open head → topups → close → fan-out → publish changeset → verify → promote
