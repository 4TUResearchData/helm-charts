# 4TU.ResearchData Helm Charts

Helm chart repository for [4TU.ResearchData](https://data.4tu.nl/) services.

> **Development phase.** These charts are pre-release and under active
> development. Defaults, values schema, and template layout may change
> without notice between releases. Pin to a specific chart version and
> review the diff before upgrading.

## Usage

[Helm](https://helm.sh) must be installed. See the
[Helm docs](https://helm.sh/docs) to get started.

Add this repository:

```bash
helm repo add 4turesearchdata https://4turesearchdata.github.io/helm-charts
helm repo update
```

Search for available charts:

```bash
helm search repo 4turesearchdata
```

Install the djehuty stack (with bundled Virtuoso):

```bash
helm install my-djehuty 4turesearchdata/djehuty
```

Install Virtuoso standalone:

```bash
helm install my-sparql 4turesearchdata/virtuoso
```

## Charts

| Chart | Description |
|---|---|
| djehuty | Djehuty research-data repository. Depends on `virtuoso` (bundled by default, gated by `virtuoso.enabled`). |
| virtuoso | OpenLink Virtuoso (open-source) SPARQL/RDF triple store. Installable standalone or as the djehuty subchart. |

## Source

Chart sources, issues, and contributions:
<https://github.com/4TUResearchData/helm-charts>
