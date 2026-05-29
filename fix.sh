#!/usr/bin/env bash
# Reset the helm-charts repo to a single-commit "0.1.0-dev" state and
# republish both charts. Destructive: force-pushes main and gh-pages,
# deletes the djehuty-0.1.0-dev GitHub release. Safe only while no
# external users are consuming the chart repo.

set -euo pipefail

REPO_DIR="/Users/kdearaujo/dev/4TUReserchData/helm-charts"
INITIAL_COMMIT="599a62c"
GH_REPO="4TUResearchData/helm-charts"

cd "$REPO_DIR"

# 1. Revert version bumps in both Chart.yaml files (chart version + djehuty's dep).
sed -i '' 's/version: 0.1.0-dev.1/version: 0.1.0-dev/' charts/virtuoso/Chart.yaml charts/djehuty/Chart.yaml
sed -i '' 's/version: "0.1.0-dev.1"/version: "0.1.0-dev"/' charts/djehuty/Chart.yaml

# 2. Rebuild the bundled virtuoso tarball so djehuty ships the fixed values.
rm -f charts/djehuty/charts/virtuoso-*.tgz
helm package charts/virtuoso -d charts/djehuty/charts/

# 3. Squash main into a single commit on top of the original initial commit.
git add -A
git reset --soft "$INITIAL_COMMIT"
git commit --amend -m "initial helm chart development"

# 4. Delete the lingering djehuty release (and its tag) so chart-releaser republishes.
gh release delete djehuty-0.1.0-dev --cleanup-tag -y -R "$GH_REPO"

# 5. Wipe gh-pages index so the workflow regenerates it from scratch.
git checkout gh-pages
git rm index.yaml
git commit -m "reset index"
git push --force-with-lease origin gh-pages
git checkout main

# 6. Force-push main; release workflow fires and publishes both charts fresh.
git push --force-with-lease origin main

echo "Done. Watch the workflow with: gh run watch -R $GH_REPO"
