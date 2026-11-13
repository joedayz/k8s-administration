# Lab 06 — Básico: Taints, Tolerations y NodeSelector

## Objetivo
Controlar en qué nodos se despliegan los pods usando taints y tolerations. Verificar el impacto real en el scheduling.

## Duración estimada
50 minutos

---

## Paso 1 — Verificar el estado actual de los nodos

```bash
# Ver labels y taints actuales
kubectl get nodes --show-labels
kubectl describe nodes | grep -A5 "Taints:"
```

---

## Paso 2 — Añadir un taint a k3s-worker

Vamos a marcar el nodo `k3s-worker` como dedicado a workloads de frontend:

```bash
kubectl taint nodes k3s-worker tier=frontend:NoSchedule

# Verificar
kubectl describe node k3s-worker | grep -A3 "Taints:"
```

---

## Paso 3 — Intentar desplegar un pod SIN toleración

```bash
kubectl create namespace scheduling
kubectl apply -f pod-sin-toleracion.yaml

# Observar — el pod irá a k3s-worker2 o k3s-server, NO a k3s-worker
sleep 5
kubectl get pod pod-sin-toleracion -n scheduling -o wide
```

Fíjate en la columna NODE. El scheduler ha evitado `k3s-worker`.

---

## Paso 4 — Desplegar un pod CON toleración

```bash
kubectl apply -f pod-con-toleracion.yaml

sleep 5
kubectl get pods -n scheduling -o wide
```

El pod con toleración **puede** ir a `k3s-worker`, aunque no es obligatorio.

---

## Paso 5 — Forzar que SOLO vaya al nodo tainteado

Para que un pod vaya exclusivamente a un nodo, combina taint + `nodeName` o `nodeSelector`:

```bash
kubectl apply -f pod-nodo-dedicado.yaml

sleep 5
kubectl get pod pod-nodo-dedicado -n scheduling -o wide
# Debe aparecer en k3s-worker
```

---

## Paso 6 — Taint con efecto NoExecute

El efecto `NoExecute` expulsa pods que YA están corriendo en el nodo:

```bash
# Crear un pod en k3s-worker2
kubectl run pod-victima --image=nginx:alpine -n scheduling \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k3s-worker2"}}}'

sleep 8
kubectl get pod pod-victima -n scheduling -o wide

# Ahora tainteamos k3s-worker2 con NoExecute
kubectl taint nodes k3s-worker2 mantenimiento=true:NoExecute

# El pod será expulsado en segundos
sleep 5
kubectl get pod pod-victima -n scheduling -o wide
# STATUS: Terminating o ya no existe
```

---

## Limpieza

```bash
# Quitar los taints
kubectl taint nodes k3s-worker tier=frontend:NoSchedule-
kubectl taint nodes k3s-worker2 mantenimiento=true:NoExecute-

# Borrar recursos
kubectl delete namespace scheduling
```

---

## Verificación final

```bash
kubectl describe nodes | grep "Taints:"
# Todos deben mostrar: Taints: <none>
```

---

## Preguntas de reflexión para el instructor

1. ¿Cuándo usarías `NoSchedule` vs `NoExecute`? ¿Qué riesgo tiene `NoExecute`?
2. ¿Cómo configurarías un nodo exclusivo para bases de datos en producción?
3. ¿Qué pasa si el único nodo disponible tiene un taint y el pod no tiene toleración?
4. ¿Los pods del sistema (CoreDNS, kube-proxy) tienen toleraciones? ¿Por qué?
