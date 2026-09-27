#!/usr/bin/env bash
# Self-test for verify.sh. Needs a Docker daemon that is a Swarm manager
# (`docker swarm init`). Leaves two stacks behind for the workflow to call the
# action against: sv-good (last update completed) and sv-rollback (last update
# rolled back).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
verify="$here/../verify.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

# deploy <stack> <failure_action> <ok|crash> <revision>
# Prints the deploy output and returns docker stack deploy's exit code.
deploy() {
  local command='exec tail -f /dev/null'
  [ "$3" = crash ] && command='exit 1'
  cat > "$work/$1.yaml" <<EOF
services:
  app:
    image: alpine:3.22
    command: ["sh", "-c", "$command"]
    environment:
      REVISION: "$4"
    stop_grace_period: 1s
    deploy:
      replicas: 1
      restart_policy:
        condition: any
        delay: 1s
      update_config:
        failure_action: $2
        monitor: 5s
      rollback_config:
        monitor: 5s
EOF
  docker stack deploy --detach=false -c "$work/$1.yaml" "$1" 2>&1
}

echo "--- good: create, then a healthy update"
deploy sv-good rollback ok 1 >/dev/null
deploy sv-good rollback ok 2 >/dev/null
"$verify" sv-good || fail "verify failed on a completed update"

echo "--- rollback: a crashing update with failure_action rollback"
deploy sv-rollback rollback ok 1 >/dev/null
set +e
out=$(deploy sv-rollback rollback crash 2); status=$?
set -e
echo "$out" | tail -n 5
[ "$status" -eq 0 ] || fail "docker stack deploy --detach=false exited $status on a rollback; the premise is wrong, the flag alone would do"
echo "docker stack deploy exited 0 after the rollback, as expected"
if out=$("$verify" sv-rollback); then fail "verify passed a rolled-back update"; fi
echo "$out"
echo "$out" | grep -q 'rollback_completed' || fail "verify did not report rollback_completed"

echo "--- paused: a crashing update with failure_action pause"
deploy sv-paused pause ok 1 >/dev/null
set +e
out=$(deploy sv-paused pause crash 2); status=$?
set -e
echo "$out" | tail -n 3
[ "$status" -ne 0 ] || fail "docker stack deploy --detach=false exited 0 on a paused update"
echo "docker stack deploy exited $status on the paused update, as expected"
if out=$("$verify" sv-paused); then fail "verify passed a paused update"; fi
echo "$out"
echo "$out" | grep -q 'update paused' || fail "verify did not report the paused update"

echo "--- empty: a stack name with no services"
if "$verify" sv-nonexistent; then fail "verify passed a stack with no services"; fi

echo "PASS"
