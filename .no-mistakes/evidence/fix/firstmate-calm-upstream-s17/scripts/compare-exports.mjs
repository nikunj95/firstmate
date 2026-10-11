/**
 * Compare Codemode HTML rendering in Calm exports and shares with the no-Calm stock export.
 * Files from the same Pi session must match byte for byte; files from a different run match
 * stock once each nested call's measured execution time (`1ms`) and Codemode wall time are normalized.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { basename } from "node:path";

const [stockPath, ...otherPaths] = process.argv.slice(2);

/** Decode the session payload Pi embeds in an exported or shared HTML page. */
function sessionData(path) {
  const html = readFileSync(path, "utf8");
  const encoded = html.match(/<script id="session-data" type="application\/json">([^<]+)<\/script>/)?.[1];
  assert(encoded, `${path} has no session data`);
  return JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
}

/** Return the persisted message list from decoded session data. */
function messages(data) {
  return (data.session?.entries ?? data.entries).filter((entry) => entry.type === "message").map((entry) => entry.message);
}

/** Replace measured nested-call durations, and the row padding their digit count shifts, so separate runs compare on presentation alone. */
function withoutDurations(rendering) {
  return JSON.parse(JSON.stringify(rendering).replace(/>\d+ms<\/span> */g, ">#ms</span>"));
}

/** Return message role, tool and content, without per-run ids, timestamps or Codemode wall time. */
function transcript(data) {
  return messages(data).map((message) => [message.role, message.toolName ?? "", JSON.stringify(message.content).replace(/Wall time \d+(\.\d+)? seconds/g, "Wall time # seconds")]);
}

const stock = sessionData(stockPath);
const codemodeIds = messages(stock).filter((message) => message.role === "toolResult" && message.toolName === "codemode").map((message) => message.toolCallId);
assert.equal(codemodeIds.length, 2, "stock export should hold two Codemode results");
for (const id of codemodeIds) {
  assert(stock.renderedTools[id].callHtml.includes("tools.fm_branch_outcomes"), "stock export lost the Codemode script");
  assert(stock.renderedTools[id].resultHtmlExpanded.includes("OUTCOME_PRIVATE_RAW"), "stock export lost the Codemode output");
}
const report = [`stock reference ${basename(stockPath)}: Codemode rows ${codemodeIds.join(", ")}`];
const sessions = [];
for (const path of otherPaths) {
  const data = sessionData(path);
  assert.deepEqual(Object.keys(data.renderedTools ?? {}).sort(), Object.keys(stock.renderedTools).sort(), `${basename(path)} pre-rendered a different tool set`);
  for (const id of codemodeIds) {
    assert.deepEqual(withoutDurations(data.renderedTools[id]), withoutDurations(stock.renderedTools[id]), `${basename(path)} rendered Codemode ${id} differently from stock`);
  }
  assert.deepEqual(transcript(data), transcript(stock), `${basename(path)} message content differs from stock`);
  const sameSession = sessions.find((entry) => JSON.stringify(messages(entry.data)) === JSON.stringify(messages(data)));
  if (sameSession) {
    assert.deepEqual(data.renderedTools, sameSession.data.renderedTools, `${basename(path)} differs byte for byte from ${basename(sameSession.path)} of the same session`);
    report.push(`${basename(path)}: Codemode rendering equals stock; every pre-rendered tool is byte-identical to ${basename(sameSession.path)} (same session)`);
  } else {
    sessions.push({ path, data });
    report.push(`${basename(path)}: Codemode call/collapsed/expanded HTML equals stock apart from measured nested-call durations; message content equals stock`);
  }
}
console.log(report.join("\n"));
