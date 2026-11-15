# cluster-policies-standin

Stand-in for the cluster policy chart (ValidatingAdmissionPolicy).
Pinned by commit from template repos. Swap = change address + commit.

## What is here

- `chart/`: the policy chart `cluster-policies`.
  - `require-lpsm-labels`: every workload and its pod template carry the four LPSM labels
    (`<labelPrefix>/landscape`, `platform`, `service`, `module`). A CronJob's `jobTemplate.metadata` carries them too.
  - `reload-label-required`: every pod template carries `<labelPrefix>/reload: live` or `restart`.
  - `reload-live-inputs`: a `live` pod reads no ConfigMap or Secret through `env`, `envFrom` or a `subPath` file,
    unless the pod annotation `<labelPrefix>/restart-configs` lists it.
  - `sos-key-owner-externalsecret` and `sos-key-owner-clusterexternalsecret` (secrets guard): one
    ClusterSecretStore per cluster (`sosStore.name`, default `infisical`, the store cobalt ships) can read every platform's folder in the
    secret-of-secrets project. Through it, a platform (= its namespace name) may only read
    `/<platform>/<sosStore.folder>/<NAME>` (default folder `access`, NAME matching `sosStore.namePattern`).
    An ExternalSecret's platform is its namespace. A ClusterExternalSecret must target exactly one namespace with
    the single `matchLabels` `kubernetes.io/metadata.name: <platform>`. Searching the store (`dataFrom.find`)
    and per-item `sourceRef` are refused. Only creates and spec changes are checked, so an object made before the
    policy can still be deleted.
    **Install order: install this chart before any platform namespace or ExternalSecret exists.** A policy never
    removes objects that are already there.
  - Exempt (workload policies): Helm test hooks, and the named Alloy operator objects in `values.yaml` (`alloyOperator`)
    plus the ReplicaSets and Pods they own (matched through `ownerReferences` and `pod-template-hash`).
  - Bindings leave out the system namespaces (`exemptNamespaces`).
- `values.yaml` `labelPrefix` defaults to `durian.cloud` so the chart renders on its own.
  Template repos set it from their root chart (`scripts/local/helm-check.sh`).
- `tests/cases/`: one manifest per case. The first line says `# expect: pass` or `# expect: fail <policy>`.
- `tests/run.sh`: runs `chart-checks check` on every case; red when any case gives another result.
- `tests/live/run.sh`: cluster-only checks for the secrets guard in a kind cluster with the External Secrets Operator
  (fake provider): the threat without the policy, the store's namespace list, the controller's own child create refused,
  every `*-sos-*` case in a real API server, updates and deletes, and a store using another namespace's Secret.

## Run the cases

```bash
nix develop -c ./tests/run.sh
nix develop .#live -c ./tests/live/run.sh   # needs docker
```

## Cluster-only case

The binding that leaves out `kube-system` (and the other `exemptNamespaces`) is not tested here.
chart-checks keeps only the ValidatingAdmissionPolicy objects and never evaluates bindings offline,
so "a Pod in `kube-system` without the labels is admitted" can only be shown in a cluster.
