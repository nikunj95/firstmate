/** Render a captured ANSI terminal viewport as a standalone HTML page for screenshots. */
import { readFileSync, writeFileSync } from "node:fs";

const [input, output, title] = process.argv.slice(2);
const BASIC = ["#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
  "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#ffffff"];

/** Return the CSS color for an xterm 256-color index. */
function xterm256(index) {
  if (index < 16) return BASIC[index];
  if (index < 232) {
    const value = index - 16;
    const level = (step) => (step === 0 ? 0 : 55 + step * 40);
    return `rgb(${level(Math.floor(value / 36))},${level(Math.floor(value / 6) % 6)},${level(value % 6)})`;
  }
  const gray = 8 + (index - 232) * 10;
  return `rgb(${gray},${gray},${gray})`;
}

/** Escape text for HTML. */
function escapeHtml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** Apply one SGR parameter list to the running style. */
function applySgr(style, params) {
  const codes = params.length ? params.split(/[;:]/).map(Number) : [0];
  for (let i = 0; i < codes.length; i++) {
    const code = codes[i];
    if (code === 0) Object.assign(style, { fg: null, bg: null, bold: false, dim: false, italic: false, underline: false, inverse: false });
    else if (code === 1) style.bold = true;
    else if (code === 2) style.dim = true;
    else if (code === 3) style.italic = true;
    else if (code === 4) style.underline = true;
    else if (code === 7) style.inverse = true;
    else if (code === 22) { style.bold = false; style.dim = false; }
    else if (code === 23) style.italic = false;
    else if (code === 24) style.underline = false;
    else if (code === 27) style.inverse = false;
    else if (code >= 30 && code <= 37) style.fg = BASIC[code - 30];
    else if (code >= 90 && code <= 97) style.fg = BASIC[code - 90 + 8];
    else if (code >= 40 && code <= 47) style.bg = BASIC[code - 40];
    else if (code >= 100 && code <= 107) style.bg = BASIC[code - 100 + 8];
    else if (code === 39) style.fg = null;
    else if (code === 49) style.bg = null;
    else if (code === 38 || code === 48) {
      const key = code === 38 ? "fg" : "bg";
      if (codes[i + 1] === 5) { style[key] = xterm256(codes[i + 2]); i += 2; }
      else if (codes[i + 1] === 2) { style[key] = `rgb(${codes[i + 2]},${codes[i + 3]},${codes[i + 4]})`; i += 4; }
    }
  }
}

/** Convert the style to an inline CSS declaration. */
function css(style) {
  let fg = style.fg ?? "#cdd6f4";
  let bg = style.bg;
  if (style.inverse) [fg, bg] = [bg ?? "#1e1e2e", fg];
  const parts = [`color:${fg}`];
  if (bg) parts.push(`background:${bg}`);
  if (style.bold) parts.push("font-weight:bold");
  if (style.dim) parts.push("opacity:0.6");
  if (style.italic) parts.push("font-style:italic");
  if (style.underline) parts.push("text-decoration:underline");
  return parts.join(";");
}

const raw = readFileSync(input, "utf8").replace(/\r/g, "");
const style = { fg: null, bg: null, bold: false, dim: false, italic: false, underline: false, inverse: false };
let html = "";
let pending = "";
let pendingCss = css(style);
const flush = () => {
  for (const [index, part] of pending.split("\n").entries()) {
    if (index > 0) html += "</div><div class=\"l\">";
    if (part) html += `<span style="${pendingCss}">${escapeHtml(part)}</span>`;
  }
  pending = "";
};
const pattern = /\x1b\[([0-9;:?]*)([A-Za-z])|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][A-Za-z0-9]|\x1b[=>]/g;
let last = 0;
for (const match of raw.matchAll(pattern)) {
  pending += raw.slice(last, match.index);
  last = match.index + match[0].length;
  if (match[2] === "m") {
    flush();
    applySgr(style, match[1]);
    pendingCss = css(style);
  }
}
pending += raw.slice(last);
flush();
const page = `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(title ?? input)}</title>
<style>body{margin:0;background:#1e1e2e;}h1{font:14px monospace;color:#a6adc8;margin:8px 12px;}
.term{display:inline-block;margin:0 12px 12px;padding:8px;font:13px Menlo,'JetBrains Mono',monospace;color:#cdd6f4;background:#1e1e2e;border:1px solid #45475a;}
.l{height:17px;line-height:17px;white-space:pre;}.l span{display:inline-block;height:17px;vertical-align:top;}</style>
</head><body><h1>${escapeHtml(title ?? "")}</h1><div class="term"><div class="l">${html}</div></div></body></html>`;
writeFileSync(output, page);
