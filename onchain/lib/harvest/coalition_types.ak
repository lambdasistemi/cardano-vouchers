/// Coalition-metadata datum and governance redeemer types.
///
/// Shapes are authoritative per
/// `specs/003-devnet-full-flow/contracts/coalition-metadata-datum.md`.

/// Coalition registry UTxO datum.
///
/// Both `shop_pks` and `reificator_pks` are canonically sorted
/// lexicographically (byte order) and free of duplicates. `issuer_pk`
/// is frozen at coalition-create time and preserved by every governance
/// transition.
pub type CoalitionDatum {
  /// Sorted, unique list of 32-byte Ed25519 shop public keys.
  shop_pks: List<ByteArray>,
  /// Sorted, unique list of 32-byte Ed25519 reificator public keys.
  reificator_pks: List<ByteArray>,
  /// 32-byte Ed25519 public key of the coalition issuer.
  issuer_pk: ByteArray,
}

/// Governance redeemer submitted against the coalition-metadata
/// validator.
///
/// `issuer_sig` is an Ed25519 signature produced by `issuer_pk` over
/// the concatenation `txid || op_tag || target_pk`, where `txid` is
/// the 32-byte transaction body hash, `op_tag` is a single byte
/// (`0x00` = AddShop, `0x01` = AddReificator, `0x02` = RevokeReificator),
/// and `target_pk` is the 32-byte key being added or revoked.
pub type GovernanceRedeemer {
  /// Add a shop key to `shop_pks`.
  AddShop { target_pk: ByteArray, issuer_sig: ByteArray }
  /// Add a reificator key to `reificator_pks`.
  AddReificator { target_pk: ByteArray, issuer_sig: ByteArray }
  /// Remove a reificator key from `reificator_pks`.
  RevokeReificator { target_pk: ByteArray, issuer_sig: ByteArray }
}
