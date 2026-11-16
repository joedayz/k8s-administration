# Lab 07 — Básico: Cordon, Drain y Uncordon

## Objetivo
Realizar el flujo completo de mantenimiento de un nodo: retirarlo del servicio sin interrumpir aplicaciones, hacer el mantenimiento y reincorporarlo.

## Duración estimada
45 minutos

---

## Paso 1 — Desplegar una aplicación de prueba

```bash
kubectl create namespace mantenimiento
kubectl apply -f deployment-app.yaml

sleep 10
kubectl get pods -n mantenimiento -o wide
# Verifica que los pods están distribuidos entre los nodos
```

---

## Paso 2 — Cordon del nodo

`cordon` marca el nodo como `SchedulingDisabled`. Los pods existentes siguen corriendo, pero no entran nuevos.

```bash
kubectl cordon k3s-worker

# Verificar estado
kubectl get nodes
# k3s-worker debe mostrar: Ready,SchedulingDisabled

# Los pods que ya están en el nodo siguen corriendo
kubectl get pods -n mantenimiento -o wide
```

---

## Paso 3 — Drain del nodo

`drain` desaloja los pods del nodo y los mueve a `k3s-server` o `k3s-worker2`. kube-proxy y el CNI van dentro del proceso `k3s-agent`, no son pods. `--ignore-daemonsets` cubre los DaemonSet que sí haya, como el ServiceLB de un Service `LoadBalancer`. El drain mueve todo lo que haya en `k3s-worker`, también pods de otros labs.

```bash
kubectl drain k3s-worker \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30

# Verificar que todos los pods migraron
kubectl get pods -n mantenimiento -o wide
# Ningún pod debe estar en k3s-worker

# El nodo sigue en el cluster pero sin pods de usuario
kubectl get nodes
```

---

## Paso 4 — Simular mantenimiento

```bash
# Simular un reboot del nodo (en producción sería el upgrade del OS)
multipass restart k3s-worker

# Esperar a que el nodo vuelva
sleep 20
kubectl get nodes
# k3s-worker vuelve a Ready,SchedulingDisabled
# El cordon vive en el objeto Node, dentro de state.db, y sobrevive al reboot de la VM
```

---

## Paso 5 — Uncordon y verificar

```bash
kubectl uncordon k3s-worker

kubectl get nodes
# k3s-worker debe mostrar: Ready

# Los pods NO vuelven automáticamente al nodo — el scheduler decide
# según disponibilidad en el próximo scheduling
kubectl get pods -n mantenimiento -o wide
```

---

## Paso 6 — Forzar redistribución (opcional)

```bash
# Si quieres redistribuir los pods actualmente cargados en otros nodos:
kubectl rollout restart deployment/app-mantenimiento -n mantenimiento
sleep 10
kubectl get pods -n mantenimiento -o wide
# Ahora el scheduler reparte de nuevo incluyendo k3s-worker
```

---

## Limpieza

```bash
kubectl delete namespace mantenimiento
```

---

## Verificación final

```bash
kubectl get nodes
# Todos deben mostrar Ready sin SchedulingDisabled
kubectl describe nodes | grep "Taints:"
# Todos <none>
```

---

## Para llevar a un clúster real

Estos comandos no se ejecutan en las VMs del curso. El flujo es el mismo: cordon, drain, mantenimiento, uncordon. El taint queda en el objeto Node.

**kubeadm y Kubernetes vanilla.** `kubectl cordon`, `kubectl drain` y `kubectl uncordon`, con el nombre real del nodo. kube-proxy y el CNI sí suelen ser DaemonSets, así que `--ignore-daemonsets` hace falta. Un pod suelto, creado con `kubectl create` o `kubectl run --restart=Never`, detiene el drain hasta que pases `--force`, porque nadie lo volvería a crear.

```bash
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data --grace-period=30
kubectl uncordon <worker>
```

**OpenShift.** Se usa `oc adm`. `--force` aparece a menudo porque varios pods de plataforma no tienen un controlador que los recree. Durante un upgrade el Machine Config Pool ya drena los nodos; un drain manual es para mantenimiento de un nodo concreto.

```bash
oc adm cordon <worker>
oc adm drain <worker> --ignore-daemonsets --delete-emptydir-data --force --grace-period=600
oc adm uncordon <worker>
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué ocurre con los pods en `emptyDir` al hacer drain? ¿Y con los pods en `PVC`?
2. ¿Por qué el taint de cordon persiste después de un reboot del nodo?
3. ¿Qué es `PodDisruptionBudget` y cómo afecta al drain?
4. ¿Cuántos nodos puedes drainear a la vez en producción con seguridad?
