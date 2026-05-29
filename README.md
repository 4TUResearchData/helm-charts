# 4TU.ResearchData Helm Charts

Helm charts maintained by [4TU.ResearchData](https://data.4tu.nl/) for
deploying our open-source research-data services on Kubernetes and OpenShift.

> [!WARNING]
> **Development phase.** These charts are under active development and have
> not yet had a stable release. Defaults, values schema, and template layout
> may change without notice between commits. Pin to a specific chart version
> and review the diff before upgrading. Production use is at your own risk.

## Charts

| Chart | Description |
|---|---|
| [djehuty](charts/djehuty) | Djehuty research-data repository. Depends on `virtuoso` (bundled by default, gated by `virtuoso.enabled`). |
| [virtuoso](charts/virtuoso) | OpenLink Virtuoso (open-source) SPARQL/RDF triple store. Installable standalone or as the djehuty subchart. |

## Usage

Add the repository (once it is published):

```sh
helm repo add 4turesearchdata https://4turesearchdata.github.io/helm-charts
helm repo update
```

Install the djehuty stack (with bundled Virtuoso):

```sh
helm install my-djehuty 4turesearchdata/djehuty
```

Install Virtuoso standalone:

```sh
helm install my-sparql 4turesearchdata/virtuoso
```

Use an external SPARQL store instead of the bundled one:

```sh
helm install my-djehuty 4turesearchdata/djehuty \
  --set virtuoso.enabled=false \
  --set rdfStore.sparqlUri=https://sparql.example.com/sparql
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Code of Conduct, governance, and
the security disclosure process are inherited from the parent
[djehuty](https://github.com/4TUResearchData/djehuty) project.

## License

MIT — see [LICENSE](LICENSE).
