# Lab 10 — Básico: Manual Scheduling (nodeName y Binding API)

## Objetivo
Entender qué hace realmente el kube-scheduler agendando un pod a mano, de dos formas distintas: escribiendo `spec.nodeName` directamente, y llamando al endpoint `/binding` del API server (lo que hace el scheduler por debajo).

## Duración estimada
40 minutos

---

## Paso 1 — Crear el namespace de trabajo

```bash
kubectl create namespace scheduling-admission
```

---

## Paso 2 — Saltarse el scheduler con `nodeName`

`pod-nodename-manual.yaml` fija `spec.nodeName: k3s-worker` desde el principio. El pod **nunca pasa por el scheduler** — el kubelet de ese nodo lo ve directamente en su lista de pods asignados y lo arranca.

```bash
kubectl apply -f pod-nodename-manual.yaml

sleep 5
kubectl get pod pod-nodename-manual -n scheduling-admission -o wide
# NODE debe ser k3s-worker, y no debe aparecer ningún evento de "Scheduled"
# generado por kube-scheduler:
kubectl get events -n scheduling-admission --field-selector involvedObject.name=pod-nodename-manual
```

> Si el nodo indicado no existe o no tiene recursos, el pod se queda en `Pending` para siempre — a diferencia del scheduling normal, **no hay fallback** a otro nodo.

---

## Paso 3 — Crear un pod a propósito sin agendar

`pod-sin-asignar.yaml` define `schedulerName: no-schedule-manual`, un nombre de scheduler que no existe. Así el pod se queda `Pending` esperando a que alguien (nosotros) lo asigne manualmente:

```bash
kubectl apply -f pod-sin-asignar.yaml

sleep 5
kubectl get pod pod-sin-asignar -n scheduling-admission -o wide
# STATUS: Pending, NODE: <none>
```

---

## Paso 4 — Agendar el pod a mano con la Binding API

Esto es exactamente lo que hace el kube-scheduler al decidir un nodo: un `POST` a `/api/v1/namespaces/<ns>/pods/<pod>/binding` con un objeto `Binding`.

Abre un túnel al API server con `kubectl proxy` (en una terminal aparte, o en background):

```bash
kubectl proxy --port=8765 &
```

Y en otra terminal, haz el bind manualmente a `k3s-worker2`:

```bash
curl -s -X POST http://127.0.0.1:8765/api/v1/namespaces/scheduling-admission/pods/pod-sin-asignar/binding \
  -H "Content-Type: application/json" \
  -d '{
  "apiVersion": "v1",
  "kind": "Binding",
  "metadata": {"name": "pod-sin-asignar"},
  "target": {"apiVersion": "v1", "kind": "Node", "name": "k3s-worker2"}
}'
```

Respuesta esperada: `"status": "Success", "code": 201`.

```bash
sleep 3
kubectl get pod pod-sin-asignar -n scheduling-admission -o wide
# NODE: k3s-worker2, STATUS: Running
```

Cierra el proxy cuando termines (`fg` + Ctrl+C, o `kill %1`).

---

## Limpieza

```bash
kubectl delete namespace scheduling-admission
```

---

## Verificación final

```bash
kubectl get pods -A | grep scheduling-admission
# No debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. Si fijas `nodeName` a un nodo que no tiene capacidad suficiente, ¿qué pasa con el pod? ¿Quién lo detecta?
2. ¿Por qué el objeto `Binding` se manda como un `POST` a un subrecurso del pod (`/binding`) en lugar de hacer un `PATCH` directo a `spec.nodeName`?
3. ¿Qué ventajas tiene escribir un scheduler personalizado usando este mismo mecanismo, en vez de modificar kube-scheduler?
4. ¿Qué validaciones de admisión (RBAC, PodSecurity) se siguen aplicando aunque te saltes el scheduler?
