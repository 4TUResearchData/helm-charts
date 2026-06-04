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
- djehuty Deployment with persistent `/data` and in-pod first-time
  `--initialize`.
- Bundled SPARQL store via the
  [`virtuoso`](../virtuoso/README.md) subchart (gated by `virtuoso.enabled`).
  Disable to point at an external SPARQL endpoint via `rdfStore.sparqlUri`.
- Ingress *and* OpenShift Route templates with cert-manager toggles
  (`*.certManager.{clusterIssuer,issuer}`).
- Secret handling that keeps sensitive values out of ConfigMaps:
  `${env:NAME}` and `${file:/path}` references in `config` resolve at
  startup from a chart-rendered or operator-managed Secret.
- OpenShift-friendly defaults (empty `podSecurityContext` /
  `securityContext`); `config.base-url` auto-derives from the enabled
  Route or Ingress.

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
    - configMap: djehuty-menu
      keys: ["menu.json"]
    # Use `secret:` instead of `configMap:` for sensitive fragments
    # (e.g. account lists that include personal data).
```

### Fragment JSON shapes

Each referenced file is a fragment of djehuty's JSON config — same shape
as the chart-rendered `config.json`, just the subtree(s) you want to
merge under the top-level `"djehuty"` key. The shapes below mirror
djehuty's XML config 1:1 via the rules in [Authoring
config](#authoring-config) (`#text` for element bodies, plain scalars
double as XML attributes, repeated elements become JSON arrays).

**`quotas.json`** — default cap plus per-group / per-account overrides
(`default` is the attribute on `<quotas>`; `#text` is each entry's body):

```json
{
  "djehuty": {
    "quotas": {
      "default": "5000000000",
      "group": [
        { "domain": "tudelft.nl", "#text": "50000000000" }
      ],
      "account": [
        { "email": "user@example.org", "#text": "21474836480" }
      ]
    }
  }
}
```

**`privileges.json`** — admin / reviewer flags per account. djehuty
matches accounts by `email` (or `orcid`); `first_name` / `last_name` are
informational:

```json
{
  "djehuty": {
    "privileges": {
      "account": [
        {
          "first_name": "Jane",
          "last_name": "Doe",
          "email": "jane@example.org",
          "orcid": "0000-0000-0000-0001",
          "may-administer": "1",
          "may-run-sparql-queries": "1",
          "may-impersonate": "0",
          "may-review": "1",
          "may-review-quotas": "0"
        }
      ]
    }
  }
}
```

**`menu.json`** — top-nav structure, up to three levels (`primary-menu`
→ `sub-menu` → `sub-sub-menu`). `href` is required on `sub-menu` and
`sub-sub-menu` entries:

```json
{
  "djehuty": {
    "menu": {
      "primary-menu": [
        {
          "title": "About your Data",
          "sub-menu": [
            { "title": "Getting started",  "href": "/info/about-your-data/getting-started" },
            { "title": "Publish and Cite", "href": "/info/about-your-data/publish-cite" }
          ]
        },
        {
          "title": "Collaborations",
          "sub-menu": [
            {
              "title": "Digital Capacity for NES",
              "href":  "https://example.org/digital-capacity/",
              "sub-sub-menu": [
                { "title": "Call 1: Instructors", "href": "https://example.org/digital-capacity/call-1/" },
                { "title": "Call 2: Learners",    "href": "https://example.org/digital-capacity/call-2/" }
              ]
            }
          ]
        }
      ]
    }
  }
}
```

A single fragment may carry multiple top-level sections at once (e.g.
`quotas` + `privileges` in one file) — djehuty merges everything under
`"djehuty"` into the running config.

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

## Bundled Virtuoso

Enabled by default. See the [`virtuoso` chart README](../virtuoso/README.md)
for config, init scripts, and the `.bp` backup restore procedure. Anything
under `virtuoso.*` in values.yaml is passed straight through to the subchart.

When restoring a Virtuoso backup, scale djehuty to zero first so it
doesn't serve SPARQL errors:

```sh
kubectl -n $NS scale deployment <release>-djehuty --replicas=0
# … run the restore on <release>-virtuoso (see virtuoso chart README) …
kubectl -n $NS scale deployment <release>-djehuty --replicas=1
```

To use an external SPARQL store instead:

```
--set virtuoso.enabled=false \
--set rdfStore.sparqlUri=http://your-virtuoso/sparql \
--set rdfStore.stateGraph=https://data.example.com
```

## Authoring config

Everything under `config:` is rendered to `/etc/djehuty/config.json`.
The shape mirrors djehuty's XML config 1:1 — translate any `<el>` from
djehuty's example XML using this table:

| XML                                                           | values.yaml under `config:`                                     |
|---------------------------------------------------------------|-----------------------------------------------------------------|
| `<port>8080</port>`                                           | `port: "8080"`                                                  |
| `<production pre-production="1">1</production>`               | `production: { pre-production: "1", "#text": "1" }`             |
| `<colors><primary-color>#e1670b</primary-color></colors>`     | `colors: { primary-color: "#e1670b" }`                          |
| `<account email="x@y.org">5000000000</account>` (repeated)    | `account: [ { email: "x@y.org", "#text": "5000000000" }, ... ]` |

- `#text` is the element body — use it when an element has attributes
  *and* a text value.
- Repeated elements become a YAML list under that tag.

## Secrets

Short-string secrets go in `secrets.env` (referenced from `config` as
`${env:NAME}`); multi-line secrets (PEMs, certs) go in `secrets.files`
(referenced as `${file:/etc/djehuty/secrets/<filename>}`). djehuty
resolves both at startup.

```yaml
secrets:
  env:
    ORCID_CLIENT_SECRET: "actual-secret-value"
  files:
    repo-key.pem: |
      -----BEGIN PRIVATE KEY-----
      ...

config:
  authentication:
    orcid:
      client-secret: "${env:ORCID_CLIENT_SECRET}"
  repository:
    private-key: "${file:/etc/djehuty/secrets/repo-key.pem}"
```

For production, set `secrets.existingSecret` to a Secret you manage
out-of-band (sealed-secrets, external-secrets-operator, etc.). Its keys
are used verbatim and must match the names listed under `secrets.env` /
`secrets.files` — values there are ignored, only the keys matter. The
chart does not roll the pod when an external Secret rotates; trigger it
with `kubectl rollout restart deployment/<release>-djehuty` or use a
controller like [reloader](https://github.com/stakater/Reloader).

