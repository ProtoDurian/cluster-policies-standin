# cluster-policies-standin

Stand-in for the cluster policy chart (ValidatingAdmissionPolicy).
Pinned by commit from template repos. Swap = change address + commit.

## What is here

- `chart/`: the policy chart `cluster-policies`.
  - `require-lpsm-labels`: every workload and its pod template carry the four LPSM labels
    (`<labelPrefix>/landscape`, `platform`, `service`, `module`).
  - `reload-label-required`: every pod template carries `<labelPrefix>/reload: live` or `restart`.
  - `reload-live-inputs`: a `live` pod reads no ConfigMap or Secret through `env`, `envFrom` or a `subPath` file,
    unless the pod annotation `<labelPrefix>/restart-configs` lists it.
  - Exempt: Helm test hooks, and the named Alloy operator objects in `values.yaml` (`alloyOperator`)
    plus the ReplicaSets and Pods they own (matched through `ownerReferences` and `pod-template-hash`).
  - Bindings leave out the system namespaces (`exemptNamespaces`).
- `values.yaml` `labelPrefix` defaults to `durian.cloud` so the chart renders on its own.
  Template repos set it from their root chart (`scripts/local/helm-check.sh`).
- `tests/cases/`: one manifest per case. The first line says `# expect: pass` or `# expect: fail <policy>`.
- `tests/run.sh`: runs `chart-checks check` on every case; red when any case gives another result.

## Run the cases

```bash
nix develop -c ./tests/run.sh
```

## Cluster-only case

The binding that leaves out `kube-system` (and the other `exemptNamespaces`) is not tested here.
chart-checks keeps only the ValidatingAdmissionPolicy objects and never evaluates bindings offline,
so "a Pod in `kube-system` without the labels is admitted" can only be shown in a cluster.
