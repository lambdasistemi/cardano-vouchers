# Cardano Vouchers Constitution

## Core Principles

### I. Privacy by Default

User balances and voucher caps are never revealed on-chain. All on-chain data is either commitments (Poseidon hashes) or zero-knowledge proofs. Only the spend amount per transaction is public. Privacy is the reason this project exists — without it, a simple token ledger suffices.

### II. Proof Soundness

The system security relies entirely on the soundness of Groth16 proofs. No spend can occur without a valid proof that the committed counter has not exceeded the hidden cap. The circuit is the source of truth for what constitutes a valid state transition. The on-chain validator must reject anything the circuit would not prove.

### III. Off-Chain Certificates, On-Chain State

Voucher certificates (containing the cap) live off-chain, issued by the supermarket. On-chain state tracks only committed spend counters. This separation means the supermarket can issue new certificates without any on-chain transaction, and users accumulate multiple independent vouchers freely.

### IV. Minimal On-Chain Footprint

Each spend transaction carries only: the spend amount, the new commitment, and the Groth16 proof. The validator checks the proof, verifies signature, and ensures datum continuity. No auxiliary data, no oracle feeds, no complex multi-step protocols.

### V. Correct Before Optimized

Start with one UTXO per user. Merkle Patricia Trie optimization comes later. Start with snarkjs for proof generation. Native Rust prover comes later. Start with cardano-cli for transactions. Programmatic submission comes later. Every step must be end-to-end testable before the next optimization layer.

### VI. Nix-First

All dependencies, builds, and CI are Nix-managed. The flake produces all derivations. The dev shell provides all tools. No global installs, no version drift between developers or CI.

## Technology Stack

- **On-chain**: Aiken (Plutus V3), BLS12-381 builtins for Groth16 pairing verification
- **Circuits**: Circom 2 targeting BLS12-381, Poseidon commitments, Groth16 proof system
- **Off-chain**: Haskell (GHC 9.10+), cardano-node-clients for transaction construction and submission
- **Point compression**: Rust FFI via blst crate
- **Proof generation**: snarkjs (via Node.js subprocess, to be replaced by native prover)

## Development Workflow

- Linear git history, conventional commits
- Every PR passes CI (build, test, format, lint)
- Specs precede implementation — the SDD workflow gates all feature work
- Small bisect-safe commits: every commit compiles
- Test at system boundaries: on-chain/off-chain interface, proof generation/verification round-trip

## Governance

This constitution supersedes all other practices. Amendments require documentation and rationale. Privacy guarantees (Principle I) and proof soundness (Principle II) cannot be weakened.

**Version**: 1.0.0 | **Ratified**: 2026-04-14
