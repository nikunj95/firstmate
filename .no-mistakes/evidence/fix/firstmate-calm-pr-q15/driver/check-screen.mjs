/** Check one captured Pi viewport for Codemode visibility; exit 0 when the named expectation holds. */
import { readFileSync } from "node:fs";

const [mode, file] = process.argv.slice(2);
const rows = readFileSync(file, "utf8").split("\n").map(row => row.trim());
const leaks = ["text(await", "tools.read", "tools.fm_branch_outcomes", "OUTCOME_PRIVATE_RAW", "CODEMODE_READ_PRIVATE", "seq=7"];

/** Return the leaked Codemode needles present in the viewport. */
function leaked(needles) {
  return needles.filter(needle => rows.some(row => row.includes(needle)));
}

let problems = [];
if (mode === "hidden") {
  problems = leaked([...leaks, "ordinary.txt"]).map(needle => `leaked ${needle}`);
  const baseline = rows.indexOf("BASELINE_FINAL") - rows.indexOf("GENUINE_BASELINE");
  const actual = rows.indexOf("AFTER_CODEMODE") - rows.indexOf("GENUINE_CODEMODE");
  if (!(baseline > 0 && rows.includes("GENUINE_CODEMODE") && rows.includes("AFTER_CODEMODE"))) problems.push("genuine rows missing");
  else if (actual !== baseline) problems.push(`gap ${actual} != baseline ${baseline}`);
  else console.log(`user-to-final row distance: codemode turn ${actual} == no-tool baseline ${baseline}`);
} else if (mode === "codemode-hidden") {
  problems = leaked(leaks).map(needle => `leaked ${needle}`);
  if (!rows.includes("AFTER_CODEMODE")) problems.push("final reply missing");
} else if (mode === "codemode-stock") {
  for (const needle of ["tools.fm_branch_outcomes", "OUTCOME_PRIVATE_RAW"]) {
    if (!rows.some(row => row.includes(needle))) problems.push(`stock row missing ${needle}`);
  }
} else {
  problems.push(`unknown mode ${mode}`);
}
if (problems.length) {
  console.log(problems.join("; "));
  process.exit(1);
}
