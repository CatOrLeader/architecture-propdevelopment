#!/usr/bin/env bash
set -euo pipefail
KUBE_CONTEXT="${KUBE_CONTEXT:-propdevelopment}"
NAMESPACE=traffic-lab
K=(kubectl --context "$KUBE_CONTEXT")
roles=(front-end back-end-api admin-front-end admin-back-end-api)
peers=(back-end-api front-end admin-back-end-api admin-front-end)
probe="isolated-probe-$(date +%s)-$$"
other_ns="pd-probe-$(date +%s)-$$"
created_probe=false
created_namespace=false
checks=0

cleanup() {
  if $created_probe; then "${K[@]}" -n "$NAMESPACE" delete pod "$probe" --wait=false >/dev/null; fi
  if $created_namespace; then "${K[@]}" delete namespace "$other_ns" --wait=false >/dev/null; fi
}
trap cleanup EXIT

check_http() {
  local source_ns="$1" source="$2" target="$3" expected="$4" label="$5" result
  if result="$("${K[@]}" -n "$source_ns" exec "$source" -- wget -qO- -T 2 "http://$target" 2>&1)"; then
    [[ "$expected" == allow && "$result" == *'Welcome to nginx!'* ]] || {
      echo "FAIL $label: неожиданно получен ответ"; exit 1;
    }
  else
    [[ "$expected" == deny && "$result" == *'timed out'* ]] || {
      echo "FAIL $label: $result"; exit 1;
    }
  fi
  checks=$((checks + 1))
  echo "PASS $label ($expected)"
}

"${K[@]}" -n "$NAMESPACE" wait --for=condition=Ready pod --all --timeout=60s
ips=()
for role in "${roles[@]}"; do
  ips+=("$("${K[@]}" -n "$NAMESPACE" get pod "$role-app" -o jsonpath='{.status.podIP}')")
  check_http "$NAMESPACE" "$role-app" 127.0.0.1 allow "$role: локальный Nginx"
done

# Все 12 направлений проверяем по Pod IP: ошибка DNS не выдаётся за сетевой запрет.
for i in 0 1 2 3; do
  for j in 0 1 2 3; do
    [[ "$i" == "$j" ]] && continue
    expected=deny
    [[ "${peers[$i]}" == "${roles[$j]}" ]] && expected=allow
    check_http "$NAMESPACE" "${roles[$i]}-app" "${ips[$j]}" "$expected" "${roles[$i]} -> ${roles[$j]}"
  done
  check_http "$NAMESPACE" "${roles[$i]}-app" "${peers[$i]}-app" allow "${roles[$i]} -> Service/DNS"
done

# Новый pod без разрешённой роли закрыт в обе стороны.
"${K[@]}" -n "$NAMESPACE" run "$probe" --image=nginx:1.28-alpine \
  --overrides='{"spec":{"automountServiceAccountToken":false}}' >/dev/null
created_probe=true
"${K[@]}" -n "$NAMESPACE" wait --for=condition=Ready "pod/$probe" --timeout=60s
probe_ip="$("${K[@]}" -n "$NAMESPACE" get pod "$probe" -o jsonpath='{.status.podIP}')"
check_http "$NAMESPACE" "$probe" 127.0.0.1 allow 'Новый pod: локальный Nginx'
for i in 0 1 2 3; do
  check_http "$NAMESPACE" "${roles[$i]}-app" "$probe_ip" deny "${roles[$i]} -> новый pod"
  check_http "$NAMESPACE" "$probe" "${ips[$i]}" deny "новый pod -> ${roles[$i]}"
done

# Такая же метка в чужом namespace не должна расширять разрешённую пару.
"${K[@]}" create namespace "$other_ns" >/dev/null
created_namespace=true
"${K[@]}" -n "$other_ns" run foreign-front --image=nginx:1.28-alpine --labels=role=front-end \
  --overrides='{"spec":{"automountServiceAccountToken":false}}' >/dev/null
"${K[@]}" -n "$other_ns" wait --for=condition=Ready pod/foreign-front --timeout=60s
foreign_ip="$("${K[@]}" -n "$other_ns" get pod foreign-front -o jsonpath='{.status.podIP}')"
check_http "$other_ns" foreign-front 127.0.0.1 allow 'Чужой namespace: локальный Nginx'
check_http "$other_ns" foreign-front "${ips[1]}" deny 'Чужой namespace -> back-end-api'
check_http "$NAMESPACE" back-end-api-app "$foreign_ip" deny 'back-end-api -> чужой namespace'
echo "Проверок пройдено: $checks"
