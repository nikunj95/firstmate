#!/usr/bin/env bash
# Confirm pre-existing refuse-default guards still refuse in a stopped-default namespace.
set -u
WT=$1 H=$2 STATE=$3
export HOME="$H" FM_HERDR_LAB_STATE_DIR="$STATE"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
LAB="$WT/bin/fm-herdr-lab.sh"
step() { printf '\n$ %s\n' "${*#$WT/}"; "$@"; printf '[exit %s]\n' "$?"; }
default_row() { "$LAB" run fm-lab-probe session list --json | jq -c '.sessions[] | select(.name=="default") | {name,default,running}'; }
echo "default before: $(default_row)"
step "$LAB" provision default
step "$LAB" prepare default
step "$LAB" stop default
step "$LAB" teardown default
step "$LAB" viewer start default
step "$LAB" run default workspace list
step "$LAB" run fm-lab-guard workspace list --session default
step "$LAB" run fm-lab-guard --session default server
step "$LAB" run fm-lab-guard server
step "$LAB" run fm-lab-guard server stop
step "$LAB" run fm-lab-guard session stop default
step "$LAB" run fm-lab-guard session delete default
step "$LAB" stop fm-lab-never-provisioned
step "$LAB" teardown fm-lab-never-provisioned
echo; echo "default after: $(default_row)"
echo "sessions: $("$LAB" run fm-lab-probe session list --json | jq -c '[.sessions[].name]')"
echo "tripwires created: $(ls "$STATE" | wc -l | tr -d ' ')"
