# virtuoso Helm chart

Helm chart for [OpenLink Virtuoso (open-source)](https://github.com/openlink/virtuoso-opensource),
a SPARQL/RDF triple store. Extracted from the
[djehuty chart](../djehuty/README.md) — usable standalone or as its subchart.

> [!WARNING]
> **Development phase.** Pre-1.0 and under active development. Pin the
> chart version before upgrading.

Single-replica Deployment, ReadWriteOnce PVC at `/database`, `Recreate`
strategy. Empty `podSecurityContext` / `securityContext` so OpenShift's SCC
controls UID / fsGroup.

## Quick start

```sh
helm install my-virtuoso 4turesearchdata/virtuoso \
  --set dbaPassword='change-me'
kubectl port-forward svc/my-virtuoso 8890:8890
```

## DBA password

Default: chart renders a Secret with `dbaPassword` (defaults to `"dba"` —
change it). To delegate the secret to your own management (sealed-secrets,
external-secrets-operator, vault-injector, …):

```yaml
existingSecret: my-virtuoso-creds       # must already exist in the namespace
existingSecretKey: DBA_PASSWORD         # default
```

When `existingSecret` is set, `dbaPassword` is ignored.

## Init scripts

Maps `<filename>: <contents>` into `/opt/virtuoso-opensource/initdb.d`. The
official image runs every `*.sql` / `*.sh` here **once**, on first boot —
write idempotent SQL if you want re-runnable behaviour.

```yaml
initScripts:
  001-permissions.sql: |
    DB.DBA.RDF_DEFAULT_USER_PERMS_SET ('nobody', 7);
    GRANT SPARQL_UPDATE TO "SPARQL";
```

## Restoring a `.bp` backup

The chart wires Virtuoso's native checkpoint restore into pod startup,
gated by a marker file. Enabled by default (`restore.enabled: true`) and
a no-op until an operator drops the marker — safe to leave on.

```sh
NS=data4tu-stage
POD=$(kubectl -n $NS get pod -l app.kubernetes.io/name=virtuoso -o jsonpath='{.items[0].metadata.name}')

kubectl -n $NS exec $POD -- mkdir -p /database/restore
for f in ./backups/prod-*.bp; do
  kubectl cp -n $NS "$f" "$POD:/database/restore/"
done
kubectl -n $NS exec $POD -- touch /database/restore/.pending
kubectl -n $NS delete pod $POD
kubectl -n $NS logs -f -l app.kubernetes.io/name=virtuoso -c restore
```

The init script derives the backup prefix by stripping trailing digits +
`.bp` (e.g. `prod-2025-07-09_#1.bp` → prefix `prod-2025-07-09_#`); copy
only one backup set at a time. Any SPARQL client in the same release
(e.g. djehuty) should be scaled to zero first to avoid serving errors.

Disable entirely: `restore.enabled: false`.
