# Lab 13 — Intermedio: Multiple Schedulers y Scheduler Profiles

## Objetivo
Desplegar un **segundo scheduler** en el cluster (con su propio KubeSchedulerConfiguration y un perfil nombrado), y hacer que un pod específico lo use vía `spec.schedulerName`. Verificar con evidencia real quién agendó cada pod.

## Duración estimada
50 minutos

> **Versión de la imagen:** usamos `registry.k8s.io/kube-scheduler:v1.37.2` para que coincida con el API server (`kubectl version` → Server Version). Si tu cluster es otra versión, ajusta el tag — un scheduler muy desfasado del apiserver puede fallar por version skew.

---

## Teoría rápida

- **Multiple Schedulers**: desplegar un proceso de scheduler extra (otro Deployment) con su propia lógica.
- **Scheduler Profiles**: dentro de un mismo binario de scheduler puedes declarar varios perfiles en el `KubeSchedulerConfiguration`; **el `schedulerName` de cada perfil es lo que los pods referencian**. Aquí combinamos ambos: desplegamos un segundo scheduler cuyo perfil se llama `mi-scheduler`.

---

## Paso 1 — Pre-descargar la imagen del scheduler en los nodos (opcional pero evita esperas)

```bash
multipass exec k3s-worker  -- sudo k3s ctr images pull registry.k8s.io/kube-scheduler:v1.37.2
multipass exec k3s-worker2 -- sudo k3s ctr images pull registry.k8s.io/kube-scheduler:v1.37.2
```

---

## Paso 2 — Crear el ServiceAccount y los permisos RBAC del scheduler

Un scheduler necesita los mismos permisos que el `kube-scheduler` del sistema (leer pods/nodos, crear bindings, leer volúmenes):

```bash
kubectl apply -f scheduler-rbac.yaml
```

---

## Paso 3 — Desplegar el segundo scheduler con su perfil

El `KubeSchedulerConfiguration` (dentro del ConfigMap) define `schedulerName: mi-scheduler`:

```bash
kubectl apply -f mi-scheduler-deployment.yaml
kubectl rollout status deployment/mi-scheduler -n kube-system --timeout=90s

# Debe estar Running
kubectl get pods -n kube-system -l app=mi-scheduler
```

---

## Paso 4 — Desplegar un pod que use el scheduler personalizado

```bash
kubectl create namespace cka-schedulers
kubectl apply -f pod-mi-scheduler.yaml

sleep 6
kubectl get pod pod-mi-scheduler -n cka-schedulers -o wide
# STATUS: Running
```

---

## Paso 5 — Confirmar QUIÉN lo agendó

Este es el punto clave: el evento `Scheduled` debe venir de `mi-scheduler`, no del `default-scheduler`:

```bash
kubectl get events -n cka-schedulers --field-selector reason=Scheduled \
  -o custom-columns='POD:.involvedObject.name,SCHEDULER:.reportingComponent,MSG:.message'
```

Salida esperada:

```
POD                SCHEDULER      MSG
pod-mi-scheduler   mi-scheduler   Successfully assigned cka-schedulers/pod-mi-scheduler to k3s-server
```

También lo ves en los logs del propio scheduler:

```bash
kubectl logs -n kube-system -l app=mi-scheduler --tail=5 | grep "Successfully bound"
```

---

## Paso 6 — Qué pasa con un scheduler que no existe

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-scheduler-fantasma
  namespace: cka-schedulers
spec:
  schedulerName: no-existe-este-scheduler
  containers:
  - name: nginx
    image: nginx:alpine
EOF

sleep 5
kubectl get pod pod-scheduler-fantasma -n cka-schedulers
# STATUS: Pending para siempre — ningún scheduler responde a ese nombre
```

---

## Limpieza

```bash
kubectl delete namespace cka-schedulers
kubectl delete -f mi-scheduler-deployment.yaml
kubectl delete -f scheduler-rbac.yaml
```

---

## Verificación final

```bash
kubectl get pods -n kube-system -l app=mi-scheduler   # no debe devolver nada
kubectl get ns | grep cka-schedulers                   # no debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué el segundo scheduler necesita el ClusterRole `system:kube-scheduler` y `system:volume-scheduler`? ¿Qué falla si le faltan?
2. ¿Qué diferencia hay entre desplegar un **segundo scheduler** (otro proceso) y definir un **segundo profile** en el mismo scheduler? ¿Cuándo preferirías cada uno?
3. En el pod con `schedulerName` inexistente, ¿por qué se queda en `Pending` en vez de dar error al crearse?
4. ¿Por qué pusimos `leaderElection.leaderElect: false`? ¿Qué pasaría en producción con varias réplicas del scheduler?
