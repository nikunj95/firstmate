#!/usr/bin/env bash
# Flip a disposable namespace's own default between stopped and running mid-lab and confirm the tripwire fails closed.
set -u
WT=$1 H=$2 STATE=$3
export HOME="$H" FM_HERDR_LAB_STATE_DIR="$STATE"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
LAB="$WT/bin/fm-herdr-lab.sh"
step() { printf '\n$ %s\n' "$*"; "$@"; printf '[exit %s]\n' "$?"; }
default_row() { "$LAB" run fm-lab-probe session list --json | jq -c '.sessions[] | select(.name=="default") | {name,default,running,socket_path}'; }
lab_row() { "$LAB" run fm-lab-probe session list --json | jq -c --arg n "$1" '[.sessions[] | select(.name==$n) | {name,running}]'; }
wait_default() { local i; for i in $(seq 1 100); do [ "$("$LAB" run fm-lab-probe session list --json | jq -r '.sessions[]|select(.name=="default")|.running')" = "$1" ] && return 0; sleep 0.2; done; return 1; }
start_fixture_default() { (cd "$H" && exec nohup herdr server >"$H/fixture-default.log" 2>&1) & DPID=$!; wait_default true && echo "fixture default started in $H (pid $DPID)"; }
stop_fixture_default() { kill "$DPID"; wait "$DPID" 2>/dev/null; wait_default false && echo "fixture default pid $DPID ended"; }

echo "== disposable namespace HOME=$H; only its own default is flipped, never the host default"
echo "default: $(default_row)"

echo; echo "######## A. stopped baseline, default starts during lab work ########"
N=$("$LAB" name stopped-flip)
step "$LAB" provision "$N"
echo "tripwire: $(cat "$STATE/$N.fleet-state.json")"
step "$LAB" stop "$N"
start_fixture_default
echo "default now: $(default_row)"
step "$LAB" provision "$N"
echo "lab after refused restart: $(lab_row "$N")"
step "$LAB" teardown "$N"
echo "tripwire retained as evidence? $([ -e "$STATE/$N.fleet-state.json" ] && echo yes || echo no)"
stop_fixture_default
echo "default restored: $(default_row)"
step "$LAB" teardown "$N"
echo "tripwire retained? $([ -e "$STATE/$N.fleet-state.json" ] && echo yes || echo no); lab: $(lab_row "$N")"

echo; echo "######## B. running baseline, default stops during lab work ########"
start_fixture_default
N=$("$LAB" name running-flip)
step "$LAB" provision "$N"
echo "tripwire: $(cat "$STATE/$N.fleet-state.json")"
stop_fixture_default
echo "default now: $(default_row)"
step "$LAB" teardown "$N"
echo "tripwire retained as evidence? $([ -e "$STATE/$N.fleet-state.json" ] && echo yes || echo no); lab: $(lab_row "$N")"
start_fixture_default
step "$LAB" teardown "$N"
echo "tripwire retained? $([ -e "$STATE/$N.fleet-state.json" ] && echo yes || echo no)"
stop_fixture_default
echo "final default: $(default_row)"
echo "final sessions: $("$LAB" run fm-lab-probe session list --json | jq -c '[.sessions[].name]')"
