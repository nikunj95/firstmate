/** Render captured Pi viewports (SGR ANSI text) as one self-contained HTML page. */
import { readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";

const [title, out, ...inputs] = process.argv.slice(2);
const base16 = ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
  "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"];

/** Map an xterm 256-color index to CSS. */
function color256(index) {
  if (index < 16) return base16[index];
  if (index < 232) {
    const value = index - 16;
    const steps = [0, 95, 135, 175, 215, 255];
    return `rgb(${steps[Math.floor(value / 36)]},${steps[Math.floor(value / 6) % 6]},${steps[value % 6]})`;
  }
  const grey = 8 + (index - 232) * 10;
  return `rgb(${grey},${grey},${grey})`;
}

/** Escape text for HTML. */
function escapeHtml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** Convert one ANSI capture to HTML spans. */
function render(ansi) {
  const cleaned = ansi.replace(/\r/g, "").replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, "");
  let state = {};
  let html = "";
  const pattern = /\x1b\[([0-9;:]*)([A-Za-z])/g;
  let last = 0;
  let match;
  /** Append text with the current style. */
  const emit = text => {
    if (!text) return;
    const style = [];
    let fg = state.fg, bg = state.bg;
    if (state.inverse) [fg, bg] = [bg ?? "#1e1e2e", fg ?? "#cdd6f4"];
    if (fg) style.push(`color:${fg}`);
    if (bg) style.push(`background:${bg}`);
    if (state.bold) style.push("font-weight:bold");
    if (state.dim) style.push("opacity:.6");
    if (state.italic) style.push("font-style:italic");
    if (state.underline) style.push("text-decoration:underline");
    html += style.length ? `<span style="${style.join(";")}">${escapeHtml(text)}</span>` : escapeHtml(text);
  };
  while ((match = pattern.exec(cleaned))) {
    emit(cleaned.slice(last, match.index));
    last = pattern.lastIndex;
    if (match[2] !== "m") continue;
    const codes = match[1] === "" ? [0] : match[1].split(/[;:]/).map(Number);
    for (let i = 0; i < codes.length; i++) {
      const code = codes[i];
      if (code === 0) state = {};
      else if (code === 1) state.bold = true;
      else if (code === 2) state.dim = true;
      else if (code === 3) state.italic = true;
      else if (code === 4) state.underline = true;
      else if (code === 7) state.inverse = true;
      else if (code === 22) state.bold = state.dim = false;
      else if (code === 23) state.italic = false;
      else if (code === 24) state.underline = false;
      else if (code === 27) state.inverse = false;
      else if (code >= 30 && code <= 37) state.fg = base16[code - 30];
      else if (code >= 90 && code <= 97) state.fg = base16[code - 82];
      else if (code >= 40 && code <= 47) state.bg = base16[code - 40];
      else if (code >= 100 && code <= 107) state.bg = base16[code - 92];
      else if (code === 39) state.fg = undefined;
      else if (code === 49) state.bg = undefined;
      else if ((code === 38 || code === 48) && codes[i + 1] === 5) {
        state[code === 38 ? "fg" : "bg"] = color256(codes[i + 2]);
        i += 2;
      } else if ((code === 38 || code === 48) && codes[i + 1] === 2) {
        state[code === 38 ? "fg" : "bg"] = `rgb(${codes[i + 2]},${codes[i + 3]},${codes[i + 4]})`;
        i += 4;
      }
    }
  }
  emit(cleaned.slice(last));
  return html;
}

const sections = inputs.map(input => {
  const [path, caption] = input.split("::");
  const heading = caption === title ? "" : `<h2>${escapeHtml(caption ?? basename(path))}</h2>`;
  return `<section>${heading}<pre class="term">${render(readFileSync(path, "utf8"))}</pre></section>`;
}).join("\n");
writeFileSync(out, `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(title)}</title>
<style>body{background:#11111b;color:#cdd6f4;font-family:"JetBrains Mono",Menlo,monospace;margin:24px}
h1{font-size:18px}h2{font-size:14px;color:#cba6f7;margin:24px 0 6px}
.term{background:#1e1e2e;color:#cdd6f4;padding:10px;border:1px solid #45475a;font-size:12px;line-height:15px;white-space:pre;display:inline-block;min-width:80ch}.term span{display:inline-block;height:15px;vertical-align:top}</style>
</head><body><h1>${escapeHtml(title)}</h1>${sections}</body></html>`);
