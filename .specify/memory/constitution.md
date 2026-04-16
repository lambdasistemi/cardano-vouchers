# Cardano Vouchers Constitution

## Vision

A loyalty coalition protocol on Cardano. Multiple businesses form a coalition. Each member issues voucher certificates to customers. Customers spend vouchers at any coalition member. One wallet, every loyalty program.

New members get instant foot traffic on day one — existing coalition users walk in and spend vouchers before the new member has issued a single certificate. Every redemption is a real sale. The coalition is the growth flywheel.

## Core Principles

### I. Coalition, Not Silos

The protocol eliminates per-business loyalty silos. Any coalition member issues vouchers. Any coalition member accepts them. Users earn at one place, spend at another. The coalition is the product — not the individual issuer. Joining the coalition means adding a verification key to the on-chain list. That is the only integration step.

### II. User Has No Wallet

The user has no Cardano wallet, no ADA, no signing keys. The user's phone holds certificates, private state (randomness, proving keys), and communicates with reificators. The user never interacts with the blockchain directly.

### III. Smart Contract as Trust Layer

Coalition members do not verify each other's certificates. The on-chain validator does. A fake certificate produces an invalid Groth16 proof. The transaction fails. Nobody loses anything. The smart contract is the only trust relationship — no APIs, no shared databases, no inter-member communication needed.

### IV. Privacy by Default

User balances and voucher caps are never revealed on-chain. All on-chain data is commitments (Poseidon hashes) or zero-knowledge proofs. Only the spend amount per transaction is public. The issuer who tops up a user's cap knows that cap (they signed it), but on-chain observers learn nothing about balances.

### V. Proof Soundness

No spend occurs without a valid Groth16 proof that the committed counter has not exceeded the hidden cap. The proof binds the spend amount `d` — the customer authorizes the exact amount by generating the proof. No party can alter `d` without invalidating the proof. A single Groth16 circuit handles everything: issuer signature verification, counter arithmetic, range check, and commitment binding.

### VI. Monotonic State

Cap only grows (rewards). Spent only grows (redemptions). The invariant is always: spent <= cap. The gap is the user's available balance, known only to the user's phone. A new certificate always supersedes the old one with a higher cap. There is no revocation.

### VII. Reification Model

Spending and redemption are decoupled in time and space.

#### Terminology

- **Reificator**: A device at a cashing point (shop). Has a signing key, settles proofs on-chain, signs certificates. Stores unredeemed nonces. Screen is dormant between interactions but settlement runs continuously in the background.
- **Reification**: The act of exposing a settled spend to the physical world — the reificator's screen lights up and the casher sees the amount.
- **Settlement**: The reificator submits the customer's ZK proof on-chain and waits for confirmation. Happens asynchronously, before the customer visits the shop.
- **Redemption**: The casher acknowledges the reified amount and applies the discount.
- **Topup**: The casher loads new reward points. The reificator signs a fresh cap certificate and sends it to the customer's phone.

#### Two Signing Roles

The reificator signs in two capacities:

1. **As the shop** (issuer): signs cap certificates (`issuer_pk` in the circuit). These are verified inside the ZK proof on-chain.
2. **As itself** (reificator identity): signs reification certificates, bound to its own identity and a nonce. These are verified at redemption by checking the nonce against the unredeemed set.

#### Flow

1. **At home**: Customer contacts the reificator remotely with a spending proof.
2. **Settlement**: Reificator submits the proof on-chain, waits for confirmation. Stores the nonce.
3. **Certificate**: Reificator returns a signed reification certificate (with nonce) to the phone.
4. **At the shop**: Customer reaches the cashing point. Reificator screen is dormant.
5. **Reification**: Customer presents certificate. Reificator verifies nonce is in its unredeemed set, switches to present state — displays the spent amount.
6. **Redemption**: Casher acknowledges, applies the discount. Nonce consumed.
7. **Topup**: Casher sets new reward amount. Reificator signs a fresh cap certificate for the shop, sends to phone.
8. **Dormant**: Reificator screen goes dormant. Background settlement continues.

#### Security Properties

- **No double-spend**: Settlement happens before the customer visits the shop. On-chain confirmation has minutes/hours, not seconds.
- **No amount tampering**: The ZK proof binds the spend amount `d`. The reificator cannot alter it without invalidating the proof. The on-chain validator enforces this.
- **No certificate replay**: Reification certificates carry nonces. Each nonce is consumed on redemption.
- **Reificator-bound**: Reification certificates are redeemable only at the reificator that issued them.

#### State

| Location | What it holds |
|----------|--------------|
| **On-chain** | `user_id → commit(spent)` per issuer (the UTXO at the script address) |
| **User's phone** | User secret, spend randomness, cap certificates (signed by reificators-as-shops), reification certificates (signed by reificators-as-themselves) |
| **Reificator** | Signing key (shop + self), set of unredeemed nonces |

### VIII. On-Chain State: Nested Trie

The shared state is a Merkle Patricia Trie of tries: issuer -> user -> committed spend counter. A spend transaction updates one or more leaves, each with its own Groth16 proof. The trie root sits in a single coalition UTXO.

### IX. Correct Before Optimized

Start simple, prove correctness, then optimize. One UTXO per user before the trie. Single-issuer spends before multi-issuer. snarkjs before native prover. Every step end-to-end testable before the next.

### X. Nix-First

All dependencies, builds, and CI are Nix-managed. The flake produces all derivations. No global installs, no version drift.

## Technology Stack

- **On-chain**: Aiken (Plutus V3), BLS12-381 builtins for Groth16 pairing verification
- **Circuits**: Circom 2 targeting BLS12-381, Poseidon commitments, EdDSA-Poseidon on Jubjub, Groth16 proof system
- **Off-chain**: Haskell (GHC 9.8.4), cardano-node-clients for transaction construction
- **Point compression**: Rust FFI via blst crate
- **Proof generation**: snarkjs (to be replaced by native Rust prover, see issue #2)
- **State**: Merkle Patricia Trie (aiken-lang/merkle-patricia-forestry)

## Development Workflow

- Linear git history, conventional commits
- Specs precede implementation (SDD workflow)
- Small bisect-safe commits: every commit compiles
- Test at system boundaries: proof generation/verification round-trip, on-chain/off-chain interface

## Governance

This constitution supersedes all other practices. Privacy guarantees (Principle IV) and proof soundness (Principle V) cannot be weakened. The coalition model (Principle I) is the project's reason for existence.

**Version**: 4.0.0 | **Ratified**: 2026-04-16
