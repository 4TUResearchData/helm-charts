# virtuoso Helm chart

Helm chart for [OpenLink Virtuoso (open-source)](https://github.com/openlink/virtuoso-opensource),
a SPARQL/RDF triple store. Maintained by [4TU.ResearchData](https://data.4tu.nl/)
alongside [djehuty](https://github.com/4TUResearchData/helm-charts/tree/main/charts/djehuty).

> [!WARNING]
> **Development phase.** This chart is pre-1.0 and under active development.
> Values, templates, and defaults may change between commits. Pin to a
> specific version and review release notes before upgrading.

## Why this chart

There is no actively-maintained upstream Helm chart for Virtuoso. This one
was extracted from the djehuty chart for 4TU's roadmap to host SPARQL
independently of the application that queries it. It can be used standalone
or as a subchart (see djehuty's `virtuoso.enabled` toggle).

## Features

- Single-replica `Deployment` with a persistent `/database` PVC
  (ReadWriteOnce, `Recreate` strategy).
- Generic `initScripts` map (filename → contents) mounted at
  `/opt/virtuoso-opensource/initdb.d` — the official image runs every
  `*.sql` / `*.sh` here on first boot. Use it for SPARQL permissions,
  user setup, etc.
- Native checkpoint restore from `.bp` backups, gated by a marker file
  written by an operator. Idempotent and a no-op when no marker is present.
- OpenShift-friendly defaults: empty `podSecurityContext` /
  `securityContext` so the SCC controls UID/fsGroup.

## Quick start

```sh
helm install my-virtuoso 4turesearchdata/virtuoso \
  --set dbaPassword='change-me'
```

Port-forward and reach the SPARQL endpoint:

```sh
kubectl port-forward svc/my-virtuoso 8890:8890
open http://localhost:8890/sparql
```

## DBA password

By default the chart renders a Secret containing `dbaPassword` (default
`"dba"` — change for anything beyond a throwaway). To delegate the secret
to your own management (sealed-secrets, external-secrets-operator,
vault-injector, …), point the chart at an existing Secret instead:

```yaml
existingSecret: my-virtuoso-creds      # must already exist in the namespace
existingSecretKey: DBA_PASSWORD        # key inside that Secret (default shown)
```

When `existingSecret` is set, the chart skips rendering its own Secret and
`dbaPassword` is ignored.

As a djehuty subchart:

```yaml
virtuoso:
  existingSecret: my-virtuoso-creds
  existingSecretKey: DBA_PASSWORD
```

## Init scripts

```yaml
initScripts:
  001-permissions.sql: |
    DB.DBA.RDF_DEFAULT_USER_PERMS_SET ('nobody', 7);
    DB.DBA.RDF_DEFAULT_USER_PERMS_SET ('SPARQL', 7);
    GRANT SPARQL_UPDATE TO "SPARQL";
```

Scripts run once, on the first pod start, in alphabetical order. Subsequent
restarts (or re-creates with the same PVC) do **not** re-run them — write
idempotent SQL if you want re-runnable behaviour.

## Restoring a backup

Virtuoso ships a native checkpoint backup format (`.bp` files produced by
`backup_online()`). The on-VM restore procedure is to stop Virtuoso, swap
the database files, run `virtuoso-t +restore-backup`, and start Virtuoso
again. In k8s this can't be done interactively (a pod dies when its main
process exits), so the chart wires the same steps into pod startup via an
initContainer guarded by a marker file.

The chart enables this by default (`restore.enabled: true`). It's a no-op
until an operator places a backup and the marker — safe to leave on.

### Procedure

```sh
NS=data4tu-stage
POD=$(kubectl -n $NS get pod -l app.kubernetes.io/name=virtuoso -o jsonpath='{.items[0].metadata.name}')

# 1. (Recommended) Snapshot current state — restore wipes the live DB.
kubectl -n $NS exec -i $POD -- isql 1111 dba "$DBA_PASSWORD" <<'EOF'
backup_online('pre-restore-snapshot_#', 1000000, 0, vector());
EOF
kubectl -n $NS exec $POD -- sh -c \
  'mkdir -p /database/snapshots && mv /database/backup/pre-restore-snapshot_*.bp /database/snapshots/'

# 2. Copy backup files into the pod.
kubectl -n $NS exec $POD -- mkdir -p /database/restore
for f in ./backups/prod-*.bp; do
  kubectl cp -n $NS "$f" "$POD:/database/restore/"
done

# 3. Mark and restart — the restore initContainer picks it up.
kubectl -n $NS exec $POD -- touch /database/restore/.pending
kubectl -n $NS delete pod $POD

# 4. Watch.
NEW_POD=$(kubectl -n $NS get pod -l app.kubernetes.io/name=virtuoso -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS logs $NEW_POD -c restore -f
```

If the application that *reads* from Virtuoso is in the same release (e.g.
djehuty bundling this as a subchart), scale it to zero first to avoid
serving errors during the restore.

### Backup file naming

The init script extracts the backup prefix automatically by stripping
trailing digits + `.bp` from the first `.bp` file found:

| File on disk | Prefix passed to `+restore-backup` |
|---|---|
| `prod-2025-07-09_#1.bp` (+ `_#2.bp`, …) | `prod-2025-07-09_#` |
| `staging-2025-11-12_1.bp` | `staging-2025-11-12_` |

If your naming scheme breaks this heuristic, copy only one set of backup
files into `/database/restore/` so the auto-detection picks the right one.

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `CrashLoopBackOff`, log says *no .bp file* | Marker created but no backup files in `/database/restore/` | Copy the files in, or remove the marker (`rm /database/restore/.pending`) |
| `CrashLoopBackOff`, log says *virtuoso.ini not found* | First-time install — Virtuoso hasn't created its config yet | Disable restore (`--set restore.enabled=false`), let Virtuoso boot once, re-enable, then run the procedure |
| Restore "succeeds" but data isn't there | Wrong backup prefix detected | Check the init container log for the detected prefix; ensure only one backup set is in `/database/restore/` |
| `permission denied` reading `.bp` files | Copied files don't have read perms for the random OpenShift UID | The init container does `chmod -R a+r /database/restore` defensively; if it still fails, `chmod 644 ./backups/*.bp` before copying |
| Restore takes hours | Backup is large; Virtuoso replays transactions | Watch `logs -c restore -f`; consider a larger PVC/node |

### Disabling restore entirely

```yaml
restore:
  enabled: false
```

Any `.bp` file copied into `/database/restore/` then sits unused.
