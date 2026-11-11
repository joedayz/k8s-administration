# Lab 04 — Avanzado: Prometheus, Grafana y alertas

## Objetivo
Instalar el stack de monitorización estándar de la industria (Prometheus + Grafana) y configurar alertas que el admin recibirá cuando el cluster tenga problemas.

## Duración estimada
90 minutos

---

## Paso 1 — Instalar kube-prometheus-stack con Helm

Este chart incluye: Prometheus, Grafana, Alertmanager y exportadores de métricas.

```bash
# Agregar repositorio
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Crear namespace de monitorización
kubectl create namespace monitoreo

# Instalar el stack completo
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoreo \
  --values prometheus-values.yaml

# Seguir la instalación
kubectl rollout status deployment/prometheus-grafana -n monitoreo --timeout=3m
kubectl get pods -n monitoreo
```

---

## Paso 2 — Acceder a Grafana

```bash
# Obtener la contraseña de Grafana
kubectl get secret prometheus-grafana -n monitoreo \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo

# Port-forward para acceder desde tu Mac
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoreo
```

Abre en el navegador: http://localhost:3000
- Usuario: `admin`
- Contraseña: la del comando anterior

**Dashboards precargados a explorar:**
- "Kubernetes / Cluster" — vista general del cluster
- "Kubernetes / Nodes" — CPU, RAM, disco por nodo
- "Kubernetes / Pods" — métricas por pod

---

## Paso 3 — Acceder a Prometheus

```bash
# En otra terminal
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoreo
```

Abre: http://localhost:9090

**Queries útiles para un admin:**

```promql
# Porcentaje de CPU usado por nodo
100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memoria disponible por nodo en GB
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024

# Pods en estado no-Running
kube_pod_status_phase{phase!="Running",phase!="Succeeded"}

# Reinicios de containers en la última hora
increase(kube_pod_container_status_restarts_total[1h]) > 0

# Uso de disco en nodos
(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes * 100
```

---

## Paso 4 — Configurar alertas

```bash
kubectl apply -f alertas-admin.yaml

# Verificar que las reglas se cargaron
kubectl get prometheusrule -n monitoreo
```

Ver las alertas en Prometheus: http://localhost:9090/alerts

---

## Paso 5 — Simular una alerta

```bash
# Crear un pod que consuma memoria para disparar la alerta
kubectl apply -f pod-stress.yaml

# Observar en Prometheus cómo sube el consumo
# Query: container_memory_working_set_bytes{pod="pod-stress"}

# Después de 2-5 minutos la alerta debe aparecer en estado "Firing"
# En producción, Alertmanager enviaría un email/Slack/PagerDuty

# Limpiar
kubectl delete pod pod-stress
```

---

## Paso 6 — Logging con kubectl

Sin un stack centralizado de logs, estas son las herramientas del admin:

```bash
# Logs de un pod específico
kubectl logs -n monitoreo -l app.kubernetes.io/name=prometheus --tail=50

# Seguir logs en tiempo real
kubectl logs -f deployment/prometheus-grafana -n monitoreo

# Logs de un pod que murió (contenedor anterior)
kubectl logs <pod-name> --previous -n monitoreo

# Logs de todos los pods de un deployment
kubectl logs -l app.kubernetes.io/name=prometheus -n monitoreo --all-containers

# Ver logs de los últimos 30 minutos
kubectl logs deployment/prometheus-grafana -n monitoreo --since=30m
```

---

## Limpiar

```bash
helm uninstall prometheus -n monitoreo
kubectl delete namespace monitoreo
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué métrica usarías para detectar que un nodo está a punto de quedarse sin disco?
2. ¿Cuál es la diferencia entre un alert `Pending` y uno `Firing`?
3. ¿Por qué necesitas un stack de logs centralizado si ya tienes `kubectl logs`?
4. ¿Qué harías si Prometheus mismo se queda sin memoria?
