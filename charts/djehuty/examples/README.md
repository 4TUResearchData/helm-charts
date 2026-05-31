# djehuty chart — reference deployments

Three values files covering the shapes you'll actually encounter. Each
is a complete, working `-f` input — pick the one closest to your
environment and adapt.

| Example                                                         | Shape                                                                                                       | Secrets                              | Use when…                                                          |
|-----------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|--------------------------------------|--------------------------------------------------------------------|
| [`local-dev/`](./local-dev/values.yaml)                         | Smallest viable. Bundled Virtuoso, no Ingress/Route, port-forward access.                                   | Inline (single-operator dev cluster) | Local kind/minikube/Docker Desktop tinkering.                      |
| [`staging/`](./staging/values.yaml)                             | OpenShift Route with cert-manager edge TLS, bundled Virtuoso, chart-rendered Secret with test credentials.  | Inline (acceptable for pre-prod)     | Pre-production environments you own end-to-end.                    |
| [`production-external-secrets/`](./production-external-secrets/values.yaml) | `existingSecret:` + `config.includes:` for operator-managed quotas/privileges; SAML 2.0 SSO wiring.       | External (sealed-secrets / ESO / SOPS) | Production. The only shape for shared / multi-operator clusters. |

The production example ships with two companion ConfigMap templates
(`configmap-quotas.example.yaml`, `configmap-privileges.example.yaml`)
showing the JSON shape djehuty expects for side-loaded fragments. The
chart does **not** apply them — they're owned by the operator and
typically regenerated nightly from the source-of-truth quota database.

See the main [`README.md`](../README.md) for chart features,
the [`Authoring config`](../README.md#authoring-config) section for the
`#text` / attribute convention, and
[`Side-loaded config fragments`](../README.md#side-loaded-config-fragments)
for the `config.includes:` mechanism.
