#!/usr/bin/env bash
set -euo pipefail
KUBE_CONTEXT="${KUBE_CONTEXT:-propdevelopment}"
K=(kubectl --context "$KUBE_CONTEXT")

for domain in sales housing finance data; do
  "${K[@]}" apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: $domain
  labels:
    propdevelopment.ru/domain: $domain
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.35
YAML
done

"${K[@]}" apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pd-domain-viewer
rules:
  - apiGroups: [""]
    resources: [pods, services, endpoints, events, persistentvolumeclaims]
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [deployments, replicasets, statefulsets, daemonsets]
    verbs: [get, list, watch]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch]
  - apiGroups: [autoscaling]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch]
  - apiGroups: [networking.k8s.io]
    resources: [networkpolicies, ingresses]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pd-namespace-configurator
rules:
  - apiGroups: [""]
    resources: [resourcequotas, limitranges]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [networking.k8s.io]
    resources: [networkpolicies]
    verbs: [get, list, watch, create, update, patch, delete]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pd-cluster-viewer
rules:
  - apiGroups: [""]
    resources: [nodes, namespaces, persistentvolumes]
    verbs: [get, list, watch]
  - apiGroups: [storage.k8s.io]
    resources: [storageclasses]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pd-cluster-configurator
rules:
  - apiGroups: [""]
    resources: [nodes]
    verbs: [get, list, watch, update, patch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pd-secret-reader
rules:
  - apiGroups: [""]
    resources: [secrets]
    resourceNames: [integration-credentials]
    verbs: [get]
YAML
