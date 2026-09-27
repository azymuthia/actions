#!/usr/bin/env bash
# Fails when any service in a Swarm stack ended its last update paused or
# rolled back. Run it after `docker stack deploy --detach=false`, which waits
# for the update but still exits 0 when Swarm rolled it back.
set -euo pipefail

stack=${1:?usage: verify.sh <stack>}

services=$(docker stack services --format '{{.Name}}' "$stack")
if [ -z "$services" ]; then
  echo "::error::stack $stack has no services - is the stack name right?"
  exit 1
fi

failed=0
for service in $services; do
  # UpdateStatus is absent on a service that has only ever been created.
  state=$(docker service inspect --format '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{end}}' "$service")
  case "$state" in
    paused|rollback_started|rollback_paused|rollback_completed)
      message=$(docker service inspect --format '{{.UpdateStatus.Message}}' "$service")
      echo "::error::$service: update $state: $message"
      echo "Most recent stopped tasks of $service:"
      docker service ps --no-trunc --filter desired-state=shutdown \
        --format '  {{.Name}} {{.Image}} {{.Error}}' "$service" | head -n 5 || true
      failed=1
      ;;
    *)
      echo "$service: ${state:-created}"
      ;;
  esac
done

exit "$failed"
