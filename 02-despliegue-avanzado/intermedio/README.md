# Lab 02 — Intermedio: StatefulSets, Jobs y CronJobs

## Objetivo
Gestionar aplicaciones con estado y tareas programadas — dos responsabilidades críticas del administrador de Kubernetes.

## Duración estimada
60 minutos

---

## Parte A — StatefulSet (base de datos)

### Paso 1 — Desplegar un StatefulSet

```bash
kubectl apply -f statefulset-postgres.yaml

# Observar cómo los pods se crean EN ORDEN (postgres-0 primero, luego postgres-1)
kubectl get pods -n produccion -w

# Verificar que cada pod tiene su propio PVC
kubectl get pvc -n produccion

# Ver los pods con identidad estable
kubectl get pods -n produccion -l app=postgres
```

**Puntos clave para el admin:**
- `postgres-0`, `postgres-1` — nombres predecibles y estables
- Cada pod tiene su propio volumen: `data-postgres-0`, `data-postgres-1`
- Si eliminas `postgres-1`, vuelve con el mismo nombre y el mismo volumen

### Paso 2 — Verificar identidad y DNS estable

```bash
# El Headless Service crea registros DNS para cada pod
# Formato: <pod>.<service>.<namespace>.svc.cluster.local
kubectl run dns-test --image=busybox:1.36 --restart=Never -- \
  nslookup postgres-0.postgres-headless.produccion.svc.cluster.local

kubectl logs dns-test
kubectl delete pod dns-test
```

### Paso 3 — Simular fallo y recuperación

```bash
# Eliminar un pod del StatefulSet
kubectl delete pod postgres-1 -n produccion

# Observar cómo se recrea con el mismo nombre
kubectl get pods -n produccion -w

# Verificar que el PVC sigue intacto
kubectl get pvc -n produccion
```

---

## Parte B — Jobs

### Paso 4 — Ejecutar un Job (tarea única)

```bash
kubectl apply -f job-migracion.yaml

# Seguir la ejecución
kubectl get job job-migracion -n produccion
kubectl get pods -n produccion -l job-name=job-migracion

# Ver los logs del Job
kubectl logs -l job-name=job-migracion -n produccion

# Verificar que completó exitosamente
kubectl describe job job-migracion -n produccion
```

### Paso 5 — Jobs paralelos

```bash
kubectl apply -f job-paralelo.yaml

# Ver cómo crea múltiples pods en paralelo
kubectl get pods -n produccion -l job-name=job-procesamiento -w
```

---

## Parte C — CronJobs

### Paso 6 — Crear un CronJob de backup

```bash
kubectl apply -f cronjob-backup.yaml

# Ver el CronJob
kubectl get cronjob -n produccion

# Forzar ejecución manual (útil para probar)
kubectl create job backup-manual --from=cronjob/backup-db -n produccion

# Ver el historial de Jobs ejecutados
kubectl get jobs -n produccion

# Ver logs del último backup
kubectl logs -l job-name=backup-manual -n produccion
```

### Paso 7 — Gestionar Jobs fallidos (tarea del admin)

```bash
# Ver cuántos Jobs completados/fallidos hay acumulados
kubectl get jobs -n produccion

# Limpiar Jobs completados manualmente
kubectl delete job -l app=backup -n produccion

# Revisar la política de retención del CronJob
kubectl describe cronjob backup-db -n produccion | grep -E "Success|Failed"
```

---

## Verificación

```bash
kubectl get statefulsets -n produccion
kubectl get pvc -n produccion
kubectl get cronjobs -n produccion
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué una base de datos NO puede ser un Deployment?
2. ¿Qué pasa si eliminas el PVC de un StatefulSet? ¿Se recupera?
3. ¿Cuál es el riesgo de un CronJob sin `concurrencyPolicy`?
4. ¿Cómo configuras alertas cuando un Job falla?
