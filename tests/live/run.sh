#!/usr/bin/env bash
set -uo pipefail

# Cluster-only checks for the sos-key-owner-* policies: what the offline cases cannot show.
# A kind cluster with the External Secrets Operator (ESO) and its fake provider holding keys for two
# platforms (nitroso, pichu). The chart's policies and bindings are applied from `helm template`.
#
#   1. without the policy, nitroso reads pichu's token through the cluster store (the threat is real);
#   2. a namespace missing from the store's ESO namespace list cannot use the store at all;
#   3. with only the ExternalSecret guard bound, a bad ClusterExternalSecret gets in but the ESO
#      controller's own create of the child ExternalSecret is refused;
#   4. every tests/cases/*-sos-* case gives its expected result in a real API server, and a good one syncs;
#   5. edits to point an existing ExternalSecret at another platform are refused, and an object made
#      before the policy can still be deleted (the finalizer UPDATE keeps its spec);
#   6. a SecretStore cannot use another namespace's credential Secret (ESO's own webhook).
#
# Needs docker, kind, kubectl and helm. Exit 1 when any check gives another result.

cd "$(git rev-parse --show-toplevel)"
LIVE=tests/live
NAME="${KIND_CLUSTER_NAME:-sos-guard}"
CTX="kind-${NAME}"
ESO_VERSION=2.15.0
bad=0
good=0

k() { kubectl --context "${CTX}" "$@"; }
say() { echo "[$(date -u +%H:%M:%S)] $*"; }
check() { # name ok(true|false) detail
  if [[ $2 == true ]]; then
    good=$((good + 1))
    say "✅ $1"
  else
    bad=$((bad + 1))
    say "❌ $1: $3"
  fi
}
cleanup() { kind delete cluster --name "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# secret_value <ns> <name> <timeout s>: the Secret's token value, or '' after the timeout
secret_value() {
  local s=${SECONDS} v
  while ((SECONDS - s < $3)); do
    v="$(k -n "$1" get secret "$2" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null)"
    if [[ -n ${v} ]]; then
      echo "${v}"
      return 0
    fi
    sleep 1
  done
  echo ""
}
# until_denied <file>: policies load asynchronously; wait until a server dry run of a fail case is refused
until_denied() {
  local s=${SECONDS}
  while ((SECONDS - s < 60)); do
    k apply --dry-run=server -f "$1" >/dev/null 2>&1 || return 0
    sleep 1
  done
  return 1
}

cleanup
kind create cluster --name "${NAME}" --wait 180s || exit 1
helm --kube-context "${CTX}" install external-secrets external-secrets \
  --repo https://charts.external-secrets.io --version "${ESO_VERSION}" \
  -n external-secrets --create-namespace --set installCRDs=true --wait --timeout 5m || exit 1

s=${SECONDS}
until k apply -f "${LIVE}/00-store.yaml" >/dev/null 2>&1; do
  ((SECONDS - s > 120)) && {
    k apply -f "${LIVE}/00-store.yaml"
    exit 1
  }
  sleep 3
done
k wait --for=condition=Ready clustersecretstore/infisical --timeout=60s || exit 1

rendered="$(mktemp)"
helm template cluster-policies chart >"${rendered}" || exit 1
yq 'select(.kind == "ValidatingAdmissionPolicy" and (.metadata.name | test("^sos-key-owner-")))' "${rendered}" >"${rendered}.vap"
yq 'select(.kind == "ValidatingAdmissionPolicyBinding" and .metadata.name == "sos-key-owner-externalsecret")' "${rendered}" >"${rendered}.bind-es"
yq 'select(.kind == "ValidatingAdmissionPolicyBinding" and .metadata.name == "sos-key-owner-clusterexternalsecret")' "${rendered}" >"${rendered}.bind-ces"

say "--- 1, 2: before the policy"
k apply -f "${LIVE}/01-threat-es.yaml" -f "${LIVE}/02-rogue-es.yaml" >/dev/null
v="$(secret_value nitroso threat 60)"
check "threat is real: nitroso read pichu's token without the policy" "$([[ ${v} == pichu-token-v1 ]] && echo true || echo false)" "got '${v}'"
v="$(secret_value rogue rogue-steal 20)"
check "the store's namespace list keeps namespace rogue out" "$([[ -z ${v} ]] && echo true || echo false)" "got '${v}'"
k -n rogue delete externalsecret rogue-steal --wait=false >/dev/null

say "--- 3: only the ExternalSecret guard bound"
k apply -f "${rendered}.vap" -f "${rendered}.bind-es" >/dev/null || exit 1
until_denied tests/cases/41-sos-es-other-platform.yaml || say "policy not active after 60 s"
k apply -f "${LIVE}/03-ces-bad-child.yaml" >/dev/null
sleep 20
reason="$(k get clusterexternalsecret sos-bad-child -o jsonpath='{.status.failedNamespaces[0].reason}' 2>&1)"
child="$(k -n nitroso get externalsecret bad-child -o name 2>/dev/null)"
check "ESO's own child create is refused by the ExternalSecret guard" \
  "$([[ -z ${child} && ${reason} == *sos-key-owner-externalsecret* ]] && echo true || echo false)" "child='${child}' reason='${reason}'"
k delete clusterexternalsecret sos-bad-child >/dev/null

say "--- 4: both guards bound, every sos case"
k apply -f "${rendered}.bind-ces" >/dev/null || exit 1
until_denied tests/cases/54-sos-ces-wrong-namespace.yaml || say "policy not active after 60 s"
for f in tests/cases/*-sos-*.yaml; do
  expect="$(sed -n '1s/^# expect: //p' "${f}")"
  out="$(k apply -f "${f}" 2>&1)"
  rc=$?
  if ((rc == 0)); then got=pass; else got="fail $(grep -o 'sos-key-owner-[a-z]*' <<<"${out}" | head -1)"; fi
  check "$(basename "${f}" .yaml): ${expect}" "$([[ ${got} == "${expect}" ]] && echo true || echo false)" "got [${got}] ${out}"
done
v="$(secret_value nitroso own-token 60)"
check "nitroso's own key syncs" "$([[ ${v} == nitroso-token-v1 ]] && echo true || echo false)" "got '${v}'"
v="$(secret_value nitroso platform-store-cred 60)"
check "the ClusterExternalSecret copies nitroso's token into nitroso" "$([[ ${v} == nitroso-token-v1 ]] && echo true || echo false)" "got '${v}'"
sleep 5
v="$(secret_value rogue rogue-token 2)"
check "rogue reading under its own name gets nothing (namespace list)" "$([[ -z ${v} ]] && echo true || echo false)" "got '${v}'"

say "--- 5: updates and deletes"
key_to_pichu='[{"op":"replace","path":"/spec/data/0/remoteRef/key","value":"/pichu/access/token"}]'
out="$(k -n nitroso patch externalsecret own-token --type=json -p "${key_to_pichu}" 2>&1)"
check "changing a good key to pichu's is refused" "$([[ ${out} == *sos-key-owner-externalsecret* ]] && echo true || echo false)" "${out}"
out="$(k -n nitroso patch externalsecret sos-token --type=json -p "${key_to_pichu}" 2>&1)"
check "editing the ClusterExternalSecret's child to pichu's key is refused" "$([[ ${out} == *sos-key-owner-externalsecret* ]] && echo true || echo false)" "${out}"
out="$(k -n nitroso patch externalsecret threat --type=merge -p '{"spec":{"refreshInterval":"20s"}}' 2>&1)"
check "editing the spec of an object made before the policy is refused" "$([[ ${out} == *sos-key-owner-externalsecret* ]] && echo true || echo false)" "${out}"
out="$(k -n nitroso delete externalsecret threat --timeout=60s 2>&1)"
rc=$?
check "an object made before the policy can still be deleted" "$( ((rc == 0)) && echo true || echo false)" "${out}"

say "--- 6: a namespaced store cannot use another namespace's Secret"
out="$(k apply -f "${LIVE}/04-store-other-namespace.yaml" 2>&1)"
check "SecretStore in nitroso using pichu's Secret is refused by ESO" "$([[ ${out} == *validate.secretstore.external-secrets.io* ]] && echo true || echo false)" "${out}"

echo "live: ${good} as expected, ${bad} not"
[[ ${bad} -eq 0 ]]
