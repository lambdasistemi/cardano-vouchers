pragma circom 2.1.0;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/poseidon.circom";

/// Voucher spend circuit.
///
/// Proves that a user can spend amount `d` from a voucher with hidden cap `C`,
/// updating their committed counter from S_old to S_new, without revealing
/// the cap or the running total.
///
/// Commitments use Poseidon hash (field-arithmetic only, works on BLS12-381).
/// Commit(v, r) = Poseidon(v, r)  — a single field element.
///
/// Public inputs (visible on-chain):
///   - d             : spend amount
///   - commit_S_old  : Poseidon commitment to old counter
///   - commit_S_new  : Poseidon commitment to new counter
///
/// Private inputs (only the user knows):
///   - S_old   : old running total of spent tokens
///   - S_new   : new running total after this spend
///   - C       : the voucher cap issued by the supermarket
///   - r_old   : randomness for old commitment
///   - r_new   : randomness for new commitment

template VoucherSpend(nBits) {
    // --- public inputs ---
    signal input d;
    signal input commit_S_old;
    signal input commit_S_new;

    // --- private inputs ---
    signal input S_old;
    signal input S_new;
    signal input C;
    signal input r_old;
    signal input r_new;

    // 1. Counter increment: S_new = S_old + d
    S_new === S_old + d;

    // 2. No overspend: S_new <= C
    component rangeCheck = LessEqThan(nBits);
    rangeCheck.in[0] <== S_new;
    rangeCheck.in[1] <== C;
    rangeCheck.out === 1;

    // 3. Old commitment matches: Poseidon(S_old, r_old)
    component hashOld = Poseidon(2);
    hashOld.inputs[0] <== S_old;
    hashOld.inputs[1] <== r_old;
    commit_S_old === hashOld.out;

    // 4. New commitment matches: Poseidon(S_new, r_new)
    component hashNew = Poseidon(2);
    hashNew.inputs[0] <== S_new;
    hashNew.inputs[1] <== r_new;
    commit_S_new === hashNew.out;
}

// 32-bit range: caps up to ~4 billion tokens
component main {public [d, commit_S_old, commit_S_new]} = VoucherSpend(32);
