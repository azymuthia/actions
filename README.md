# azymuthia/actions

Shared GitHub Actions for the azymuthia organisation.

This repository is **public on purpose**. The organisation is on the GitHub
Free plan, where an action stored in a private repository cannot be used by
other repositories — a workflow referencing it fails with "repository not
found". Making this repository public is what allows the private application
repositories to consume these actions.

Nothing here is a secret. Every action takes its credentials and its
environment as inputs at call time; there are no site-specific defaults.

## `registry-login`

Logs the runner's Docker daemon in to a container registry using credentials
held in Doppler.

```yaml
- name: Log in to the registry
  uses: azymuthia/actions/registry-login@v1
  with:
    registry: registry.example.com
    doppler-token: ${{ secrets.DOPPLER_INFRA_TOKEN }}
    project: infrastructure
    config: prd
```

| Input | Required | Default | Notes |
|---|---|---|---|
| `registry` | yes | — | Registry hostname |
| `doppler-token` | yes | — | Service token for the config below |
| `project` | yes | — | Doppler project |
| `config` | yes | — | Doppler config |
| `username-secret` | no | `REGISTRY_USERNAME` | Doppler secret name |
| `password-secret` | no | `REGISTRY_PASSWORD` | Doppler secret name |

### Why not a local composite action

`uses: ./.github/actions/...` resolves against the workspace, so it requires
`actions/checkout` in every job that calls it. The deploy workflows that use
this action deliberately do not check out — they build from
`docker/build-push-action`'s Git context — so a local action would mean adding
a checkout to every one of them.

### Call it in every job that needs it

Docker credentials live in the daemon's config on the runner, so a login in
one job is not guaranteed to be visible to the next. Call this in each job
that pushes, pulls, or runs `docker stack deploy --with-registry-auth`.

## `stack-verify`

Fails the job when any service in a Docker Swarm stack ended its last update
paused or rolled back. Call it right after the deploy, and give the job a
timeout, because `--detach=false` waits for the stack to converge:

```yaml
deploy:
  runs-on: kiribati
  timeout-minutes: 15
  steps:
    - name: Deploy stack
      run: docker stack deploy --detach=false --with-registry-auth -c docker-compose.prod.yaml "$STACK_NAME"

    - name: Verify stack
      uses: azymuthia/actions/stack-verify@v1
      with:
        stack: ${{ env.STACK_NAME }}
```

| Input | Required | Default | Notes |
|---|---|---|---|
| `stack` | yes | — | Stack name, as passed to `docker stack deploy` |

It fails on a stack with no services too, which usually means a wrong name.
The runner has to be a Swarm manager, which it already is if it can deploy.

### Why `--detach=false` alone is not enough

Without `--detach=false`, `docker stack deploy` returns as soon as the update
is submitted, and nothing waits for the result. With it, the command waits,
and it exits non-zero when an update **pauses** (`failure_action: pause`). But
when Swarm **rolls back** (`failure_action: rollback`), it prints a `rollback`
line and exits **0** once the old tasks are running again. The run stays green
while the new image never started. docker/cli
`cli/command/service/progress/progress.go::ServiceProgress` treats
`rollback_completed` as a message, not an error.

This action reads each service's `UpdateStatus.State` afterwards and fails on
`paused`, `rollback_started`, `rollback_paused` or `rollback_completed`. It
prints Swarm's message and the service's most recent stopped tasks, with their
errors. `stack-verify/test/run.sh` proves both behaviours on a real swarm. The
`Test stack-verify` workflow runs it.

### Known edge case

It checks every service in the stack, not only the ones this deploy updated.
Say a service's update rolled back, and its compose entry was later reverted
to the spec it rolled back to. Then the next deploy doesn't touch that service,
and it still reports `rollback_completed`. Clear that with
`docker service update --force <service>`.

## Versioning

Consumers pin the `v1` tag, which moves to the latest compatible commit.
