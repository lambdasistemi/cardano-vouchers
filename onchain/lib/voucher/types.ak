/// Voucher spend types for Groth16-verified private balance.

/// Groth16 proof: three curve points.
pub type Groth16Proof {
  /// G1 element (compressed, 48 bytes)
  a: ByteArray,
  /// G2 element (compressed, 96 bytes)
  b: ByteArray,
  /// G1 element (compressed, 48 bytes)
  c: ByteArray,
}

/// Groth16 verification key (published by supermarket).
pub type VerificationKey {
  alpha_g1: ByteArray,
  beta_g2: ByteArray,
  gamma_g2: ByteArray,
  delta_g2: ByteArray,
  /// One per public input + 1
  ic: List<ByteArray>,
}

/// On-chain state per user: their public key and committed spend counter.
pub type VoucherDatum {
  /// User's public key (must sign spend transactions)
  user_pk: ByteArray,
  /// Poseidon commitment to the running spend total (single field element).
  commit_spent: Int,
}

/// Redeemer for a spend transaction.
pub type SpendRedeemer {
  /// The public spend amount
  d: Int,
  /// New Poseidon commitment to updated counter
  commit_spent_new: Int,
  /// Groth16 proof that the spend is valid
  proof: Groth16Proof,
}
