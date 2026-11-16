# Lab 08 — Básico: Diagnóstico de Pods Problemáticos

## Objetivo
Identificar y resolver los 5 problemas más comunes de pods en Kubernetes. Cada escenario replica una situación real de producción.

## Duración estimada
60 minutos

---

## Preparación

```bash
kubectl create namespace troubleshooting
kubectl apply -f pods-con-errores.yaml

# Ver el estado de todos los pods
watch kubectl get pods -n troubleshooting
# Espera 30 segundos a que se manifiesten los errores
```

---

## Escenario 1 — CrashLoopBackOff

```bash
kubectl get pod pod-crash -n troubleshooting
# STATUS: CrashLoopBackOff

# DIAGNÓSTICO:
kubectl describe pod pod-crash -n troubleshooting
# Buscar: Exit Code, Restart Count, Last State

# --previous solo existe después del primer reinicio.
# Si responde "previous terminated container not found", usa el log actual
# o espera a que RESTARTS sea al menos 1.
kubectl logs pod-crash -n troubleshooting --previous

# SOLUCIÓN: el comando del contenedor sale con exit 1.
# -n va ANTES de --. Lo que va después de -- es el comando del contenedor,
# no un flag de kubectl: si -n queda ahí, el pod se crea en default.
kubectl delete pod pod-crash -n troubleshooting
kubectl run pod-crash-fixed --image=busybox:1.36 \
  -n troubleshooting \
  --command -- sh -c "while true; do echo ok; sleep 10; done"

kubectl get pod pod-crash-fixed -n troubleshooting
```

---

## Escenario 2 — ImagePullBackOff

```bash
kubectl get pod pod-imagen-mala -n troubleshooting
# STATUS: ImagePullBackOff

# DIAGNÓSTICO:
kubectl describe pod pod-imagen-mala -n troubleshooting
# Buscar en Events: "Failed to pull image"
# El error te dice exactamente qué imagen no se encontró

# SOLUCIÓN: este pod es suelto. kubectl set image no lo recrea.
# En un Deployment sí se usa: kubectl set image deployment/<nombre> ...
kubectl delete pod pod-imagen-mala -n troubleshooting
kubectl run pod-imagen-buena --image=nginx:alpine -n troubleshooting
```

---

## Escenario 3 — OOMKilled (Exit Code 137)

```bash
kubectl get pod pod-oom -n troubleshooting
# STATUS: OOMKilled o Error con múltiples reinicios

# DIAGNÓSTICO:
kubectl describe pod pod-oom -n troubleshooting
# Buscar en "Last State": Reason: OOMKilled, Exit Code: 137

# SOLUCIÓN: aumentar el límite de memoria o reducir consumo
# Crear un nuevo pod con límites correctos
kubectl delete pod pod-oom -n troubleshooting
```

Aplica el pod corregido:

```bash
kubectl apply -f pod-oom-corregido.yaml
sleep 15
kubectl get pod pod-oom-corregido -n troubleshooting
# Debe estar Running sin reinicios
```

---

## Escenario 4 — Pod Pending (sin recursos)

```bash
kubectl get pod pod-pending -n troubleshooting
# STATUS: Pending

# DIAGNÓSTICO:
kubectl describe pod pod-pending -n troubleshooting
# Buscar en Events: "Insufficient cpu" o "Insufficient memory"
# o "no nodes available to schedule pods"

# Ver recursos disponibles en los nodos
kubectl top nodes  # requiere metrics-server
kubectl describe nodes | grep -A5 "Allocated resources"

# SOLUCIÓN: ajustar los requests a valores razonables
kubectl delete pod pod-pending -n troubleshooting
```

---

## Escenario 5 — Pod en estado desconocido / Terminating atascado

`pod-finalizer` ya viene en `pods-con-errores.yaml`, con un finalizer que nadie retira. `delete` sin `--wait=false` se queda colgado: el pod no desaparece hasta quitar el finalizer.

```bash
kubectl get pod pod-finalizer -n troubleshooting

# --wait=false devuelve el prompt mientras el pod sigue en Terminating
kubectl delete pod pod-finalizer -n troubleshooting --wait=false

sleep 5
kubectl get pod pod-finalizer -n troubleshooting

# SOLUCIÓN: eliminar el finalizer con patch
kubectl patch pod pod-finalizer -n troubleshooting \
  -p '{"metadata":{"finalizers":[]}}' \
  --type=merge

kubectl get pod pod-finalizer -n troubleshooting
# Ahora desaparece
```

---

## Herramientas de diagnóstico rápido

```bash
# Health check del cluster completo
kubectl get pods -A | grep -v "Running\|Completed\|NAME"

# Eventos ordenados por tiempo (muy útil para diagnóstico)
kubectl get events -n troubleshooting --sort-by=lastTimestamp

# Solo eventos de tipo Warning
kubectl get events -n troubleshooting \
  --field-selector type=Warning \
  --sort-by=lastTimestamp

# Qué está pasando en un pod en tiempo real
kubectl logs -f pod-crash -n troubleshooting

# Ejecutar comandos dentro de un pod para diagnosticar
kubectl exec -it <pod-name> -n troubleshooting -- sh
```

---

## Limpieza

Si el escenario 5 se quedó a medias, el finalizer también bloquea el borrado del namespace. Primero se vacía.

```bash
kubectl patch pod pod-finalizer -n troubleshooting \
  -p '{"metadata":{"finalizers":[]}}' \
  --type=merge 2>/dev/null || true

kubectl delete namespace troubleshooting --ignore-not-found
```

---

## Para llevar a un clúster real

Estos comandos no se ejecutan en las VMs del curso. `describe`, `logs --previous` y el patch del finalizer son iguales en los tres.

**kubeadm.** Un pod suelto se diagnostica igual. En un Deployment el arreglo de la imagen es `kubectl set image deployment/<nombre> contenedor=imagen:tag` y el rollout recrea los pods. El control plane no interviene en un CrashLoopBackOff de una aplicación.

**OpenShift.** Se usa `oc` con los mismos subcomandos (`oc describe`, `oc logs --previous`, `oc debug`). Un pod de plataforma atascado en `Terminating` se mira antes de borrar el finalizer a mano: a veces lo retiene un operador.

```bash
oc logs pod-crash -n troubleshooting --previous
oc debug pod-crash -n troubleshooting
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué significa el Exit Code 137? ¿Y el 1? ¿Y el 0?
2. Si un pod tiene `RESTARTS: 47`, ¿qué problema tiene probablemente?
3. ¿Por qué `kubectl logs` sin `--previous` no funciona para diagnosticar CrashLoopBackOff?
4. ¿Cómo distingues un OOMKilled de un crash de la aplicación?
