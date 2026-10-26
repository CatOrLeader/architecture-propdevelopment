#!/usr/bin/env bash
set -euo pipefail
KUBE_CONTEXT="${KUBE_CONTEXT:-propdevelopment}"
K=(kubectl --context "$KUBE_CONTEXT")

bind_domain() {
  local domain="$1" suffix="$2" role="$3"
  "${K[@]}" apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pd-$suffix
  namespace: $domain
subjects:
  - kind: Group
    name: pd:$domain:$suffix
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: $role
  apiGroup: rbac.authorization.k8s.io
YAML
}

for domain in sales housing finance data; do
  bind_domain "$domain" viewers pd-domain-viewer
  bind_domain "$domain" operators pd-namespace-configurator
  bind_domain "$domain" secret-readers pd-secret-reader
done

"${K[@]}" apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pd-platform-viewers
subjects:
  - kind: Group
    name: pd:platform:viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pd-cluster-viewer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pd-platform-operators
subjects:
  - kind: Group
    name: pd:platform:operators
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pd-cluster-configurator
  apiGroup: rbac.authorization.k8s.io
YAML
