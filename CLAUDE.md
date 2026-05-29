# helm-charts

Helm charts for 4TU.ResearchData. Two charts live here:

- `charts/djehuty/` — the djehuty research-data repository application.
- `charts/virtuoso/` — generic OpenLink Virtuoso (SPARQL/RDF triple store).

`djehuty` depends on `virtuoso` via `Chart.yaml` `dependencies:` (`condition: virtuoso.enabled`). The Virtuoso chart is published independently and pulled in as `virtuoso-*.tgz` into `charts/djehuty/charts/`.

## Related repos

- djehuty source + Dockerfile: sibling repo at `../djehuty/`. The OpenShift UID compat (`chown -R djehuty:0 /data && chmod -R g=u /data`) lives in `../djehuty/docker/Dockerfile` — it's an image concern, not a chart concern. Do not try to handle it via `securityContext` here.
- djehuty image: `ghcr.io/4turesearchdata/djehuty:dev`, built multi-arch (`docker buildx build --platform linux/amd64`) since OpenShift nodes are amd64.

## OpenShift compatibility pattern

Both charts default to empty `podSecurityContext: {}` and `securityContext: {}` so OpenShift's SCC assigns UID/fsGroup from the namespace range. Don't set explicit `runAsUser` / `fsGroup` in the chart defaults — it'll break SCC.

## Virtuoso chart — non-obvious bits

- Image `openlink/virtuoso-opensource-7`, tag falls back to `.Chart.AppVersion`.
- Persistence is `ReadWriteOnce`, deployment `strategy: Recreate` — must not be Rolling.
- DBA password: either `dbaPassword` (chart renders Secret) OR `existingSecret`/`existingSecretKey` for sealed-secrets / ESO / vault-injector. Container reads `DBA_PASSWORD` env via `secretKeyRef`.
- `initScripts:` map → ConfigMap at `/opt/virtuoso-opensource/initdb.d`. Image runs `*.sql` / `*.sh` on first boot only; idempotency is the script's responsibility. Parent djehuty chart uses this to seed SPARQL permissions.

### Backup restore (the tricky bit)

`restore.enabled: true` adds an initContainer that runs on every pod start but is a no-op without operator action. Guarded by `/database/restore/.pending` marker.

Operator flow:
1. Scale djehuty to zero.
2. `kubectl exec $POD -- mkdir -p /database/restore`
3. `kubectl cp ./backups $NS/$POD:/database/restore` (the `.bp` file(s))
4. `kubectl exec $POD -- touch /database/restore/.pending`
5. `kubectl delete pod $POD` — restart triggers restore.

InitContainer logic worth knowing:
- Derives backup prefix via `sed 's/[0-9]*$//'` on the basename — handles split backups like `prefix#1.bp prefix#2.bp …`.
- Wipes live db files (`virtuoso.db|lck|log|pxa|trx` + `virtuoso-temp.db|trx`) but keeps `virtuoso.ini`.
- `mv $RESTORE_DIR/*.bp /database/` — CWD requirement of `virtuoso-t`. The image's `virtuoso.ini` has `../database/...` paths that only resolve from `/database`.
- Runs `virtuoso-t +configfile /database/virtuoso.ini +restore-backup $PREFIX`, then removes `.bp` files + marker.

## Staging deployment

- Cluster: OpenShift, namespace `data4tu-stage`, accessed via `kubectl` (works through `oc`).
- Hostname: `staging.data.4tu.nl` (Route + cert-manager via `letsencrypt-prod` ClusterIssuer, in `values-staging.yaml`).
- Virtuoso state is restored from a `.bp` checkpoint backup of production (state graph `https://data.4tu.nl`, 33M+ triples). The restored DBA password is the production one — NOT `virtuoso.dbaPassword` default. `isql 1111 dba dba` won't work; needs the real one.
