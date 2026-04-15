use cardano/address.{Address}
use cardano/script_context.{ScriptContext}
use cardano/transaction.{InlineDatum, Input, Output, OutputReference, Transaction}
use voucher/groth16
use voucher/types.{SpendRedeemer, VerificationKey, VoucherDatum}

/// Voucher spend validator.
///
/// Users spend from a supermarket-issued voucher by proving in zero knowledge
/// that their cumulative spend does not exceed their (hidden) cap.
///
/// The verification key is a parameter baked into the validator.
/// Each user has their own UTXO with a committed spend counter.
validator voucher_spend(vk: VerificationKey) {
  spend(
    datum: Option<VoucherDatum>,
    redeemer: SpendRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(voucher) = datum

    // The user must sign the transaction
    let signed = list_has(self.extra_signatories, voucher.user_pk)

    // Public inputs match the circuit: [d, commit_S_old, commit_S_new]
    let public_inputs =
      [redeemer.d, voucher.commit_spent, redeemer.commit_spent_new]

    // Verify the Groth16 proof
    let proof_valid = groth16.verify(vk, redeemer.proof, public_inputs)

    // Check that the output UTXO has the updated commitment
    let output_valid =
      check_output(self, own_ref, voucher.user_pk, redeemer.commit_spent_new)

    signed && proof_valid && output_valid
  }

  else(_ctx: ScriptContext) {
    False
  }
}

/// Verify the continuing output has the updated datum.
fn check_output(
  tx: Transaction,
  own_ref: OutputReference,
  user_pk: ByteArray,
  new_commit: Int,
) -> Bool {
  expect Some(own_input) =
    tx.inputs |> find_input(own_ref)

  let own_address = own_input.output.address

  expect Some(output) =
    tx.outputs |> find_output_at(own_address)

  expect InlineDatum(raw_datum) = output.datum
  expect datum: VoucherDatum = raw_datum
  datum.user_pk == user_pk && datum.commit_spent == new_commit
}

fn list_has(list: List<ByteArray>, item: ByteArray) -> Bool {
  when list is {
    [] -> False
    [head, ..tail] ->
      if head == item {
        True
      } else {
        list_has(tail, item)
      }
  }
}

fn find_input(
  inputs: List<Input>,
  ref: OutputReference,
) -> Option<Input> {
  when inputs is {
    [] -> None
    [input, ..rest] ->
      if input.output_reference == ref {
        Some(input)
      } else {
        find_input(rest, ref)
      }
  }
}

fn find_output_at(
  outputs: List<Output>,
  addr: Address,
) -> Option<Output> {
  when outputs is {
    [] -> None
    [output, ..rest] ->
      if output.address == addr {
        Some(output)
      } else {
        find_output_at(rest, addr)
      }
  }
}
