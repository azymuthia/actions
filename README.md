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

## Versioning

Consumers pin the `v1` tag, which moves to the latest compatible commit.
