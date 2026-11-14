#!/usr/bin/env bash
set -euo pipefail

# Checks every tests/cases/*.yaml against this repo's chart with chart-checks (offline).
# Each case starts with `# expect: pass` or `# expect: fail <policy-name>`.
# A fail case must be refused by the policy stage (the schema stage passes) and by that policy.
# Exit 1 when any case gives a different result.

cd "$(git rev-parse --show-toplevel)"

log_dir="$(mktemp -d)"
trap 'rm -rf "${log_dir}"' EXIT

chart-checks install >"${log_dir}/install.log" 2>&1 || {
  cat "${log_dir}/install.log" >&2
  exit 1
}

mapfile -t cases < <(find tests/cases -maxdepth 1 -type f -name '*.yaml' | LC_ALL=C sort)
if [[ ${#cases[@]} -eq 0 ]]; then
  echo "❌ tests/cases holds no *.yaml cases" >&2
  exit 1
fi

good=0
bad=0
for case in "${cases[@]}"; do
  name="$(basename "${case}" .yaml)"
  expect="$(sed -n '1s/^# expect: //p' "${case}")"
  log="${log_dir}/${name}.log"
  rc=0
  chart-checks check "${case}" >"${log}" 2>&1 || rc=$?
  ok=false
  case "${expect}" in
  pass)
    [[ ${rc} -eq 0 ]] && ok=true
    ;;
  fail\ *)
    policy="${expect#fail }"
    if [[ ${rc} -eq 1 ]] &&
      grep -q 'schema stage exit 0' "${log}" &&
      grep -q "^policy ${policy} -> resource " "${log}"; then
      ok=true
    fi
    ;;
  *)
    echo "❌ ${case}: first line must be '# expect: pass' or '# expect: fail <policy>'" >&2
    exit 1
    ;;
  esac
  if [[ ${ok} == true ]]; then
    echo "✅ ${name}: ${expect}"
    good=$((good + 1))
  else
    echo "❌ ${name}: expected ${expect}, chart-checks exit ${rc}"
    sed 's/^/    /' "${log}"
    bad=$((bad + 1))
  fi
done

echo "cases: ${good} as expected, ${bad} not"
[[ ${bad} -eq 0 ]]
