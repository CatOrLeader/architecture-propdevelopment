# Изоляция трафика

В `traffic-lab` развёрнуты четыре pod с Nginx и четыре ClusterIP Service. Метки `role` заданы по условию. По умолчанию закрыты ingress и egress всех pod, включая новые. Разрешены TCP/80 внутри двух пар и DNS для четырёх заданных ролей.

| Откуда → куда | front-end | back-end-api | admin-front-end | admin-back-end-api |
| --- | --- | --- | --- | --- |
| front-end | — | Разрешено | Запрещено | Запрещено |
| back-end-api | Разрешено | — | Запрещено | Запрещено |
| admin-front-end | Запрещено | Запрещено | — | Разрешено |
| admin-back-end-api | Запрещено | Запрещено | Разрешено | — |

Разрешённые пары могут начинать соединение в обе стороны. `podSelector` без `namespaceSelector` выбирает pod только в том же namespace. Для DNS разрешён доступ к CoreDNS в `kube-system` по UDP/TCP 53.

## Запуск и проверка

Используется Minikube из Task4 с Calico: без поддержки NetworkPolicy со стороны CNI политики не ограничивают трафик.

```bash
kubectl --context propdevelopment apply -f Task5/workloads.yaml
kubectl --context propdevelopment apply -f Task5/network-policies.yaml
bash Task5/verify.sh
```

Скрипт проверяет все 12 направлений между pod по IP, DNS, изоляцию нового pod без роли и pod с такой же меткой в другом namespace. Запрет засчитывается только при таймауте. Временные ресурсы удаляются после проверки.

26.10.2026, Minikube 1.38.1, Kubernetes 1.35.1, Calico 3.31.3, `nginx:1.28-alpine`: 32 из 32 проверок пройдены. Четыре разрешённых направления дали страницу Nginx, восемь запрещённых — таймаут.

Документация: [Minikube](https://minikube.sigs.k8s.io/docs/handbook/network_policy/), [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/).
