# djehuty Helm chart

Helm chart for deploying [djehuty](https://github.com/4TUResearchData/djehuty)
on Kubernetes / OpenShift.

This chart lives in [4TUResearchData/helm-charts](https://github.com/4TUResearchData/helm-charts);
see the top-level [README](../../README.md) for the chart repo overview and
the [CONTRIBUTING guide](../../CONTRIBUTING.md) for local development.

> [!WARNING]
> **Development phase.** This chart is pre-1.0 and under active
> development. Values, templates, and defaults may change between commits.
> Pin to a specific version and review release notes before upgrading.

Features:
- djehuty Deployment with persistent `/data`, in-pod first-time
  `--initialize`, configurable site/auth/storage via plain JSON.
- Bundled SPARQL store via the
  [`virtuoso`](https://github.com/4TUResearchData/helm-charts/tree/main/charts/virtuoso)
  subchart (gated by `virtuoso.enabled`). djehuty's `rdf-store.sparql-uri`
  auto-derives from the subchart's Service. Disable to point at an
  externally-managed Virtuoso (or any other SPARQL endpoint) via
  `rdfStore.sparqlUri`.
- Ingress *and* OpenShift Route templates with matching cert-manager
  toggles (`*.certManager.{clusterIssuer,issuer}`), mutually optional.
- Secret handling that keeps sensitive values out of ConfigMaps:
  `${env:NAME}` and `${file:/path}` references in `config` are resolved at
  djehuty startup from the chart-rendered Secret.
- OpenShift-friendly defaults: empty `podSecurityContext` /
  `securityContext` so SCC controls UID/fsGroup; `/data` group-owned by
  GID 0 in the Dockerfile so the random assigned UID can write.
- `config.base-url` auto-derives from the enabled Route or Ingress
  (https when TLS is configured) — one less knob.

## Test against this branch

1. Build a local djehuty image from the current source tree:

   ```
   docker build -t djehuty:dev -f docker/Dockerfile .
   ```

2. Load it into your local cluster:

   | Cluster         | Command                                          |
   |-----------------|--------------------------------------------------|
   | Docker Desktop  | (nothing — local images are already visible)     |
   | kind            | `kind load docker-image djehuty:dev`             |
   | minikube        | `minikube image load djehuty:dev`                |
   | k3d             | `k3d image import djehuty:dev`                   |

3. Pull the virtuoso subchart, then install:

   ```
   helm dependency update ./charts/djehuty
   helm install djehuty ./charts/djehuty \
     --set image.pullPolicy=Never
   ```

4. Reach it:

   ```
   kubectl port-forward svc/djehuty-djehuty 8080:8080
   open http://localhost:8080
   ```

## Disable bundled Virtuoso

If you already run a SPARQL store elsewhere, disable the subchart and
point djehuty at it:

```
--set virtuoso.enabled=false \
--set rdfStore.sparqlUri=http://your-virtuoso/sparql \
--set rdfStore.stateGraph=https://data.example.com
```

(`rdfStore.sparqlUpdateUri` defaults to `sparqlUri` when omitted.)

## Secrets

Short-string secrets go in `secrets.env` and are referenced from `config` via
`${env:NAME}`. Multi-line secrets (PEMs, certs) go in `secrets.files` and are
referenced via `${file:/etc/djehuty/secrets/<filename>}`. The JSON config
parser resolves both at startup.

Example:

```
secrets:
  env:
    ORCID_CLIENT_SECRET: "actual-secret-value"
  files:
    repo-key.pem: |
      -----BEGIN PRIVATE KEY-----
      ...
      -----END PRIVATE KEY-----

config:
  authentication:
    orcid:
      client-secret: "${env:ORCID_CLIENT_SECRET}"
  repository:
    private-key: "${file:/etc/djehuty/secrets/repo-key.pem}"
```

For production, prefer external secret management (sealed-secrets,
external-secrets-operator, etc.) over committing values into `values.yaml`.

### Using an existing Secret

To skip the chart-rendered Secret entirely, set `secrets.existingSecret` to
the name of a Secret you create out-of-band:

```yaml
secrets:
  existingSecret: djehuty-prod-creds   # must already exist in the namespace
  env:
    ORCID_CLIENT_SECRET: ""            # keys still listed; values ignored
  files:
    repo-key.pem: ""                   # filenames still listed; contents ignored
```

The chart wires the pod to your Secret:

- For every key under `secrets.env`, an env var of the same name is bound
  via `secretKeyRef` to the matching key in `<existingSecret>`.
- The Secret is also mounted at `/etc/djehuty/secrets/`, so every
  filename under `secrets.files` resolves as
  `${file:/etc/djehuty/secrets/<filename>}`.

Your Secret must therefore contain a key for every `${env:NAME}` reference
in `config`, and a key (used as filename) for every
`${file:/etc/djehuty/secrets/<filename>}` reference. The chart does not
verify this; missing keys surface at pod startup.

Helm does not roll the deployment when an external Secret rotates — use
your secret-management tool's own rotation hook (reloader, etc.) or
`kubectl rollout restart`.

## Restoring a Virtuoso backup

The native `.bp` checkpoint restore flow now lives in the
[`virtuoso` chart](../virtuoso/README.md#restoring-a-backup) — including
the operator procedure, file-naming heuristic, troubleshooting, and the
toggle to disable it.

The only djehuty-specific step is **scale djehuty to zero first** so it
doesn't serve SPARQL errors during the restore:

```sh
kubectl -n $NS scale deployment <release>-djehuty --replicas=0
# … run the restore procedure on <release>-virtuoso …
kubectl -n $NS scale deployment <release>-djehuty --replicas=1
```

A fresh djehuty pod reads from the restored Virtuoso on startup; no
cache-bust is needed.

To disable the restore initContainer in the bundled Virtuoso, pass the
subchart toggle through:

```yaml
virtuoso:
  restore:
    enabled: false
```
