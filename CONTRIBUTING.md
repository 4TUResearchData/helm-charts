# Contributing

This repository inherits the contribution guidelines of the parent
[djehuty](https://github.com/4TUResearchData/djehuty) project — please
read those first:

<https://github.com/4TUResearchData/djehuty/blob/main/CONTRIBUTING.md>

The notes below cover only the bits that are specific to working on
Helm charts in this repo.

## Local development

You will need:

- [Helm](https://helm.sh/docs/intro/install/) ≥ 3.12
- [just](https://github.com/casey/just) — task runner used by all recipes
- [chart-testing (`ct`)](https://github.com/helm/chart-testing) for the same
  lint/install checks CI runs
- [pre-commit](https://pre-commit.com/) for the standard hooks
- A local Kubernetes cluster (kind, k3d, minikube, Docker Desktop, …) for
  install testing

Clone and bootstrap:

```sh
git clone https://github.com/4TUResearchData/helm-charts.git
cd helm-charts
pre-commit install
```

### Common tasks

```sh
just                                    # list recipes
just lint                               # helm lint + ct lint across all charts
just template                           # helm template with the canonical values
just chart=djehuty install              # helm install into the current kube-context
just chart=djehuty package              # produces a .tgz in .cr-release-packages/
```

## Pull requests (chart-specific)

1. Branch from `main`.
2. Bump the chart's `version:` in `charts/<chart>/Chart.yaml` whenever you
   change anything under `charts/<chart>/`. Follow SemVer.
3. Run `just lint` locally — CI runs the same checks on PR.
4. Keep PRs focused: one chart change per PR is easiest to review and
   release.

## Releasing

Releases are cut automatically by
[chart-releaser-action](https://github.com/helm/chart-releaser-action):

- Merging a PR that changes a chart's `version:` causes the next push to
  `main` to publish a `<chart>-<version>` GitHub Release with the packaged
  `.tgz`, and update `index.yaml` on the `gh-pages` branch.
- Forgetting to bump the chart version means no release is cut.

## Code of Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — inherited from djehuty.
