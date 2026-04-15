# Voucher Spend Circuit

Zero-knowledge proof that a user can spend `d` tokens from a voucher
without revealing their cap or remaining balance.

## Prerequisites

```bash
# circom compiler
npm install -g circom
# snarkjs for trusted setup + proof generation
npm install -g snarkjs
# circomlib for Pedersen and comparator gadgets
npm install circomlib
```

## Workflow

### 1. Compile the circuit (BLS12-381)

```bash
circom voucher_spend.circom --r1cs --wasm --sym --prime bls12381 -o build/
```

### 2. Trusted setup (once per supermarket)

```bash
# Phase 1: powers of tau (BLS12-381)
snarkjs powersoftau new bls12381 14 pot_0000.ptau
snarkjs powersoftau contribute pot_0000.ptau pot_0001.ptau --name="supermarket"
snarkjs powersoftau prepare phase2 pot_0001.ptau pot_final.ptau

# Phase 2: circuit-specific
snarkjs groth16 setup build/voucher_spend.r1cs pot_final.ptau voucher_spend_0000.zkey
snarkjs zkey contribute voucher_spend_0000.zkey voucher_spend_final.zkey --name="supermarket"

# Export verification key (goes on-chain via ak-381)
snarkjs zkey export verificationkey voucher_spend_final.zkey verification_key.json
```

### 3. Generate a proof (every spend, in the user's wallet)

```bash
# input.json contains public + private inputs
snarkjs groth16 prove voucher_spend_final.zkey build/voucher_spend_js/voucher_spend.wasm input.json proof.json public.json
```

Example `input.json` for spending 10 tokens (old total: 25, cap: 100):

```json
{
  "d": 10,
  "S_old": 25,
  "S_new": 35,
  "C": 100,
  "r_old": 12345678,
  "r_new": 87654321,
  "commit_S_old": ["<pedersen(25, 12345678).x>", "<pedersen(25, 12345678).y>"],
  "commit_S_new": ["<pedersen(35, 87654321).x>", "<pedersen(35, 87654321).y>"]
}
```

### 4. Verify off-chain (for testing)

```bash
snarkjs groth16 verify verification_key.json public.json proof.json
```

### 5. On-chain verification

The `verification_key.json` is consumed by the Aiken validator via
[ak-381](https://github.com/Modulo-P/ak-381) Groth16 verifier.
The proof and public inputs are passed as the transaction redeemer.

## On-chain state machine

Each user UTXO datum holds `(pk, commit_S)`. A spend transaction:

1. Consumes the UTXO with old `commit_S_old`
2. Provides redeemer: `(d, proof, commit_S_new)`
3. Aiken validator checks:
   - Groth16 proof verifies against `(d, commit_S_old, commit_S_new)`
   - Output UTXO datum is `(pk, commit_S_new)`
   - Transaction signed by `pk`
4. Produces new UTXO with `commit_S_new`
