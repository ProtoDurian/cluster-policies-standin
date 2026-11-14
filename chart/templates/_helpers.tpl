{{/* The exemptions shared by every policy here: Helm test hooks and the named Alloy operator objects. */}}
{{- define "policies.exemptions" -}}
# Helm test hooks (helm.sh/hook: test, test-success, test-failure) are exempt: they run only on
# `helm test`, never in a deploy, and several upstream charts cannot label their test Pods.
- name: not-a-helm-test-hook
  expression: >-
    !(has(object.metadata.annotations) &&
    'helm.sh/hook' in object.metadata.annotations &&
    object.metadata.annotations['helm.sh/hook'].split(',')
    .exists(h, h.trim() in ['test', 'test-success', 'test-failure']))
# The named Alloy operator objects, and the objects they create: a ReplicaSet owned by a named Deployment,
# a Pod owned by a named Job, and a Pod owned by the ReplicaSet `<named Deployment>-<the pod's pod-template-hash>`.
# Each child is tied to one named object through ownerReferences; no name prefix is trusted on its own.
- name: not-an-alloy-operator-object
  expression: >-
    !([{{ range .Values.alloyOperator }}['{{ .kind }}', '{{ .name }}'], {{ end }}]
    .exists(e, (object.kind == e[0] && object.metadata.name == e[1]) ||
    object.metadata.?ownerReferences.orValue([]).exists(o,
    (object.kind == 'ReplicaSet' && e[0] == 'Deployment' && o.kind == 'Deployment' && o.name == e[1]) ||
    (object.kind == 'Pod' && e[0] == 'Job' && o.kind == 'Job' && o.name == e[1]) ||
    (object.kind == 'Pod' && e[0] == 'Deployment' && o.kind == 'ReplicaSet' &&
    object.metadata.?labels.orValue({})[?'pod-template-hash'].orValue('') != '' &&
    o.name == e[1] + '-' + object.metadata.labels['pod-template-hash']))))
{{- end }}

{{- define "policies.workloadRules" -}}
- apiGroups: ['']
  apiVersions: ['*']
  operations: [CREATE, UPDATE]
  resources: [pods]
- apiGroups: [apps]
  apiVersions: ['*']
  operations: [CREATE, UPDATE]
  resources: [deployments, statefulsets, daemonsets, replicasets]
- apiGroups: [batch]
  apiVersions: ['*']
  operations: [CREATE, UPDATE]
  resources: [jobs, cronjobs]
{{- end }}

{{- define "policies.podMeta" -}}
- name: podMeta
  expression: >-
    object.kind == 'Pod' ? object.metadata :
    object.kind == 'CronJob' ? object.spec.jobTemplate.spec.template.metadata :
    object.spec.template.metadata
- name: podSpec
  expression: >-
    object.kind == 'Pod' ? object.spec :
    object.kind == 'CronJob' ? object.spec.jobTemplate.spec.template.spec :
    object.spec.template.spec
{{- end }}
