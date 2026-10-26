#!/usr/bin/env bash
set -euo pipefail
umask 077

KUBE_CONTEXT="${KUBE_CONTEXT:-propdevelopment}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CREDENTIALS_DIR="$SCRIPT_DIR/.credentials"
K=(kubectl --context "$KUBE_CONTEXT")
for tool in kubectl openssl; do command -v "$tool" >/dev/null; done
"${K[@]}" get --raw=/readyz >/dev/null
mkdir -p "$CREDENTIALS_DIR"
chmod 700 "$CREDENTIALS_DIR"

server="$("${K[@]}" config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
if [[ -f "$CREDENTIALS_DIR/server" && "$(cat "$CREDENTIALS_DIR/server")" != "$server" ]]; then
  echo 'Кластер изменился. Перенесите старую .credentials перед выпуском новых сертификатов.' >&2
  exit 1
fi
printf '%s' "$server" > "$CREDENTIALS_DIR/server"
"${K[@]}" config view --minify --flatten --raw \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | openssl base64 -d -A > "$CREDENTIALS_DIR/ca.crt"
test -s "$CREDENTIALS_DIR/ca.crt"

create_user() {
  local username="$1" namespace="$2" groups="$3"
  local base="$CREDENTIALS_DIR/$username" subject="/CN=$username" group csr_name certificate
  if [[ -f "$base.key" && -f "$base.crt" && -f "$base.kubeconfig" ]] && \
     openssl x509 -in "$base.crt" -checkend 300 -noout >/dev/null && \
     openssl verify -CAfile "$CREDENTIALS_DIR/ca.crt" "$base.crt" >/dev/null 2>&1; then
    echo "$username: действующий сертификат уже есть"
    return
  fi
  for group in $groups; do subject="$subject/O=$group"; done
  openssl req -new -newkey rsa:2048 -nodes -keyout "$base.key" \
    -out "$base.csr" -subj "$subject" 2>/dev/null
  csr_name="pd-$username-$(openssl rand -hex 4)"
  "${K[@]}" apply -f - <<YAML
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $csr_name
  labels:
    app.kubernetes.io/part-of: propdevelopment-rbac
spec:
  request: $(openssl base64 -A -in "$base.csr")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: [client auth]
YAML
  # Учебный bootstrap выполняет администратор. Пользователям approval не выдаётся.
  "${K[@]}" certificate approve "$csr_name"
  certificate=''
  for attempt in {1..30}; do
    certificate="$("${K[@]}" get csr "$csr_name" -o jsonpath='{.status.certificate}')"
    [[ -n "$certificate" ]] && break
    sleep 1
  done
  [[ -n "$certificate" ]] || { echo "Сертификат $username не выпущен" >&2; exit 1; }
  printf '%s' "$certificate" | openssl base64 -d -A > "$base.crt"
  openssl verify -CAfile "$CREDENTIALS_DIR/ca.crt" "$base.crt" >/dev/null
  kubectl --kubeconfig "$base.kubeconfig" config set-cluster "$KUBE_CONTEXT" \
    --server="$server" --certificate-authority="$CREDENTIALS_DIR/ca.crt" --embed-certs=true >/dev/null
  kubectl --kubeconfig "$base.kubeconfig" config set-credentials "$username" \
    --client-certificate="$base.crt" --client-key="$base.key" --embed-certs=true >/dev/null
  kubectl --kubeconfig "$base.kubeconfig" config set-context "$username" \
    --cluster="$KUBE_CONTEXT" --user="$username" --namespace="$namespace" >/dev/null
  kubectl --kubeconfig "$base.kubeconfig" config use-context "$username" >/dev/null
  chmod 600 "$base.key" "$base.kubeconfig"
  echo "$username: $base.kubeconfig"
}

create_user sales-viewer sales 'pd:sales:viewers'
create_user housing-operator housing 'pd:housing:viewers pd:housing:operators'
create_user platform-viewer default 'pd:platform:viewers'
create_user platform-operator default 'pd:platform:viewers pd:platform:operators'
create_user security-officer housing 'pd:housing:viewers pd:housing:secret-readers'
