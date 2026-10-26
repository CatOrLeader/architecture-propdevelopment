# Ролевой доступ в Kubernetes

Доступ разделён по четырём namespace: `sales`, `housing`, `finance`, `data`. Роли назначаются группам. `<domain>` в таблице означает один из этих доменов.

| Роль | Права роли | Группы пользователей |
| --- | --- | --- |
| `pd-domain-viewer` | `get/list/watch` для pod, сервисов, endpoints, событий, PVC, workloads, HPA, ingress и NetworkPolicy только своего namespace. Без логов, ConfigMap и Secret. | `pd:<domain>:viewers`: владельцы продуктов, аналитики, менеджеры операционных команд и инженеры, которым нужен просмотр |
| `pd-namespace-configurator` | Просмотр, создание, изменение и удаление NetworkPolicy, ResourceQuota и LimitRange своего домена. | `pd:<domain>:operators`: DevOps и инженеры эксплуатации домена |
| `pd-cluster-viewer` | `get/list/watch` для узлов, namespace, PV и StorageClass на уровне кластера. | `pd:platform:viewers`: платформа и сотрудники ИБ с задачами аудита инфраструктуры |
| `pd-cluster-configurator` | `get/list/watch/update/patch` узлов: например, cordon и изменение taint. | `pd:platform:operators`: ограниченная группа платформенных DevOps |
| `pd-secret-reader` | Только `get` одного Secret `integration-credentials` в своём namespace; без `list/watch`. | `pd:<domain>:secret-readers`: назначенные хранители интеграционных секретов, доступ по согласованию с ИБ |

Роли доменов привязаны через RoleBinding, роли платформы — через ClusterRoleBinding. Пользователи не могут менять RBAC, утверждать CSR, запускать workload и выполнять `exec`: через pod можно обойти запрет на чтение Secret. См. [рекомендации Kubernetes](https://kubernetes.io/docs/concepts/security/rbac-good-practices/).

## Запуск

Нужны Docker, Minikube, kubectl и OpenSSL. Скрипты запускаются администратором из корня репозитория.

```bash
minikube start -p propdevelopment --driver=docker --cni=calico \
  --cpus=2 --memory=2200 --keep-context --kubernetes-version=v1.35.1
bash Task4/01-create-users.sh
bash Task4/02-create-roles.sh
bash Task4/03-bind-roles.sh
```

Первый скрипт создаёт пять пользователей и их kubeconfig, второй — namespace и роли, третий — привязки групп. `KUBE_CONTEXT` по умолчанию равен `propdevelopment`. Повторный запуск переиспользует действующие сертификаты.

Ключи и kubeconfig сохраняются в `Task4/.credentials` с правами `600`, каталог исключён из Git. Сертификат запрашивается на сутки: имя пользователя берётся из `CN`, группы — из `O`. Удаление CSR не отзывает сертификат; права отзываются через привязки ролей. [Документация CSR](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/).

Проверено 26.10.2026 на Minikube 1.38.1 и Kubernetes 1.35.1: 36 проверок пройдены. Доступ к тестовому Secret получил только `security-officer`; `housing-operator` и `sales-viewer` получили `Forbidden`. NetworkPolicy и Node проверены через серверный dry-run. Тестовый Secret удалён.
