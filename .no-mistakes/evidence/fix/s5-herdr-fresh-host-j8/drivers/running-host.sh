#!/usr/bin/env bash
# Exercise the real host namespace's running default only through named fm-lab-* sessions.
set -u
WT=$1 BASE=$2 STATE=$3
export FM_HERDR_LAB_STATE_DIR="$STATE"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
LAB="$WT/bin/fm-herdr-lab.sh"
step() { printf '\n$ %s\n' "$*"; "$@"; printf '[exit %s]\n' "$?"; }
default_row() { "$LAB" run fm-lab-probe session list --json | jq -c '.sessions[] | select(.name=="default") | {name,default,running,socket_path}'; }
lab_count() { "$LAB" run fm-lab-probe session list --json | jq --arg n "$1" '[.sessions[]|select(.name==$n)]|length'; }
echo "== real host namespace (captain shape: running default); lab work only on fm-lab-* sessions"
BEFORE=$(default_row); echo "default before: $BEFORE"

echo; echo "######## A. target helper, running default, full lifecycle ########"
N=$("$LAB" name running-host)
step "$LAB" provision "$N"
echo "tripwire: $(cat "$STATE/$N.fleet-state.json")"
step "$LAB" run "$N" workspace list
step "$LAB" stop "$N"
step "$LAB" provision "$N"
step "$LAB" teardown "$N"
echo "tripwire retained? $([ -e "$STATE/$N.fleet-state.json" ] && echo yes || echo no); lab sessions named $N: $(lab_count "$N")"

echo; echo "######## B. tripwire written by base fc8972c helper, torn down by target helper ########"
N=$("$BASE/bin/fm-herdr-lab.sh" name helper-update)
step "$BASE/bin/fm-herdr-lab.sh" provision "$N"
echo "base-written tripwire: $(cat "$STATE/$N.fleet-state.json")"
step "$LAB" teardown "$N"
echo "tripwire retained? $([ -e "$STATE/$N.fleet-state.json" ] && echo yes || echo no); lab sessions named $N: $(lab_count "$N")"

AFTER=$(default_row); echo; echo "default after:  $AFTER"
[ "$BEFORE" = "$AFTER" ] && echo "host default unchanged: yes" || echo "host default unchanged: NO"
