chart       := "djehuty"
release     := chart
namespace   := "default"
charts_dir  := "charts"
chart_dir   := charts_dir / chart
pkg_dir     := ".cr-release-packages"

# Show available recipes
default:
    @just --list

# Lint every chart (helm lint + chart-testing if available)
lint:
    for d in {{charts_dir}}/*/; do helm lint "$d"; done
    command -v ct >/dev/null && ct lint --config ct.yaml || echo "ct not installed; skipping chart-testing lint"

# Render a chart's templates (override values via VALUES=path/to/values.yaml)
template values="":
    helm template {{release}} {{chart_dir}} {{ if values != "" { "-f " + values } else { "" } }}

# Install or upgrade a chart into the current kube-context
install values="":
    helm upgrade --install {{release}} {{chart_dir}} \
        -n {{namespace}} --create-namespace \
        {{ if values != "" { "-f " + values } else { "" } }}

# Uninstall the release
uninstall:
    helm uninstall {{release}} -n {{namespace}}

# Package the chart into .cr-release-packages/
package:
    mkdir -p {{pkg_dir}}
    helm package {{chart_dir}} -d {{pkg_dir}}

# Update chart dependencies
deps:
    helm dependency update {{chart_dir}}

# Regenerate chart READMEs from values.yaml comments via helm-docs
docs:
    helm-docs --chart-search-root={{charts_dir}}

# Remove packaged artefacts
clean:
    rm -rf {{pkg_dir}} .cr-index
