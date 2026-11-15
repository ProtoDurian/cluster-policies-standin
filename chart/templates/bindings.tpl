{{- /* The namespace selector skips the system namespaces. A cluster-scoped object (a ClusterExternalSecret) has no namespace, so it is never skipped. */ -}}
{{- range list "require-lpsm-labels" "reload-label-required" "reload-live-inputs" "sos-key-owner-externalsecret" "sos-key-owner-clusterexternalsecret" }}
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: {{ . }}
spec:
  policyName: {{ . }}
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchExpressions:
        - { key: kubernetes.io/metadata.name, operator: NotIn, values: {{ toJson $.Values.exemptNamespaces }} }
{{- end }}
