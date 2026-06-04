# helm-charts

Helm charts for [4TU.ResearchData](https://data.4tu.nl).

## Usage

[Helm](https://helm.sh) must be installed to use the charts. Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

```bash
helm repo add 4turesearchdata https://4turesearchdata.github.io/helm-charts
```

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages. You can then run `helm search repo
4turesearchdata` to see the charts.

## Charts

You can search all 4TU.ResearchData charts using the following command:

```bash
helm search repo 4turesearchdata
```

## Contributing

See https://github.com/4TUResearchData/helm-charts
