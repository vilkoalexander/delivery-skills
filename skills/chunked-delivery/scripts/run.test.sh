#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
run="$here/run.sh"

new_repo project
echo x > a.txt && commit_all
events() { cat "$DELIVERY_EVENTS_DIR"/*.jsonl 2>/dev/null; }

echo "# no run"
has "status exits 1"                1 "no run on $tmp/project"   bash "$run" status
has "status is the default command" 1 "no run on"                bash "$run"
has "unknown command"               2 "usage: run.sh start\|stop\|status" bash "$run" pause

echo "# start"
has "start reports the checkout"    0 "run active on $tmp/project" bash "$run" start
eq  "one marker file"               "$(ls "$DELIVERY_RUN_DIR" | wc -l | tr -d ' ')" 1
marker="$DELIVERY_RUN_DIR/$(ls "$DELIVERY_RUN_DIR")"
eq  "marker names the project"      "$(jq -r .project "$marker")" "$tmp/project"
sees "marker has a run id"          '^[0-9a-f]{12}-[0-9]{8}T[0-9]{6}Z$' "$(jq -r .run "$marker")"
has "status prints the marker"      0 '"project":"'              bash "$run" status
eq  "run_start event"               "$(events | jq -r '.ev')" "run_start"
sees "run_start carries the branch" '^(main|master)$'            "$(events | jq -r '.branch')"

before=$(cat "$marker")
has "second start is harmless"      0 "run active on"            bash "$run" start
eq  "and keeps the first marker"    "$(cat "$marker")" "$before"
eq  "and adds no event"             "$(events | wc -l | tr -d ' ')" 1

echo "# from a subdirectory"
mkdir -p deep/er
has "status finds the same run"     0 '"project":"'              bash -c "cd deep/er && bash '$run' status"

echo "# stop"
has "stop reports the checkout"     0 "run ended on $tmp/project" bash "$run" stop
eq  "marker is gone"                "$(ls "$DELIVERY_RUN_DIR")" ""
eq  "run_stop event"                "$(events | tail -1 | jq -r '.ev')" "run_stop"
has "status exits 1 again"          1 "no run on"                bash "$run" status
has "stop without a run is fine"    0 "run ended on"             bash "$run" stop

finish
