{{- $_ := required "labelPrefix is empty: set it in values (template repos set it from their root chart)" .Values.labelPrefix }}
# Cluster admission policy for workloads. Template repos evaluate it offline with chart-checks against
# their rendered charts (pinned by commit in their chart-checks.yaml); a cluster installs the same chart.
#
# Scope: workloads only (exemptions in _helpers.tpl). Every Pod and every workload (object AND its pod template,
# and a CronJob's jobTemplate) carries all four LPSM labels. Upstream non-workload objects (RBAC, CRDs, hooks, ...) are not asked for
# them: in a cluster this policy also admits upstream charts, and most cannot label those.
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-lpsm-labels
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      {{- include "policies.workloadRules" . | nindent 6 }}
  matchConditions:
    {{- include "policies.exemptions" . | nindent 4 }}
  variables:
    - name: keys
      expression: >-
        ['landscape', 'platform', 'service', 'module'].map(k, '{{ .Values.labelPrefix }}/' + k)
    {{- include "policies.podMeta" . | nindent 4 }}
  validations:
    - expression: >-
        has(object.metadata.labels) &&
        variables.keys.all(k, k in object.metadata.labels)
      message: Every workload must carry the LPSM labels {{ .Values.labelPrefix }}/landscape, platform, service and module.
    - expression: >-
        has(variables.podMeta.labels) &&
        variables.keys.all(k, k in variables.podMeta.labels)
      message: Every pod template must carry the LPSM labels {{ .Values.labelPrefix }}/landscape, platform, service and module.
    # A CronJob's Jobs take their labels from jobTemplate.metadata; without them every Job it creates is refused.
    - expression: >-
        object.kind != 'CronJob' ||
        (has(object.spec.jobTemplate.metadata) && has(object.spec.jobTemplate.metadata.labels) &&
        variables.keys.all(k, k in object.spec.jobTemplate.metadata.labels))
      message: Every CronJob jobTemplate must carry the LPSM labels {{ .Values.labelPrefix }}/landscape, platform, service and module.
