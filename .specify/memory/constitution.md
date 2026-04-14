# Cardano Vouchers Constitution

## Vision

A loyalty coalition protocol on Cardano. Multiple businesses (supermarkets, shops, services) form a coalition. Each member issues voucher certificates to customers. Customers spend vouchers at any coalition member. One wallet, every loyalty program.

## Core Principles

### I. Coalition, Not Silos

The protocol eliminates per-business loyalty silos. Any coalition member issues vouchers. Any coalition member accepts them. Users earn at one place, spend at another. The coalition is the product — not the individual issuer.

### II. User Device as State Store

The user's phone holds all private state: certificates, caps, randomness, proving keys. No server-side user databases. No accounts. The blockchain is the audit trail, the phone is the wallet. Issuers need only a signing key.

### III. Privacy by Default

User balances and voucher caps are never revealed on-chain. All on-chain data is commitments (Poseidon hashes) or zero-knowledge proofs. Only the spend amount per transaction is public. The issuer who tops up a user's cap knows that cap (they signed it), but on-chain observers learn nothing about balances.

### IV. Proof Soundness

No spend occurs without a valid Groth16 proof that the committed counter has not exceeded the hidden cap. The circuit is the source of truth for valid state transitions. The on-chain validator rejects anything the circuit would not prove.

### V. Centralized Spending, Distributed Issuance

Many issuers, one shared spending validator. Each issuer independently issues certificates using their own signing key and trusted setup. Spending happens at any coalition member against the shared on-chain state. The on-chain validator holds the list of accepted issuer verification keys.

### VI. On-Chain State: Nested Trie

The shared state is a Merkle Patricia Trie of tries: issuer -> user -> committed spend counter. A spend transaction updates one or more leaves, each with its own Groth16 proof. The trie root sits in a single coalition UTXO.

### VII. Cap Update Protocol

When an issuer tops up a user's voucher, the user presents their existing certificate (signed by the issuer). The issuer verifies its own signature, reads the current cap, adds the bonus, and issues a new certificate. This is off-chain — no on-chain transaction needed for issuance.

### VIII. Correct Before Optimized

Start simple, prove correctness, then optimize. One UTXO per user before the trie. Single-issuer spends before multi-issuer. snarkjs before native prover. cardano-cli before programmatic submission. Every step end-to-end testable before the next.

### IX. Nix-First

All dependencies, builds, and CI are Nix-managed. The flake produces all derivations. No global installs, no version drift.

## Technology Stack

- **On-chain**: Aiken (Plutus V3), BLS12-381 builtins for Groth16 pairing verification
- **Circuits**: Circom 2 targeting BLS12-381, Poseidon commitments, Groth16 proof system
- **Off-chain**: Haskell (GHC 9.10+), cardano-node-clients for transaction construction
- **Point compression**: Rust FFI via blst crate
- **Proof generation**: snarkjs (to be replaced by native prover)
- **State**: Merkle Patricia Trie (aiken-lang/merkle-patricia-forestry)

## Development Workflow

- Linear git history, conventional commits
- Specs precede implementation (SDD workflow)
- Small bisect-safe commits: every commit compiles
- Test at system boundaries: proof generation/verification round-trip, on-chain/off-chain interface

## Governance

This constitution supersedes all other practices. Privacy guarantees (Principle III) and proof soundness (Principle IV) cannot be weakened. The coalition model (Principle I) is the project's reason for existence.

**Version**: 2.0.0 | **Ratified**: 2026-04-14
