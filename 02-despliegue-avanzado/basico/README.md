# Lab 02 — Básico: Deployments, actualizaciones y rollback

## Objetivo
Gestionar el ciclo de vida de un Deployment: desplegar, actualizar sin downtime y hacer rollback cuando algo sale mal.

## Duración estimada
40 minutos

---

## Paso 1 — Desplegar una aplicación

```bash
kubectl apply -f deployment-web.yaml

# Observar cómo se crean los pods
kubectl rollout status deployment/app-web -n desarrollo

# Ver el estado
kubectl get deployment app-web -n desarrollo
kubectl get pods -n desarrollo -l app=app-web
```

---

## Paso 2 — Exponer la aplicación con un Service

```bash
kubectl apply -f service-web.yaml

# Verificar el servicio
kubectl get service app-web-svc -n desarrollo

# Probar la conectividad desde dentro del cluster
kubectl run test-curl --image=curlimages/curl:latest --restart=Never -n desarrollo -- \
  curl -s http://app-web-svc.desarrollo.svc.cluster.local

kubectl logs test-curl -n desarrollo
kubectl delete pod test-curl -n desarrollo
```

---

## Paso 3 — Actualización sin downtime (Rolling Update)

```bash
# Ver la versión actual
kubectl get deployment app-web -n desarrollo -o jsonpath='{.spec.template.spec.containers[0].image}'

# Actualizar la imagen
kubectl set image deployment/app-web nginx=nginx:1.26-alpine -n desarrollo

# Observar la actualización en tiempo real
kubectl rollout status deployment/app-web -n desarrollo

# Ver el historial de cambios
kubectl rollout history deployment/app-web -n desarrollo
```

---

## Paso 4 — Rollback

```bash
# Simular un problema: actualizar a una imagen inexistente
kubectl set image deployment/app-web nginx=nginx:version-rota -n desarrollo

# Observar cómo el rolling update se detiene (los pods nuevos fallan)
kubectl rollout status deployment/app-web -n desarrollo
kubectl get pods -n desarrollo -l app=app-web

# El admin ejecuta el rollback
kubectl rollout undo deployment/app-web -n desarrollo

# Verificar que volvió a la versión anterior
kubectl rollout status deployment/app-web -n desarrollo
kubectl get pods -n desarrollo -l app=app-web
```

---

## Paso 5 — Escalar manualmente

```bash
# Escalar a 5 réplicas
kubectl scale deployment app-web --replicas=5 -n desarrollo

# Verificar distribución de pods
kubectl get pods -n desarrollo -l app=app-web -o wide

# Volver a 2
kubectl scale deployment app-web --replicas=2 -n desarrollo
```

---

## Verificación

```bash
kubectl get all -n desarrollo
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué `maxUnavailable: 1` y `maxSurge: 1` es una configuración conservadora?
2. ¿Qué pasa si la nueva imagen no existe y `maxUnavailable: 0`?
3. ¿Cómo se ve el historial de un rollout y cuántas revisiones se guardan?
