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

## Reference deployments

Three complete `-f` values files cover the shapes you'll actually
encounter: [`examples/local-dev/`](./examples/local-dev/values.yaml),
[`examples/staging/`](./examples/staging/values.yaml), and
[`examples/production-external-secrets/`](./examples/production-external-secrets/values.yaml).
See [`examples/README.md`](./examples/README.md) for which to pick.

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

## Side-loaded config fragments

djehuty's bare-VM config supports `<include>...</include>` directives that
pull additional XML files into the running configuration. The chart's
equivalent is `config.includes:` — a list of references to existing
ConfigMaps or Secrets in the release namespace. Each entry mounts the
referenced resource under `/etc/djehuty/config.d/<refName>/` and emits one
`include:` entry per listed key into the rendered `config.json`; djehuty
walks those entries at startup and merges the referenced files into the
running config.

Use this for data that changes outside chart releases — operator-managed
quotas/privileges (often regenerated nightly), branding snippets, menu
fragments — so the values file stays static.

```yaml
config:
  includes:
    - configMap: djehuty-quotas       # mounted at /etc/djehuty/config.d/djehuty-quotas/
      keys: ["quotas.json"]           # required: explicit list of keys to project
    - configMap: djehuty-privileges
      keys: ["privileges.json"]
    - secret: djehuty-branding        # `secret:` instead of `configMap:` for sensitive fragments
      keys: ["branding.json", "menu.json"]
```

Each referenced file should be valid djehuty JSON config (same shape as
the chart's rendered `config.json`, just the subtree you want to merge).
Example `quotas.json`:

```json
{
  "djehuty": {
    "quotas": {
      "default": "5000000000",
      "account": [
        { "email": "user@example.org", "#text": "21474836480" }
      ]
    }
  }
}
```

Notes:

- **The chart does not create the referenced ConfigMap/Secret.** Manage
  them out-of-band (`kubectl apply -f`, sealed-secrets,
  external-secrets-operator, an operator-side nightly export job, etc.).
- `keys:` is required and explicit so the chart renders fully at
  template time — no cluster round-trip via Helm `lookup`. Each key
  becomes one file mount and one `include:` entry, in list order.
- Set either `configMap:` or `secret:`, not both. Set at least one.
- Rotation: bump the data inside the ConfigMap/Secret, then
  `kubectl rollout restart deployment/<release>-djehuty`. The deployment's
  `checksum/config` annotation tracks chart-rendered config only, not
  side-loaded fragments.

## Disable bundled Virtuoso

If you already run a SPARQL store elsewhere, disable the subchart and
point djehuty at it:

```
--set virtuoso.enabled=false \
--set rdfStore.sparqlUri=http://your-virtuoso/sparql \
--set rdfStore.stateGraph=https://data.example.com
```

(`rdfStore.sparqlUpdateUri` defaults to `sparqlUri` when omitted.)

## Authoring config

Everything under `config:` in values.yaml is serialized to JSON and
shipped as `/etc/djehuty/config.json`. djehuty's JSON parser
(`src/djehuty/web/config/json_parser.py`) wraps each dict into a node
that exposes both attribute-style and child-element-style access — the
same shape its XML parser sees — so the mapping from XML to JSON is
mechanical.

Four shapes cover essentially everything in a real config:

| XML                                                           | values.yaml under `config:`                                                                                       |
|---------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| `<port>8080</port>`                                           | `port: "8080"`                                                                                                    |
| `<production pre-production="1">1</production>`               | `production: { pre-production: "1", "#text": "1" }`                                                               |
| `<colors><primary-color>#e1670b</primary-color></colors>`     | `colors: { primary-color: "#e1670b" }`                                                                            |
| `<account email="x@y.org">5000000000</account>` (repeated)    | `account: [ { email: "x@y.org", "#text": "5000000000" }, ... ]`                                                   |

Rules:

- **`#text`** is the element body. Use it whenever an element has both
  attributes and a text value (`<el attr="...">body</el>`).
- **Plain scalar keys** under a dict become both XML attributes *and*
  child elements with that key as the tag. So `pre-production: "1"`
  inside `production:` shows up as `<production pre-production="1">` for
  attribute reads and as `<production><pre-production>1</pre-production></production>`
  for child-element reads. Practical effect: you can almost always write
  scalar keys directly without the `@` prefix or `#text` mechanics.
- **`@`-prefixed keys** (e.g. `"@email": "x@y.org"`) are the explicit
  attribute form. Kept for back-compat; prefer the plain-scalar form
  above unless the same key needs to coexist with a non-attribute child.
- **YAML lists** under a key (`account: [ {...}, {...} ]`) become
  repeated child elements with that key as the tag — one per list entry.

The chart's defaults already use this convention
(`cache-root: { clear-on-start: "1", "#text": "/data/cache" }` →
`<cache-root clear-on-start="1">/data/cache</cache-root>`). Verified
end-to-end against `json_parser.py`.

> [!NOTE]
> XML config (`config-file foo.xml`) is **deprecated upstream** —
> djehuty will remove XML support in December 2026. This chart only
> emits JSON, so nothing to do.

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

### Where files end up in the pod

The chart mounts the secret (rendered or existing) at
`/etc/djehuty/secrets/`, read-only. **Each key in the Secret becomes a
file at `/etc/djehuty/secrets/<key>`** — that's the path you reference
with `${file:/etc/djehuty/secrets/<key>}` from `config`. The mapping is:

| values.yaml                                         | Secret key            | Pod path                                       |
|-----------------------------------------------------|-----------------------|------------------------------------------------|
| `secrets.files.saml-sp-cert.pem`                    | `saml-sp-cert.pem`    | `/etc/djehuty/secrets/saml-sp-cert.pem`        |
| `secrets.env.ORCID_CLIENT_SECRET`                   | `ORCID_CLIENT_SECRET` | (env var, not a file)                          |

When `secrets.existingSecret` is set the chart doesn't rewrite key names
— your Secret's keys are used as filenames verbatim. So if your
out-of-band Secret has a key named `saml-sp-cert.pem`, it shows up at
`/etc/djehuty/secrets/saml-sp-cert.pem` and
`${file:/etc/djehuty/secrets/saml-sp-cert.pem}` resolves to its
contents at djehuty startup.

### Rotation

```sh
# 1. Update the Secret (sealed-secrets re-render, external-secrets sync,
#    kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -, …)
# 2. Roll the pod so the new file contents are read at startup:
kubectl rollout restart deployment/<release>-djehuty
```

Helm's `checksum/secret` annotation only tracks chart-rendered Secrets.
When `existingSecret` is set, the chart cannot observe content changes
and will not roll the pod automatically — use the manual restart above,
or run a controller like
[reloader](https://github.com/stakater/Reloader) that watches Secrets
and triggers rollouts.

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
