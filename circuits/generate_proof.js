const snarkjs = require("snarkjs");
const fs = require("fs");

async function main() {
  const zkey = "build/voucher_spend.zkey";

  // Load parameters from file or use defaults
  let S_old, d, S_new, C, r_old, r_new;
  const paramFile = process.argv[2];
  if (paramFile) {
    const params = JSON.parse(fs.readFileSync(paramFile, "utf8"));
    d = BigInt(params.d);
    S_old = BigInt(params.S_old);
    S_new = BigInt(params.S_new);
    C = BigInt(params.C);
    r_old = BigInt(params.r_old);
    r_new = BigInt(params.r_new);
  } else {
    // Default test case: cap=100, spent 25 so far, spending 10 more
    S_old = 25n;
    d = 10n;
    S_new = S_old + d;
    C = 100n;
    r_old = 12345678n;
    r_new = 87654321n;
  }

  // The Poseidon hash in the circuit uses BLS12-381's scalar field.
  // circomlibjs hardcodes BN128 constants, so we can't use it directly.
  //
  // Instead, we use a helper circuit to compute commitments.
  // Or: we use snarkjs witness calculator which operates in the correct field.
  //
  // Strategy: create a helper circuit that outputs the Poseidon hash,
  // generate its witness, and extract the output.
  //
  // Simpler approach: use the main circuit's witness calculator.
  // The witness calculator will compute Poseidon internally and we can
  // extract the signal values from the witness.
  //
  // Even simpler: use snarkjs's wtns export json to read computed signals.

  // Step 1: Generate witness with inputs where commit values are 0 (will fail
  // constraint check but we can use --no-check to get intermediate values).
  // Actually, witness calculators don't have --no-check.
  //
  // Real solution: write a separate "commitment computer" circuit.

  const helperCircom = `
pragma circom 2.1.0;
include "circomlib/circuits/poseidon.circom";
template CommitCompute() {
    signal input v;
    signal input r;
    signal output out;
    component h = Poseidon(2);
    h.inputs[0] <== v;
    h.inputs[1] <== r;
    out <== h.out;
}
component main = CommitCompute();
`;

  fs.writeFileSync("build/commit_helper.circom", helperCircom);

  const { execSync } = require("child_process");

  // Compile helper
  execSync("circom build/commit_helper.circom --prime bls12381 --wasm -l node_modules -o build/", { stdio: "pipe" });

  // Compute commit_S_old
  const wcOld = require("./build/commit_helper_js/witness_calculator.js");
  const wasmHelper = fs.readFileSync("build/commit_helper_js/commit_helper.wasm");
  const calcOld = await wcOld(wasmHelper);
  const wtnsOld = await calcOld.calculateWitness({ v: S_old.toString(), r: r_old.toString() }, 0);
  const commit_old = wtnsOld[1].toString(); // output signal is at index 1

  // Compute commit_S_new
  // Need fresh calculator instance
  delete require.cache[require.resolve("./build/commit_helper_js/witness_calculator.js")];
  const wcNew = require("./build/commit_helper_js/witness_calculator.js");
  const calcNew = await wcNew(wasmHelper);
  const wtnsNew = await calcNew.calculateWitness({ v: S_new.toString(), r: r_new.toString() }, 0);
  const commit_new = wtnsNew[1].toString();

  console.log("commit_S_old:", commit_old);
  console.log("commit_S_new:", commit_new);

  const input = {
    d: d.toString(),
    commit_S_old: commit_old,
    commit_S_new: commit_new,
    S_old: S_old.toString(),
    S_new: S_new.toString(),
    C: C.toString(),
    r_old: r_old.toString(),
    r_new: r_new.toString(),
  };

  fs.writeFileSync("build/input.json", JSON.stringify(input));

  // Generate witness for main circuit
  const wasmMain = fs.readFileSync("build/voucher_spend_js/voucher_spend.wasm");
  const wcMain = require("./build/voucher_spend_js/witness_calculator.js");
  const calcMain = await wcMain(wasmMain);
  const witness = await calcMain.calculateWTNSBin(input, 0);
  fs.writeFileSync("build/witness.wtns", witness);
  console.log("Witness generated");

  // Generate proof
  const { proof, publicSignals } = await snarkjs.groth16.prove(zkey, "build/witness.wtns");
  console.log("Proof generated");
  console.log("Public signals:", publicSignals);

  fs.writeFileSync("build/proof.json", JSON.stringify(proof, null, 2));
  fs.writeFileSync("build/public.json", JSON.stringify(publicSignals, null, 2));

  // Verify off-chain
  const vk = JSON.parse(fs.readFileSync("build/verification_key.json"));
  const valid = await snarkjs.groth16.verify(vk, publicSignals, proof);
  console.log("Verification:", valid ? "VALID" : "INVALID");

  process.exit(valid ? 0 : 1);
}

main().catch(e => { console.error(e); process.exit(1); });
