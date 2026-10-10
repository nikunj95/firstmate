#!/usr/bin/env bash
# Drive installed Pi + Firstmate Calm + real Codemode in a guarded Herdr lab and keep every screen.
# Usage: drive.sh <worktree> <out-dir> <pi-bin> <pi-package-dir> <scenario: full|offstart|degraded>
set -u
ROOT=$1 OUT=$2 PI_BIN=$3 PI_PACKAGE_DIR=$4 SCENARIO=$5
SCRIPTS=$(cd "$(dirname "$0")" && pwd)
LAB="$ROOT/bin/fm-herdr-lab.sh"
mkdir -p "$OUT"
FIX=$(mktemp -d /tmp/fm-cmfx.XXXXXX)
SESSION=
PANE=
STEP=0

log() { printf '%s\n' "$*" | tee -a "$OUT/transcript.log"; }
die() { log "FAIL: $*"; exit 1; }

teardown() {
  if [ -n "$SESSION" ]; then
    "$LAB" teardown "$SESSION" >>"$OUT/transcript.log" 2>&1 && log "lab teardown ok: $SESSION (default-session tripwire unchanged)" || log "LAB TEARDOWN FAILED: $SESSION"
  fi
  rm -rf "$FIX"
}
trap teardown EXIT

prepare() {
  local calm=$1 dependency dependency_root
  mkdir -p "$FIX/lib" "$FIX/node_modules/@earendil-works" "$FIX/home/config" "$FIX/agent" "$FIX/sessions"
  cp "$ROOT/.pi/extensions/fm-calm.ts" "$FIX/fm-calm.ts"
  cp -RL "$ROOT/.pi/extensions/lib/". "$FIX/lib/"
  ln -s "$PI_PACKAGE_DIR" "$FIX/node_modules/@earendil-works/pi-coding-agent"
  for dependency in @earendil-works/pi-tui @earendil-works/pi-ai typebox; do
    dependency_root="$PI_PACKAGE_DIR/node_modules/$dependency"
    [ -f "$dependency_root/package.json" ] || dependency_root="$PI_PACKAGE_DIR/../../$dependency"
    [ -f "$dependency_root/package.json" ] || die "missing Pi dependency $dependency"
    ln -s "$dependency_root" "$FIX/node_modules/$dependency"
  done
  printf '%s\n' '{"type":"module"}' > "$FIX/package.json"
  printf '%s\n' "$calm" > "$FIX/home/config/calm"
  cp "$SCRIPTS/provider.ts" "$FIX/provider.ts"
  printf 'CODEMODE_READ_PRIVATE\n' > "$FIX/sample.txt"
  printf 'ORDINARY_READ_PRIVATE\n' > "$FIX/ordinary.txt"
  printf '%s\n' '{"theme":"dark","quietStartup":true,"compaction":{"enabled":false}}' > "$FIX/agent/settings.json"
  local tui_mode=
  if "$PI_BIN" --help 2>&1 | grep -q -- '--tui-mode'; then tui_mode='--tui-mode fullscreen'; fi
  printf '%s\n' '#!/usr/bin/env bash' \
    "cd '$FIX' && exec env HOME='$FIX' FM_HOME='$FIX/home' PI_CODING_AGENT_DIR='$FIX/agent' CODEMODE_CONTEXT='$FIX/context.jsonl' CODEMODE_EVENTS='$FIX/events.jsonl' PI_OFFLINE=1 '$PI_BIN' --approve --no-context-files --no-skills --no-prompt-templates --no-extensions -e ./fm-calm.ts -e ./provider.ts -e builtin:codemode --tools read,codemode,fm_branch_outcomes,unrelated_probe --session-dir '$FIX/sessions' --model calm-codemode-test/deterministic $tui_mode \"\$@\"" \
    > "$FIX/launch.sh"
  log "pi: $("$PI_BIN" --version) ($PI_BIN); start config/calm=$calm"
}

launch() {
  local workspace
  workspace=$("$LAB" run "$SESSION" workspace create --cwd "$FIX" --env "HOME=$FIX" --env "ZDOTDIR=$FIX" --no-focus) || die "workspace create"
  PANE=$(printf '%s' "$workspace" | jq -er '.result.root_pane.pane_id') || die "no pane id"
  "$LAB" run "$SESSION" pane run "$PANE" "bash '$FIX/launch.sh' $*" >/dev/null || die "pane run"
}

submit() { log "> submit: $1"; "$LAB" run "$SESSION" pane run "$PANE" "$1" >/dev/null || die "submit $1"; }
key() { log "> key: $1"; "$LAB" run "$SESSION" pane send-keys "$PANE" "$1" >/dev/null || die "key $1"; }

capture_to() {
  "$LAB" run "$SESSION" pane read "$PANE" --source visible --format ansi --raw > "$1.ansi" 2>/dev/null
  sed -e $'s/\x1b\\[[0-9;:]*m//g' -e 's/\r//g' "$1.ansi" > "$1.txt"
}

# Poll until the viewport contains <needle> (or satisfies check-screen <mode> when needle starts with @).
wait_screen() {
  local name=$1 needle=$2 attempt=0
  STEP=$((STEP + 1))
  local file
  file=$(printf '%s/%02d-%s' "$OUT" "$STEP" "$name")
  while [ "$attempt" -lt 150 ]; do
    capture_to "$file"
    if [ "${needle#@}" != "$needle" ]; then
      node "$SCRIPTS/check-screen.mjs" "${needle#@}" "$file.txt" > "$file.check" 2>&1 && { log "ok screen $name: ${needle#@} $(cat "$file.check")"; return 0; }
    elif grep -Fq "$needle" "$file.txt"; then
      log "ok screen $name: contains '$needle'"
      return 0
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done
  die "screen $name never satisfied $needle: $(cat "$file.check" 2>/dev/null)"
}

expect() { # <mode> <name>
  local file
  file=$(printf '%s/%02d-%s' "$OUT" "$STEP" "$2")
  node "$SCRIPTS/check-screen.mjs" "$1" "$file.txt" > "$file.check-$1" 2>&1 || die "screen $2 failed $1: $(cat "$file.check-$1")"
  log "ok screen $2: $1 $(cat "$file.check-$1")"
}

SESSION=$("$LAB" name "cm-$SCENARIO") || die "lab name"
"$LAB" provision "$SESSION" >>"$OUT/transcript.log" 2>&1 || { SESSION=; die "lab provision"; }
log "lab session: $SESSION"

case "$SCENARIO" in
  full)
    prepare on
    launch
    wait_screen start CODEMODE_TEST_READY
    submit /calm-codemode-baseline
    wait_screen baseline-no-tool-turn BASELINE_FINAL
    submit /calm-codemode-test
    wait_screen calm-on-codemode-hidden AFTER_CODEMODE
    expect hidden calm-on-codemode-hidden
    session_file=$(find "$FIX/sessions" -name '*.jsonl' -type f | head -1)
    cp "$session_file" "$OUT/original-session.jsonl"
    key ctrl+o
    wait_screen calm-on-ctrl-o-expanded 'Tool output: expanded'
    expect hidden calm-on-ctrl-o-expanded
    submit /calm
    wait_screen calm-off-stock-expanded OUTCOME_EXPANDED_TAIL
    expect codemode-stock calm-off-stock-expanded
    log "config/calm after /calm: $(cat "$FIX/home/config/calm")"
    key ctrl+o
    wait_screen calm-off-stock-collapsed 'more lines'
    expect codemode-stock calm-off-stock-collapsed
    submit /calm
    wait_screen calm-on-rehidden @hidden
    log "config/calm after second /calm: $(cat "$FIX/home/config/calm")"
    submit "/export $FIX/export.html"
    wait_screen calm-on-export 'Session exported to:'
    expect hidden calm-on-export
    cmp "$session_file" "$OUT/original-session.jsonl" && log "ok session JSONL byte-identical after toggles, expansion and export" || die "session changed"
    cp "$FIX/export.html" "$OUT/export.html"
    key ctrl+d
    sleep 1
    launch --session "'$session_file'"
    wait_screen restart-restored-hidden AFTER_CODEMODE
    expect hidden restart-restored-hidden
    submit /calm
    wait_screen restart-calm-off-stock OUTCOME_PRIVATE_RAW
    expect codemode-stock restart-calm-off-stock
    cmp "$session_file" "$OUT/original-session.jsonl" && log "ok session JSONL byte-identical after restart and restored toggle" || die "session changed after restart"
    cp "$FIX/context.jsonl" "$OUT/provider-context.jsonl"
    cp "$FIX/events.jsonl" "$OUT/tool-events.jsonl"
    SESSION_FILE="$OUT/original-session.jsonl" CODEMODE_FIXTURE="$FIX" node "$ROOT/tests/assets/fm-calm-codemode-content.mjs" 2>&1 | tee -a "$OUT/transcript.log"
    [ "${PIPESTATUS[0]}" -eq 0 ] || die "content preservation"
    key ctrl+d
    ;;
  offstart)
    prepare off
    launch
    wait_screen start CODEMODE_TEST_READY
    submit /calm-codemode-test
    wait_screen calm-off-codemode-stock AFTER_CODEMODE
    expect codemode-stock calm-off-codemode-stock
    submit /calm
    wait_screen first-activation-codemode-hidden @codemode-hidden
    log "config/calm after first /calm: $(cat "$FIX/home/config/calm")"
    submit /calm-codemode-unrelated
    wait_screen calm-on-unrelated-tool-visible AFTER_UNRELATED
    grep -Fq unrelated_probe "$(printf '%s/%02d-%s.txt' "$OUT" "$STEP" calm-on-unrelated-tool-visible)" && log "ok unrelated custom tool row stays visible under Calm" || die "unrelated tool row hidden"
    if grep -rFq 'Codemode transcript remains visible' "$OUT"/*.txt; then die "unexpected capability warning on a supported Pi"; fi
    log "ok no Codemode capability warning on a Pi with registerToolRenderer()"
    key ctrl+d
    ;;
  degraded)
    prepare on
    launch
    wait_screen start-capability-warning CODEMODE_TEST_READY
    grep -Fq CODEMODE_RENDERER_UNAVAILABLE "$(printf '%s/%02d-%s.txt' "$OUT" "$STEP" start-capability-warning)" || die "Pi unexpectedly has registerToolRenderer"
    wait_screen start-capability-warning 'pi.registerToolRenderer() is unavailable'
    submit /calm-codemode-test
    wait_screen codemode-visible-and-executed AFTER_CODEMODE
    expect codemode-stock codemode-visible-and-executed
    submit "/export $FIX/export.html"
    wait_screen export 'Session exported to:'
    [ -s "$FIX/export.html" ] && log "ok export written ($(wc -c < "$FIX/export.html") bytes)" || die "export missing"
    node -e '
      const fs = require("fs");
      const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n").map(JSON.parse);
      const results = lines.filter(e => e.type === "message" && e.message.role === "toolResult" && e.message.toolName === "codemode").map(e => e.message);
      if (results.length !== 2 || !results.every(r => r.content.some(b => b.text?.includes("OUTCOME_PRIVATE_RAW")))) process.exit(1);
      console.log(`ok degraded Pi executed ${results.length} Codemode scripts with original nested output intact`);
    ' "$(find "$FIX/sessions" -name '*.jsonl' -type f | head -1)" | tee -a "$OUT/transcript.log"
    [ "${PIPESTATUS[0]}" -eq 0 ] || die "degraded execution"
    key ctrl+d
    ;;
esac
sleep 1
log "SCENARIO $SCENARIO PASSED"
