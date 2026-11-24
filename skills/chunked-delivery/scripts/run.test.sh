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
has "unknown command"               2 "usage: run.sh start \[--resume\]" bash "$run" pause

echo "# start"
out=$(bash "$run" start 2>&1)
sees "start reports the checkout"   "run active on $tmp/project" "$out"
sees "start names the writing rule" "^writing: ste100\. Read references/writing.md now" "$out"
mkdir -p docs/review && echo '{"stack":["node"],"writing":"free","workspaces":{".":{}}}' > docs/review/delivery.json
has "a resumed start obeys a free setting" 0 "^writing: free$"   bash "$run" start --resume
rm -r docs
eq  "one marker file"               "$(ls "$DELIVERY_RUN_DIR" | wc -l | tr -d ' ')" 1
marker="$DELIVERY_RUN_DIR/$(ls "$DELIVERY_RUN_DIR")"
eq  "marker names the project"      "$(jq -r .project "$marker")" "$tmp/project"
sees "marker has a run id"          '^[0-9a-f]{12}-[0-9]{8}T[0-9]{6}Z$' "$(jq -r .run "$marker")"
has "status prints the marker"      0 '"project":"'              bash "$run" status
eq  "run_start event"               "$(events | jq -r '.ev')" "run_start"
sees "run_start carries the branch" '^(main|master)$'            "$(events | jq -r '.branch')"

eq  "marker has the mode"           "$(jq -r .mode "$marker")" gated
eq  "marker has the head"           "$(jq -r .head "$marker")" "$(git rev-parse HEAD)"
before=$(cat "$marker")
has "a second start is refused"     2 "a run is active on $tmp/project already" bash "$run" start
has "and says how to go on"         2 "run.sh start --resume"    bash "$run" start
has "start --resume goes on"        0 "run resumed on $tmp/project" bash "$run" start --resume
eq  "and keeps the first marker"    "$(cat "$marker")" "$before"
eq  "and adds no event"             "$(events | wc -l | tr -d ' ')" 1

echo "# mode"
has "mode long"                     0 "^mode: long$"             bash "$run" mode long
eq  "is kept in the marker"         "$(jq -r .mode "$marker")" long
has "an unknown mode"               2 "usage: run.sh mode"       bash "$run" mode fast
bash "$run" mode gated > /dev/null

echo "# status"
bash "$here/mark.sh" phase=implement chunk=1 of=2 name=login risk=low
has "status shows where each chunk is" 0 "^chunk 1/2 — login · low risk · at implement — next: implement, gate, report$" bash "$run" status
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m moved
has "status says when HEAD moved"   0 "^HEAD moved since the run started" bash "$run" status

echo "# a project with a quote in its path"
mkdir -p "$tmp/odd \"dir" && (cd "$tmp/odd \"dir" && git init -q && bash "$run" start > /dev/null && bash "$run" status > "$tmp/odd.out")
sees "the marker is still JSON"     'odd \\"dir' "$(cat "$tmp/odd.out")"
(cd "$tmp/odd \"dir" && bash "$run" stop > /dev/null)

echo "# from a subdirectory"
mkdir -p deep/er
has "status finds the same run"     0 '"project":"'              bash -c "cd deep/er && bash '$run' status"

echo "# stop"
has "stop reports the checkout"     0 "run ended on $tmp/project" bash "$run" stop
eq  "marker is gone"                "$(ls "$DELIVERY_RUN_DIR")" ""
mkdir "$tmp/bin" && for tool in bash git dirname basename shasum cut node; do ln -s "$(command -v "$tool")" "$tmp/bin/$tool"; done
has "no jq: no run starts"          2 "jq is not on PATH"        env PATH="$tmp/bin" bash "$run" start
eq  "run_stop event"                "$(events | tail -1 | jq -r '.ev')" "run_stop"
has "status exits 1 again"          1 "no run on"                bash "$run" status
has "stop without a run is fine"    0 "run ended on"             bash "$run" stop

finish
