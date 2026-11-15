{{- /*
Secrets guard for the one-store-per-cluster design: one ClusterSecretStore per cluster (`sosStore.name`)
can read every platform's folder /<platform>/<sosStore.folder> in the landscape's secret-of-secrets
environment. These two policies keep each platform to its own folder:

- an ExternalSecret that reads through that store may only read /<its namespace>/<folder>/<NAME>;
- a ClusterExternalSecret that reads through it must target exactly one namespace, by the built-in
  label kubernetes.io/metadata.name (set by the API server, always equal to the name), and may only
  read that namespace's folder.

The platform is the namespace name. Searching the store (dataFrom.find) and a per-item sourceRef
(which could point one item at the store while the top-level store is another) are refused.

Only creates and spec changes are checked: the External Secrets controller removes its clean-up
finalizer with an UPDATE that keeps the spec, so checking every UPDATE would make an object created
before this policy impossible to delete.

Install this chart BEFORE any platform namespace or ExternalSecret exists: a policy never removes
objects that are already there.
*/ -}}
{{- $store := required "sosStore.name is empty" .Values.sosStore.name }}
{{- $folder := required "sosStore.folder is empty" .Values.sosStore.folder }}
{{- $pattern := required "sosStore.namePattern is empty" .Values.sosStore.namePattern }}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$" $store) }}
{{- fail "sosStore.name must be a Kubernetes object name" }}
{{- end }}
{{- if not (regexMatch "^[A-Za-z0-9_-]+$" $folder) }}
{{- fail "sosStore.folder must be one folder name ([A-Za-z0-9_-]+)" }}
{{- end }}
{{- if or (contains "'" $pattern) (contains "\\" $pattern) (contains "/" $pattern) }}
{{- fail "sosStore.namePattern may not contain a quote, a backslash or a slash" }}
{{- end }}
{{- range $kind := list "externalsecret" "clusterexternalsecret" }}
{{- $ces := eq $kind "clusterexternalsecret" }}
{{- $spec := ternary "object.spec.externalSecretSpec" "object.spec" $ces }}
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: sos-key-owner-{{ $kind }}
spec:
  failurePolicy: Fail
  matchConstraints:
    matchPolicy: Equivalent
    resourceRules:
      - apiGroups: [external-secrets.io]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [{{ $kind }}s]
  matchConditions:
    - name: create-or-spec-change
      expression: "request.operation == 'CREATE' || object.spec != oldObject.spec"
  variables:
    - name: spec
      expression: {{ $spec }}
    - name: data
      expression: "has(variables.spec.data) ? variables.spec.data : []"
    - name: dataFrom
      expression: "has(variables.spec.dataFrom) ? variables.spec.dataFrom : []"
    - name: topSos
      expression: >-
        has(variables.spec.secretStoreRef) && has(variables.spec.secretStoreRef.kind) &&
        variables.spec.secretStoreRef.kind == 'ClusterSecretStore' &&
        variables.spec.secretStoreRef.name == '{{ $store }}'
    - name: itemSos
      expression: >-
        variables.data.exists(d, has(d.sourceRef) && has(d.sourceRef.storeRef) &&
          has(d.sourceRef.storeRef.kind) && d.sourceRef.storeRef.kind == 'ClusterSecretStore' &&
          d.sourceRef.storeRef.name == '{{ $store }}') ||
        variables.dataFrom.exists(d, has(d.sourceRef) && has(d.sourceRef.storeRef) &&
          has(d.sourceRef.storeRef.kind) && d.sourceRef.storeRef.kind == 'ClusterSecretStore' &&
          d.sourceRef.storeRef.name == '{{ $store }}')
    - name: usesSos
      expression: variables.topSos || variables.itemSos
    {{- if $ces }}
    # The one namespace this ClusterExternalSecret targets, or '' when it does not name exactly one.
    - name: platform
      expression: >-
        !has(object.spec.namespaces) && !has(object.spec.namespaceSelector) &&
        has(object.spec.namespaceSelectors) && size(object.spec.namespaceSelectors) == 1 &&
        !has(object.spec.namespaceSelectors[0].matchExpressions) &&
        has(object.spec.namespaceSelectors[0].matchLabels) &&
        size(object.spec.namespaceSelectors[0].matchLabels) == 1 &&
        'kubernetes.io/metadata.name' in object.spec.namespaceSelectors[0].matchLabels
        ? object.spec.namespaceSelectors[0].matchLabels['kubernetes.io/metadata.name'] : ''
    {{- else }}
    - name: platform
      expression: request.namespace
    {{- end }}
    # Namespace names are DNS labels ([a-z0-9-]), so they are safe inside the regex.
    - name: keyPattern
      expression: "'^/' + variables.platform + '/{{ $folder }}/{{ $pattern }}$'"
  validations:
    {{- if $ces }}
    - expression: "!variables.usesSos || variables.platform != ''"
      message: >-
        A ClusterExternalSecret that reads the cluster store {{ $store }} must target exactly one namespace:
        namespaceSelectors with the single matchLabels kubernetes.io/metadata.name=<platform>.
    {{- end }}
    - expression: >-
        !variables.usesSos ||
        (variables.topSos && variables.data.all(d, !has(d.sourceRef)) &&
         variables.dataFrom.all(d, !has(d.sourceRef)))
      message: Reading the cluster store {{ $store }} must name it as the only store (no per-item sourceRef).
    - expression: "!variables.usesSos || variables.dataFrom.all(d, !has(d.find))"
      message: The cluster store {{ $store }} may not be searched (dataFrom.find).
    - expression: >-
        !variables.usesSos || variables.platform == '' ||
        (variables.data.all(d, d.remoteRef.key.matches(variables.keyPattern)) &&
         variables.dataFrom.all(d, has(d.extract) && d.extract.key.matches(variables.keyPattern)))
      messageExpression: >-
        'Through the cluster store {{ $store }}, platform ' + variables.platform +
        ' may only read keys like /' + variables.platform + '/{{ $folder }}/<NAME>.'
{{- end }}
