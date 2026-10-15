#!/usr/bin/env bash
# Drive the base and fixed lab helpers against a fresh Herdr namespace whose default is stopped.
set -u
WT=$1 BASE=$2 H=$3 STATE=$4
export HOME="$H" FM_HERDR_LAB_STATE_DIR="$STATE"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
step() { printf '\n$ %s\n' "$*"; "$@"; printf '[exit %s]\n' "$?"; }
default_row() { "$WT/bin/fm-herdr-lab.sh" run "$1" session list --json | jq -c '.sessions[] | select(.name=="default")'; }
echo "== isolated namespace: HOME=$H (fresh host, default never started)"
echo "== herdr $(herdr --version)"
echo "default before: $(default_row fm-lab-probe)"

echo; echo "######## BEFORE FIX (base fc8972c helper) ########"
NB=$("$BASE/bin/fm-herdr-lab.sh" name fresh-host-base)
step "$BASE/bin/fm-herdr-lab.sh" provision "$NB"
echo "tripwire present? $([ -e "$STATE/$NB.fleet-state.json" ] && echo yes || echo no)"
echo "lab session exists? $("$WT/bin/fm-herdr-lab.sh" run fm-lab-probe session list --json | jq --arg n "$NB" '[.sessions[]|select(.name==$n)]|length')"

echo; echo "######## AFTER FIX (target 0cb7a81 helper) ########"
N=$("$WT/bin/fm-herdr-lab.sh" name fresh-host)
echo "lab session: $N"
step "$WT/bin/fm-herdr-lab.sh" provision "$N"
echo "tripwire: $(cat "$STATE/$N.fleet-state.json")"
echo "sessions while lab runs:"; "$WT/bin/fm-herdr-lab.sh" run "$N" session list --json | jq -c '.sessions[] | {name,default,running}'
step "$WT/bin/fm-herdr-lab.sh" run "$N" workspace create --cwd /tmp --label fm-lab-probe-ws
step "$WT/bin/fm-herdr-lab.sh" run "$N" workspace list
step "$WT/bin/fm-herdr-lab.sh" stop "$N"
echo "default after guarded stop: $(default_row "$N")"
step "$WT/bin/fm-herdr-lab.sh" provision "$N"
step "$WT/bin/fm-herdr-lab.sh" teardown "$N"
echo "tripwire retained? $([ -e "$STATE/$N.fleet-state.json" ] && echo yes || echo no)"
echo "lab session remains? $("$WT/bin/fm-herdr-lab.sh" run fm-lab-probe session list --json | jq --arg n "$N" '[.sessions[]|select(.name==$n)]|length')"
echo "default after teardown: $(default_row fm-lab-probe)"
