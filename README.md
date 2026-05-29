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

Install a chart:

```bash
helm install my-djehuty 4turesearchdata/djehuty
```

## Charts

| Chart | Description |
|---|---|
| djehuty | Djehuty research-data repository (with optional bundled Virtuoso SPARQL store) |

## Source

Chart sources, issues, and contributions:
<https://github.com/4TUResearchData/helm-charts>
