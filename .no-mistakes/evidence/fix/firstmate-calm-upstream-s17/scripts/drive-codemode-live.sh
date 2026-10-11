#!/usr/bin/env bash
# Drive real installed Pi with Calm and Codemode inside a guarded named Herdr lab and keep reviewer evidence.
set -u -o pipefail
WT=/Users/nikunjkotecha/.no-mistakes/worktrees/2ee2211c408e/01M4M7NNF4YEM5TECNVZ0CXH4K
EV=/Users/nikunjkotecha/.no-mistakes/evidence/01M4M7NNF4YEM5TECNVZ0CXH4K
SCRIPTS="$EV/scripts"
OUT="$EV/live"
LAB="$WT/bin/fm-herdr-lab.sh"
PI_PACKAGE_DIR="$(npm root -g)/@earendil-works/pi-coding-agent"
FX_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-calm-live.XXXXXX")
SESSION=
PANE=
mkdir -p "$OUT"
: > "$OUT/driver.log"

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$OUT/driver.log"; }
die() { log "FAIL: $*"; exit 1; }
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

cleanup() {
  local status=$?
  if [ -n "$SESSION" ]; then
    "$LAB" teardown "$SESSION" >>"$OUT/driver.log" 2>&1 || { log "lab teardown failed"; status=1; }
  fi
  rm -rf "$FX_ROOT"
  exit "$status"
}
trap cleanup EXIT

prepare() { # <name> <on|off|none>
  local fx="$FX_ROOT/$1" dep dep_root ext=
  mkdir -p "$fx/lib" "$fx/node_modules/@earendil-works" "$fx/home/config" "$fx/agent" "$fx/sessions" "$fx/bin" "$fx/shared" "$fx/out"
  cp "$WT/.pi/extensions/fm-calm.ts" "$fx/fm-calm.ts"
  cp -RL "$WT/.pi/extensions/lib/." "$fx/lib/"
  cp "$WT/tests/assets/fm-calm-codemode-provider.ts" "$fx/provider.ts"
  ln -s "$PI_PACKAGE_DIR" "$fx/node_modules/@earendil-works/pi-coding-agent"
  for dep in @earendil-works/pi-tui @earendil-works/pi-ai typebox; do
    dep_root="$PI_PACKAGE_DIR/node_modules/$dep"
    [ -f "$dep_root/package.json" ] || dep_root="$PI_PACKAGE_DIR/../../$dep"
    ln -s "$dep_root" "$fx/node_modules/$dep"
  done
  printf '%s\n' '{"type":"module"}' > "$fx/package.json"
  printf 'CODEMODE_READ_PRIVATE\n' > "$fx/sample.txt"
  printf 'ORDINARY_READ_PRIVATE\n' > "$fx/ordinary.txt"
  printf '%s\n' '{"theme":"dark","quietStartup":true,"compaction":{"enabled":false}}' > "$fx/agent/settings.json"
  if [ "$2" != none ]; then
    printf '%s\n' "$2" > "$fx/home/config/calm"
    ext="-e ./fm-calm.ts"
  fi
  # A private gh stand-in keeps /share local: it records the HTML Pi would upload and publishes nothing.
  cat > "$fx/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$(perl -MTime::HiRes=time -e 'printf "%.3f", time')" "$*" >> "$GH_SHIM_DIR/calls.log"
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "gist create")
    count=$(find "$GH_SHIM_DIR" -name 'share-*.html' | wc -l | tr -d ' ')
    cp "${!#}" "$GH_SHIM_DIR/share-$count.html"
    printf 'https://gist.github.com/fixture/localshare%s\n' "$count"
    exit 0 ;;
esac
exit 1
SH
  chmod +x "$fx/bin/gh"
  cat > "$fx/launch.sh" <<SH
#!/usr/bin/env bash
cd '$fx' && exec env HOME='$fx' FM_HOME='$fx/home' PI_CODING_AGENT_DIR='$fx/agent' CODEMODE_CONTEXT='$fx/context.jsonl' CODEMODE_EVENTS='$fx/events.jsonl' GH_SHIM_DIR='$fx/shared' PATH='$fx/bin':"\$PATH" PI_OFFLINE=1 pi --approve --no-context-files --no-skills --no-prompt-templates --no-extensions $ext -e ./provider.ts -e builtin:codemode --tools read,codemode,fm_branch_outcomes --session-dir '$fx/sessions' --model calm-codemode-test/deterministic --tui-mode fullscreen "\$@"
SH
}

launch_pi() { # <fixture>
  local fx="$FX_ROOT/$1" workspace
  workspace=$("$LAB" run "$SESSION" workspace create --cwd "$fx" --env "HOME=$fx" --env "ZDOTDIR=$fx" --no-focus) || die "workspace create failed"
  PANE=$(printf '%s' "$workspace" | jq -er '.result.root_pane.pane_id') || die "no pane id"
  "$LAB" run "$SESSION" pane run "$PANE" "bash '$fx/launch.sh'" >/dev/null || die "launch failed"
}

capture_text() { # <file>
  "$LAB" run "$SESSION" pane read "$PANE" --source visible --format text --raw |
    node -e 'let t="";process.stdin.on("data",p=>t+=p);process.stdin.on("end",()=>process.stdout.write(t.replace(/\x1b\[[0-9;]*m/g,"").replace(/\r/g,"")))' > "$1"
}

snapshot() { # <name> <title>
  capture_text "$OUT/$1.txt"
  "$LAB" run "$SESSION" pane read "$PANE" --source visible --format ansi --raw > "$OUT/$1.ansi"
  node "$SCRIPTS/ansi-to-html.mjs" "$OUT/$1.ansi" "$OUT/$1.html" "$2"
}

wait_for() { # <needle> [file]
  local file=${2:-$FX_ROOT/wait.txt} attempt=0
  while [ "$attempt" -lt 150 ]; do
    capture_text "$file"
    grep -Fq "$1" "$file" && return 0
    sleep 0.1
    attempt=$((attempt + 1))
  done
  cp "$file" "$OUT/timeout-$(date +%s).txt"
  die "timed out waiting for: $1"
}

wait_gone() { # <needle>
  local attempt=0
  while [ "$attempt" -lt 150 ]; do
    capture_text "$FX_ROOT/wait.txt"
    grep -Fq "$1" "$FX_ROOT/wait.txt" || return 0
    sleep 0.1
    attempt=$((attempt + 1))
  done
  die "still showing: $1"
}

wait_viewport() { # <mode> <file>
  local attempt=0
  while [ "$attempt" -lt 100 ]; do
    capture_text "$2"
    node "$SCRIPTS/assert-viewport.mjs" "$2" "$1" >/dev/null 2>&1 && return 0
    sleep 0.1
    attempt=$((attempt + 1))
  done
  node "$SCRIPTS/assert-viewport.mjs" "$2" "$1" 2>&1 | tee -a "$OUT/driver.log"
  die "viewport never became $1"
}

submit() { "$LAB" run "$SESSION" pane run "$PANE" "$1" >/dev/null || die "submit failed: $1"; }
type_text() { "$LAB" run "$SESSION" pane send-text "$PANE" "$1" >/dev/null || die "send-text failed: $1"; }
keys() { "$LAB" run "$SESSION" pane send-keys "$PANE" "$@" >/dev/null || die "send-keys failed: $*"; }

exit_pi() {
  keys ctrl+d
  sleep 1
}

run_turns() {
  wait_for CODEMODE_TEST_READY
  grep -Fq CODEMODE_RENDERER_AVAILABLE "$FX_ROOT/wait.txt" || die "installed Pi lacks registerToolRenderer"
  submit /calm-codemode-baseline
  wait_for BASELINE_FINAL
  submit /calm-codemode-test
  wait_for AFTER_CODEMODE
}

# Hold Pi's /share inside its awaited Radius credential read until the stock-export macrotask has long expired.
delayed_share() { # <fixture> <label> <submit-mode: typed|autocomplete>
  local fx="$FX_ROOT/$1" before after submitted released
  printf '{"_rev":"%s"}\n' "$(now)" > "$fx/agent/auth.json"
  mkdir "$fx/agent/auth.json.lock"
  before=$(find "$fx/shared" -name 'share-*.html' | wc -l | tr -d ' ')
  submitted=$(now)
  if [ "$3" = autocomplete ]; then
    type_text /sha
    wait_for '→ share'
    snapshot "$2-autocomplete-popup" "$2: /sha typed, slash autocomplete open before Enter"
    submitted=$(now)
    keys enter
  else
    submit /share
  fi
  sleep 1.5
  if [ -f "$fx/shared/calls.log" ] && [ -n "$(awk -v t="$submitted" '$1 > t' "$fx/shared/calls.log")" ]; then
    die "$2: share reached gh before the credential lock was released"
  fi
  snapshot "$2-during-held-share" "$2: /share held in awaited credential I/O (stock-export macrotask already expired)"
  released=$(now)
  rmdir "$fx/agent/auth.json.lock"
  local attempt=0
  while [ "$(find "$fx/shared" -name 'share-*.html' | wc -l | tr -d ' ')" -le "$before" ]; do
    [ "$attempt" -lt 150 ] || die "$2: share never produced HTML"
    sleep 0.1
    attempt=$((attempt + 1))
  done
  after=$(find "$fx/shared" -name 'share-*.html' | wc -l | tr -d ' ')
  cp "$fx/shared/share-$before.html" "$OUT/$2.share.html"
  wait_for 'Share URL'
  snapshot "$2-after-share" "$2: after /share completed through the local gh stand-in"
  log "$2: submitted=$submitted lock_released=$released gh_calls=$(awk -v t="$submitted" '$1 > t {printf "%s[%s %s] ", $1, $2, $3}' "$fx/shared/calls.log") shares=$after"
}

wait_file() { # <path>
  local attempt=0
  while [ ! -s "$1" ]; do
    [ "$attempt" -lt 150 ] || die "export never wrote $1"
    sleep 0.1
    attempt=$((attempt + 1))
  done
  wait_for 'Session exported to:'
}

SESSION=$("$LAB" name calm-codemode) || die "lab name failed"
"$LAB" provision "$SESSION" >>"$OUT/driver.log" 2>&1 || { SESSION=; die "lab provision failed"; }
log "provisioned Herdr lab session $SESSION"

# Scenario baseline: Pi with Codemode and no Calm extension at all.
prepare stock none
launch_pi stock
run_turns
snapshot stock-live "No Calm extension: stock Pi Codemode rows"
submit "/export $FX_ROOT/stock/out/stock.html"
wait_file "$FX_ROOT/stock/out/stock.html"
cp "$FX_ROOT/stock/out/stock.html" "$OUT/stock.export.html"
exit_pi
log "stock baseline captured"

# Scenario Calm on from launch: hidden live rows, autocompleted and typed export, delayed share, toggle off and back.
prepare calm-on on
launch_pi calm-on
run_turns
wait_viewport hidden-gapless "$OUT/calm-on-live.txt"
snapshot calm-on-live "Calm on: Codemode script, nested calls and output hidden"
node "$SCRIPTS/assert-viewport.mjs" "$OUT/calm-on-live.txt" hidden-gapless | tee -a "$OUT/driver.log" || die "Calm on leaked Codemode"
session_file=$(find "$FX_ROOT/calm-on/sessions" -name '*.jsonl' -type f | head -1)
cp "$session_file" "$FX_ROOT/calm-on/original.jsonl"
keys ctrl+o
wait_for 'Tool output: expanded'
wait_viewport hidden-gapless "$OUT/calm-on-expanded.txt"
snapshot calm-on-expanded "Calm on after Ctrl+O expansion: Codemode still hidden"
keys ctrl+o
wait_for 'Tool output: collapsed'
type_text /exp
wait_for '→ export'
snapshot calm-on-exp-autocomplete-popup "Calm on: /exp typed, slash autocomplete open before Enter"
keys enter
wait_for 'Session exported to:'
autocomplete_export=$(find "$FX_ROOT/calm-on" -maxdepth 1 -name '*.html' -type f | head -1)
[ -f "$autocomplete_export" ] || die "autocompleted /export wrote no default HTML file in the session cwd"
log "autocompleted /export wrote $(basename "$autocomplete_export")"
cp "$autocomplete_export" "$OUT/calm-on-autocomplete.export.html"
wait_viewport hidden-gapless "$OUT/calm-on-after-autocomplete-export.txt"
snapshot calm-on-after-autocomplete-export "Calm on after autocompleted /export: confirmation shown, Codemode still hidden"
submit "/export $FX_ROOT/calm-on/out/typed.html"
wait_file "$FX_ROOT/calm-on/out/typed.html"
cp "$FX_ROOT/calm-on/out/typed.html" "$OUT/calm-on-typed.export.html"
delayed_share calm-on calm-on-typed-share typed
node "$SCRIPTS/assert-viewport.mjs" "$OUT/calm-on-typed-share-during-held-share.txt" hidden-gapless | tee -a "$OUT/driver.log" || die "held share exposed Codemode"
node "$SCRIPTS/assert-viewport.mjs" "$OUT/calm-on-typed-share-after-share.txt" hidden-gapless | tee -a "$OUT/driver.log" || die "share left Codemode visible"
submit /calm
wait_viewport stock "$OUT/calm-on-toggled-off.txt"
snapshot calm-on-toggled-off "Calm toggled off: stock Codemode script, nested calls and output restored"
delayed_share calm-on calm-off-autocomplete-share autocomplete
submit "/export $FX_ROOT/calm-on/out/calm-off.html"
wait_file "$FX_ROOT/calm-on/out/calm-off.html"
cp "$FX_ROOT/calm-on/out/calm-off.html" "$OUT/calm-off-typed.export.html"
submit /calm
wait_viewport hidden-gapless "$OUT/calm-on-toggled-back.txt"
snapshot calm-on-toggled-back "Calm toggled back on: Codemode hidden again"
cmp "$session_file" "$FX_ROOT/calm-on/original.jsonl" || die "toggles, exports or shares changed the persisted session"
log "calm-on session file unchanged across expansion, toggles, 3 exports and 2 shares"
exit_pi

# Scenario Calm off from launch: live rows identical to no-Calm stock; turning Calm on hides rows built while off.
prepare calm-off off
launch_pi calm-off
run_turns
wait_viewport stock "$OUT/calm-off-live.txt"
snapshot calm-off-live "Calm off from launch: Codemode rows"
submit "/export $FX_ROOT/calm-off/out/calm-off-start.html"
wait_file "$FX_ROOT/calm-off/out/calm-off-start.html"
cp "$FX_ROOT/calm-off/out/calm-off-start.html" "$OUT/calm-off-start.export.html"
submit /calm
wait_viewport hidden "$OUT/calm-off-toggled-on.txt"
snapshot calm-off-toggled-on "Calm off at launch, then /calm on: Codemode rows built while off are hidden"
submit /calm
wait_viewport stock "$OUT/calm-off-toggled-back-off.txt"
snapshot calm-off-toggled-back-off "Calm toggled off again: stock Codemode restored"
exit_pi

# Second no-Calm baseline in a later workspace, so its pane width matches the Calm runs for an exact viewport comparison.
prepare stock2 none
launch_pi stock2
run_turns
snapshot stock2-live "No Calm extension (second baseline): stock Pi Codemode rows"
exit_pi
normalize_viewport() { # <ansi file>
  sed -E 's/[0-9]+ms([^ ]*) */#ms\1/g; s/fm-calm-live\.[A-Za-z0-9]+\/[a-z0-9-]+/FIXTURE/' "$1"
}
if diff <(normalize_viewport "$OUT/stock2-live.ansi") <(normalize_viewport "$OUT/calm-off-live.ansi") > "$OUT/calm-off-vs-stock-viewport.diff"; then
  log "Calm-off live viewport is byte-identical (ANSI colors included) to the no-Calm viewport apart from nested-call durations and fixture path"
else
  die "Calm-off live viewport differs from the no-Calm viewport (see calm-off-vs-stock-viewport.diff)"
fi

node "$SCRIPTS/compare-exports.mjs" "$OUT/stock.export.html" \
  "$OUT/calm-on-autocomplete.export.html" "$OUT/calm-on-typed.export.html" "$OUT/calm-on-typed-share.share.html" \
  "$OUT/calm-off-autocomplete-share.share.html" "$OUT/calm-off-typed.export.html" "$OUT/calm-off-start.export.html" \
  | tee "$OUT/export-share-parity.txt" || die "export/share parity failed"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
  chrome_profile=$(mktemp -d "${TMPDIR:-/tmp}/fm-chrome.XXXXXX")
  for page in "$OUT"/*-live.html "$OUT"/calm-*.html; do
    case "$page" in *.export.html|*.share.html) continue ;; esac
    "$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check --user-data-dir="$chrome_profile" --hide-scrollbars --window-size=1000,760 --screenshot="${page%.html}.png" "file://$page" >/dev/null 2>&1
  done
  for page in "$OUT/stock.export.html" "$OUT/calm-on-autocomplete.export.html" "$OUT/calm-on-typed-share.share.html" "$OUT/calm-off-start.export.html"; do
    "$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check --user-data-dir="$chrome_profile" --hide-scrollbars --window-size=1300,2200 --virtual-time-budget=3000 --screenshot="${page%.html}.png" "file://$page" >/dev/null 2>&1
  done
  rm -rf "$chrome_profile"
fi
log "all live scenarios passed"
