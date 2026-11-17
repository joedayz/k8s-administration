# Lab 11 — Avanzado: In-place Pod Resize

## Objetivo
Cambiar los `requests`/`limits` de CPU y memoria de un pod **ya corriendo**, sin recrearlo, usando el subrecurso `resize` del API server (GA desde Kubernetes 1.33). Ver también qué pasa cuando el resize no es posible.

## Duración estimada
45 minutos

> **Nota sobre la versión de kubectl:** esta feature se gestiona con `kubectl patch --subresource resize`, soportado desde kubectl 1.33+. Si tu kubectl es más antiguo (verifica con `kubectl version --client`), usa el método alternativo con `kubectl proxy` + `curl` del Paso 3 — funciona contra cualquier cluster que soporte el subrecurso, sin depender de la versión del cliente.

---

## Paso 1 — Crear el namespace y el pod redimensionable

```bash
kubectl create namespace lifecycle-patrones
kubectl apply -f pod-resizable.yaml

sleep 5
kubectl get pod pod-resizable -n lifecycle-patrones
kubectl get pod pod-resizable -n lifecycle-patrones -o jsonpath='{.spec.containers[0].resources}'
```

---

## Paso 2 — Anotar el restartCount antes de redimensionar

```bash
kubectl get pod pod-resizable -n lifecycle-patrones -o jsonpath='{.status.containerStatuses[0].restartCount}'
# 0
```

---

## Paso 3 — Redimensionar en caliente (subir CPU y memoria)

### Opción A — con kubectl 1.33+

```bash
kubectl patch pod pod-resizable -n lifecycle-patrones --subresource resize --patch \
  '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"150m","memory":"192Mi"},"limits":{"cpu":"300m","memory":"384Mi"}}}]}}'
```

### Opción B — vía la API REST directamente (cualquier versión de kubectl)

```bash
kubectl proxy --port=8765 &

curl -s -X PATCH \
  "http://127.0.0.1:8765/api/v1/namespaces/lifecycle-patrones/pods/pod-resizable/resize" \
  -H "Content-Type: application/strategic-merge-patch+json" \
  -d '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"150m","memory":"192Mi"},"limits":{"cpu":"300m","memory":"384Mi"}}}]}}'
```

---

## Paso 4 — Verificar que no hubo restart

```bash
sleep 8
kubectl get pod pod-resizable -n lifecycle-patrones -o jsonpath='{.status.containerStatuses[0].restartCount}'
# Sigue en 0 — el contenedor nunca se reinició

kubectl get pod pod-resizable -n lifecycle-patrones -o jsonpath='{.status.containerStatuses[0].allocatedResources}'
# {"cpu":"150m","memory":"192Mi"} — kubelet ya reconcilió los nuevos valores

kubectl get pod pod-resizable -n lifecycle-patrones -o jsonpath='{.spec.containers[0].resources}'
```

---

## Paso 5 — Qué pasa si pides más de lo que el nodo tiene disponible

```bash
kubectl patch pod pod-resizable -n lifecycle-patrones --subresource resize --patch \
  '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"10","memory":"192Mi"},"limits":{"cpu":"10","memory":"384Mi"}}}]}}'
```

Resultado esperado — el API server **rechaza la petición de inmediato**, antes de tocar el pod:

```
Error from server (Forbidden): pods "pod-resizable" is forbidden:
node didn't have enough allocatable resources: cpu, requested: 10000, allocatable: 2000
```

El pod sigue corriendo sin interrupción con los valores del Paso 3 — el resize fallido no afecta al contenedor en ejecución.

---

## Limpieza

```bash
kubectl delete namespace lifecycle-patrones
```

---

## Verificación final

```bash
kubectl get pods -A | grep lifecycle-patrones
# No debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué el resize usa un subrecurso (`/resize`) en lugar de un `PATCH` normal a `spec.containers[].resources`?
2. ¿Qué pasaría si `resizePolicy` para memoria fuera `RestartContainer` en vez de `NotRequired`? ¿En qué casos tiene sentido forzar el restart (pista: apps que cachean el límite de memoria al arrancar)?
3. ¿Por qué el rechazo por falta de capacidad del nodo ocurre en la *admisión* y no después, como un evento `FailedScheduling`?
4. ¿Qué ventaja operativa tiene esta feature frente a un `kubectl rollout restart` cuando necesitas darle más memoria a una app bajo presión en producción?
