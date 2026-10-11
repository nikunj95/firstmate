/** Assert Codemode visibility in one captured Pi viewport: `hidden`, `hidden-gapless`, or `stock`. */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const [file, mode] = process.argv.slice(2);
const rows = readFileSync(file, "utf8").split("\n").map((row) => row.trim());
const codemodeNeedles = ["text(await", "tools.read", "tools.fm_branch_outcomes", "OUTCOME_PRIVATE_RAW", "CODEMODE_READ_PRIVATE", "seq=7"];
if (mode === "stock") {
  for (const needle of ["tools.read", "tools.fm_branch_outcomes", "OUTCOME_PRIVATE_RAW"]) {
    assert(rows.some((row) => row.includes(needle)), `stock Codemode presentation lost ${needle}`);
  }
} else {
  assert(rows.includes("GENUINE_CODEMODE") && rows.includes("AFTER_CODEMODE"), "genuine prompt or final reply missing from viewport");
  for (const needle of codemodeNeedles) {
    assert(!rows.some((row) => row.includes(needle)), `Calm leaked ${needle}`);
  }
  if (mode === "hidden-gapless") {
    assert(!rows.some((row) => row.includes("ordinary.txt")), "Calm leaked the ordinary read row");
    const baseline = rows.indexOf("BASELINE_FINAL") - rows.indexOf("GENUINE_BASELINE");
    const actual = rows.indexOf("AFTER_CODEMODE") - rows.indexOf("GENUINE_CODEMODE");
    assert(baseline > 0, "no-tool baseline turn missing from viewport");
    assert.equal(actual, baseline, "Codemode left residual spacing");
  }
}
console.log(`ok - ${file} is ${mode}`);
