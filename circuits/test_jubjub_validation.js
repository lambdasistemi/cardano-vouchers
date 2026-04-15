// Validate Jubjub curve operations and EdDSA against algebraic invariants.
// No external test vectors exist for EdDSA-Poseidon on Jubjub, so we verify:
//   1. Curve constants (generator on curve, order, cofactor)
//   2. EdDSA equation holds algebraically in JS
//   3. Multiple deterministic signatures verify in the circuit

const fs = require("fs");
const { keygen, sign, initPoseidon, edwardsMul, GEN_X, GEN_Y, BASE8_X, BASE8_Y, JUBJUB_ORDER, q } = require("./lib/jubjub_eddsa.js");

const JUBJUB_A = q - 1n; // -1 mod q
const JUBJUB_D = 19257038036680949359750312669786877991949435402254120286184196891950884077233n;

function mod(a, m) { return ((a % m) + m) % m; }

function isOnCurve(x, y) {
  const x2 = mod(x * x, q);
  const y2 = mod(y * y, q);
  const lhs = mod(JUBJUB_A * x2 + y2, q);
  const rhs = mod(1n + JUBJUB_D * x2 % q * y2, q);
  return lhs === rhs;
}

let passed = 0;
let failed = 0;

function assert(cond, msg) {
  if (cond) { passed++; console.log(`  OK: ${msg}`); }
  else { failed++; console.error(`  FAIL: ${msg}`); }
}

async function main() {
  console.log("=== Jubjub Curve Validation ===\n");

  // 1. Generator is on curve
  console.log("1. Curve constants");
  assert(isOnCurve(GEN_X, GEN_Y), "Generator is on Jubjub curve");
  assert(isOnCurve(BASE8_X, BASE8_Y), "Base8 is on Jubjub curve");

  // 2. Base8 = 8 * Generator
  const [b8x, b8y] = edwardsMul(GEN_X, GEN_Y, 8n);
  assert(b8x === BASE8_X && b8y === BASE8_Y, "Base8 == 8 * Generator");

  // 3. Base8 has order JUBJUB_ORDER (Base8 * order = identity)
  const [idx, idy] = edwardsMul(BASE8_X, BASE8_Y, JUBJUB_ORDER);
  assert(idx === 0n && idy === 1n, "Base8 * JUBJUB_ORDER == identity (0, 1)");

  // 4. Generator is in the subgroup (Gen * JUBJUB_ORDER = identity)
  // Note: Gen is a subgroup generator (not a full-curve generator), but the
  // EdDSA equation holds regardless since both Gen and Base8 are in the
  // prime-order subgroup and Base8 = 8*Gen = (8 mod ORDER)*Gen.
  const [gox, goy] = edwardsMul(GEN_X, GEN_Y, JUBJUB_ORDER);
  assert(gox === 0n && goy === 1n, "Generator * JUBJUB_ORDER == identity (in subgroup)");

  // 6. Identity is on curve
  assert(isOnCurve(0n, 1n), "Identity (0, 1) is on curve");

  console.log("\n=== EdDSA Algebraic Verification ===\n");

  await initPoseidon(__dirname);

  // Run multiple deterministic test cases
  const testCases = [42n, 0n, 1n, 999999n, JUBJUB_ORDER - 1n];

  for (const msg of testCases) {
    const { sk, pkx, pky } = keygen();
    const { R8x, R8y, S } = await sign(sk, pkx, pky, msg);

    // Verify public key is on curve
    assert(isOnCurve(pkx, pky), `msg=${msg}: public key on curve`);
    assert(isOnCurve(R8x, R8y), `msg=${msg}: R8 on curve`);

    // Verify EdDSA equation algebraically: S * Base8 == R8 + h * 8A
    // Compute 8A (cofactor clearing, same as circuit)
    const [a8x, a8y] = edwardsMul(pkx, pky, 8n);
    assert(isOnCurve(a8x, a8y), `msg=${msg}: 8A on curve`);

    // Recompute h (raw Poseidon, NOT reduced — matches circuit)
    // We use the helper circuit to compute Poseidon the same way the circuit does
    const helpers = {};
    for (const n of [5]) {
      const name = `hash${n}_helper`;
      const wasmPath = `${__dirname}/build/${name}_js/${name}.wasm`;
      if (fs.existsSync(wasmPath)) {
        const wasmBuf = fs.readFileSync(wasmPath);
        const wcPath = require.resolve(`${__dirname}/build/${name}_js/witness_calculator.js`);
        delete require.cache[wcPath];
        const wc = require(wcPath);
        helpers[n] = { wc, wasmBuf };
      }
    }

    const calc5 = await helpers[5].wc(helpers[5].wasmBuf);
    const w5 = await calc5.calculateWitness({
      v0: R8x.toString(), v1: R8y.toString(),
      v2: pkx.toString(), v3: pky.toString(), v4: msg.toString()
    }, 0);
    const h_full = BigInt(w5[1].toString());

    // h * 8A
    const [h8ax, h8ay] = edwardsMul(a8x, a8y, h_full);

    // R8 + h*8A (Edwards addition)
    const { edwardsAdd } = (() => {
      function edwardsAdd(x1, y1, x2, y2) {
        const modpow = (b, e, m) => { let r = 1n; b = mod(b, m); while (e > 0n) { if (e & 1n) r = mod(r * b, m); e >>= 1n; b = mod(b * b, m); } return r; };
        const modinv = (a, m) => modpow(a, m - 2n, m);
        const x1x2 = mod(x1 * x2, q);
        const y1y2 = mod(y1 * y2, q);
        const dx = mod(JUBJUB_D * x1x2 % q * y1y2, q);
        const x3n = mod(x1 * y2 + y1 * x2, q);
        const x3d = mod(1n + dx, q);
        const y3n = mod(y1y2 + x1x2, q); // a=-1
        const y3d = mod(q + 1n - dx, q);
        return [mod(x3n * modinv(x3d, q), q), mod(y3n * modinv(y3d, q), q)];
      }
      return { edwardsAdd };
    })();

    const [rx, ry] = edwardsAdd(R8x, R8y, h8ax, h8ay);

    // S * Base8
    const [lx, ly] = edwardsMul(BASE8_X, BASE8_Y, S);

    assert(lx === rx && ly === ry, `msg=${msg}: S*Base8 == R8 + h_full*8A (EdDSA equation)`);
  }

  console.log("\n=== Circuit Witness Verification ===\n");

  // Verify multiple signatures through the circuit
  const wasmBuf = fs.readFileSync("build/test_eddsa_jubjub_js/test_eddsa_jubjub.wasm");
  const wcPath = require.resolve("./build/test_eddsa_jubjub_js/witness_calculator.js");
  delete require.cache[wcPath];
  const wc = require(wcPath);

  const messages = [0n, 1n, 42n, 12345678901234567890n, JUBJUB_ORDER - 1n];

  for (const msg of messages) {
    const { sk, pkx, pky } = keygen();
    const { R8x, R8y, S } = await sign(sk, pkx, pky, msg);

    const calc = await wc(wasmBuf);
    try {
      await calc.calculateWitness({
        enabled: "1",
        Ax: pkx.toString(), Ay: pky.toString(),
        S: S.toString(),
        R8x: R8x.toString(), R8y: R8y.toString(),
        M: msg.toString(),
      }, 0);
      assert(true, `msg=${msg}: circuit witness OK`);
    } catch (e) {
      assert(false, `msg=${msg}: circuit witness FAILED — ${e.message}`);
    }
  }

  console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
  if (failed > 0) process.exit(1);
}

main().catch(e => { console.error(e); process.exit(1); });
