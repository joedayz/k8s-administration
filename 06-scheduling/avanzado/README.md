# Lab 06 — Avanzado: PriorityClass, Static Pods y Topology Spread

## Objetivo
Gestionar prioridades para garantizar que workloads críticos siempre tengan recursos, explorar los static pods del control plane, y distribuir pods de forma precisa entre nodos y zonas.

## Duración estimada
75 minutos

---

## Parte A — PriorityClass

### Paso 1 — Crear jerarquía de prioridades

```bash
kubectl apply -f priority-classes.yaml

# Ver las clases de prioridad del sistema
kubectl get priorityclasses
# Fíjate en system-cluster-critical y system-node-critical (ya existen)
```

### Paso 2 — Desplegar workloads con distintas prioridades

```bash
kubectl create namespace scheduling
kubectl apply -f deployment-critico.yaml
kubectl apply -f deployment-batch.yaml

kubectl get pods -n scheduling -o wide
```

### Paso 3 — Simular presión de recursos (preemption)

Cuando un nodo se llena, el scheduler expulsa pods de baja prioridad para hacer sitio a los de alta prioridad:

```bash
# Saturar el cluster con muchos pods batch
kubectl scale deployment batch-processor --replicas=20 -n scheduling
sleep 10

# Ver si hay pods Pending por falta de recursos
kubectl get pods -n scheduling | grep Pending

# Ahora crear un pod crítico — el scheduler liberará espacio
kubectl apply -f pod-critico-urgente.yaml
sleep 15

# El pod crítico debe estar Running, algunos batch estarán Pending o terminados
kubectl get pods -n scheduling --sort-by='.status.phase'
kubectl get events -n scheduling --sort-by=lastTimestamp | tail -15
```

---

## Parte B — Static Pods

### Paso 4 — Explorar los manifests del control plane (k3s)

Los static pods en k3s están en `/var/lib/rancher/k3s/server/manifests/`:

```bash
# Ver manifests estáticos del server
multipass exec k3s-server -- sudo ls -la /var/lib/rancher/k3s/server/manifests/

# Ver el manifest de CoreDNS
multipass exec k3s-server -- sudo cat /var/lib/rancher/k3s/server/manifests/coredns.yaml | head -40
```

### Paso 5 — Crear un static pod en un worker

Los static pods de los workers van en `/var/lib/rancher/k3s/agent/pod-manifests/`:

```bash
# Crear el archivo de manifest directamente en el worker
multipass exec k3s-worker -- sudo bash -c 'cat > /var/lib/rancher/k3s/agent/pod-manifests/static-nginx.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: static-nginx
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    resources:
      requests:
        cpu: "50m"
        memory: "64Mi"
EOF'

# Esperar a que kubelet lo detecte (10-15 segundos)
sleep 15
kubectl get pods -A | grep static-nginx
```

Observa que el pod aparece con el nombre `static-nginx-k3s-worker` — el nodo se añade como sufijo.

### Paso 6 — Intentar eliminar el static pod via kubectl (debe recrearse)

```bash
kubectl delete pod static-nginx-k3s-worker
sleep 10
kubectl get pods | grep static-nginx
# El pod vuelve a aparecer — kubelet lo recrea automáticamente

# Para eliminarlo definitivamente, hay que borrar el archivo:
multipass exec k3s-worker -- sudo rm /var/lib/rancher/k3s/agent/pod-manifests/static-nginx.yaml
sleep 10
kubectl get pods | grep static-nginx
# Ahora sí desaparece
```

---

## Parte C — Topology Spread Constraints

### Paso 7 — Distribución equilibrada entre nodos

```bash
kubectl apply -f deployment-spread.yaml

sleep 10
kubectl get pods -n scheduling -l app=app-spread -o wide
# Debe haber exactamente 2 pods por nodo (6 réplicas / 3 nodos)
```

### Paso 8 — Verificar el balanceo al escalar

```bash
kubectl scale deployment app-spread --replicas=9 -n scheduling
sleep 10
kubectl get pods -n scheduling -l app=app-spread -o wide
# Ahora 3 por nodo

kubectl scale deployment app-spread --replicas=7 -n scheduling
sleep 10
kubectl get pods -n scheduling -l app=app-spread -o wide
# maxSkew=1 garantiza que la diferencia entre nodos no sea mayor de 1
```

---

## Limpieza

```bash
kubectl delete namespace scheduling
kubectl delete priorityclass critico batch-jobs
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué ocurre si dos PriorityClasses tienen el mismo `value`?
2. ¿Por qué no puedes eliminar un static pod con `kubectl delete`?
3. ¿En qué se diferencia `topologyKey: kubernetes.io/hostname` de `topologyKey: topology.kubernetes.io/zone`?
4. ¿Cómo usarías Topology Spread con zonas de disponibilidad en AWS/Azure?
