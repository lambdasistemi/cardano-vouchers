use aiken/builtin.{
  bls12_381_final_verify, bls12_381_g1_add, bls12_381_g1_scalar_mul,
  bls12_381_g1_uncompress, bls12_381_g2_uncompress, bls12_381_miller_loop,
  bls12_381_mul_miller_loop_result,
}
use voucher/types.{Groth16Proof, VerificationKey}

/// Verify a Groth16 proof against a verification key and public inputs.
///
/// The verification equation:
///   e(A, B) == e(alpha, beta) * e(vk_x, gamma) * e(C, delta)
///
/// Checked as:
///   final_verify(
///     ml(A, B),
///     mul(mul(ml(alpha, beta), ml(vk_x, gamma)), ml(C, delta))
///   )
pub fn verify(
  vk: VerificationKey,
  proof: Groth16Proof,
  public_inputs: List<Int>,
) -> Bool {
  let a = bls12_381_g1_uncompress(proof.a)
  let b = bls12_381_g2_uncompress(proof.b)
  let c = bls12_381_g1_uncompress(proof.c)

  let alpha = bls12_381_g1_uncompress(vk.alpha_g1)
  let beta = bls12_381_g2_uncompress(vk.beta_g2)
  let gamma = bls12_381_g2_uncompress(vk.gamma_g2)
  let delta = bls12_381_g2_uncompress(vk.delta_g2)

  // Compute vk_x = ic[0] + sum(pub[i] * ic[i+1])
  expect [ic0_bytes, ..ic_rest] = vk.ic
  let ic0 = bls12_381_g1_uncompress(ic0_bytes)
  let vk_x = compute_vk_x(ic0, public_inputs, ic_rest)

  // Groth16 pairing check
  let e_ab = bls12_381_miller_loop(a, b)
  let e_alpha_beta = bls12_381_miller_loop(alpha, beta)
  let e_vkx_gamma = bls12_381_miller_loop(vk_x, gamma)
  let e_c_delta = bls12_381_miller_loop(c, delta)

  let rhs =
    bls12_381_mul_miller_loop_result(
      bls12_381_mul_miller_loop_result(e_alpha_beta, e_vkx_gamma),
      e_c_delta,
    )

  bls12_381_final_verify(e_ab, rhs)
}

/// Compute vk_x = acc + sum(pub[i] * ic[i])
fn compute_vk_x(
  acc: G1Element,
  inputs: List<Int>,
  ic: List<ByteArray>,
) -> G1Element {
  when inputs is {
    [] -> acc
    [input, ..rest_inputs] -> {
      expect [ic_bytes, ..rest_ic] = ic
      let ic_point = bls12_381_g1_uncompress(ic_bytes)
      let term = bls12_381_g1_scalar_mul(input, ic_point)
      compute_vk_x(bls12_381_g1_add(acc, term), rest_inputs, rest_ic)
    }
  }
}
