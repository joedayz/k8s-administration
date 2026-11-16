# Lab 08 — Avanzado: Troubleshooting de Nodos y Control Plane

## Objetivo
Diagnosticar y recuperar un worker con `k3s-agent` parado, un disco lleno y un CoreDNS caído en este clúster k3s. El mismo síntoma en kubeadm y en OpenShift está al final, para llevarlo a un clúster de trabajo.

## Duración estimada
90 minutos

---

## Escenario 1 — Nodo NotReady: k3s-agent parado

En este clúster el worker no corre la unidad `kubelet`. El proceso que registra el nodo es `k3s-agent`. En el server la unidad es `k3s`.

### Simular el fallo

```bash
multipass exec k3s-worker -- sudo systemctl stop k3s-agent

# Esperar ~40 segundos y observar
watch kubectl get nodes
# k3s-worker pasará a: NotReady
```

### Diagnosticar

```bash
# 1. Ver el estado del nodo
kubectl describe node k3s-worker
# Buscar en Conditions: "KubeletNotReady", "NetworkPluginNotReady"
# Buscar en Events: mensajes de desconexión

# 2. Ver los eventos recientes del cluster
kubectl get events -A --sort-by=lastTimestamp | tail -15

# 3. Conectarse al nodo y ver el agente
multipass exec k3s-worker -- sudo systemctl status k3s-agent
multipass exec k3s-worker -- sudo journalctl -u k3s-agent -n 30 --no-pager
```

### Resolver

```bash
# Reiniciar el agente k3s en el worker
multipass exec k3s-worker -- sudo systemctl start k3s-agent

# Esperar recuperación (~20 segundos)
sleep 25
kubectl get nodes
# k3s-worker debe volver a Ready
```

---

## Escenario 2 — Nodo NotReady: disco lleno

### Simular

```bash
# 3 GB. Si DiskPressure sigue en False, el disco aún no cruzó el umbral
# de desalojo (suele ser ~85% de nodefs). df -h dice cuánto falta.
multipass exec k3s-worker -- bash -c "df -h / && dd if=/dev/zero of=/tmp/disco-lleno bs=1M count=3000 2>&1 | tail -1 && df -h /"
```

### Diagnosticar

```bash
kubectl describe node k3s-worker
# Buscar: DiskPressure=True en Conditions

# En el nodo:
multipass exec k3s-worker -- df -h
multipass exec k3s-worker -- du -sh /tmp/* 2>/dev/null | sort -h | tail -5
```

### Resolver

```bash
# Liberar espacio
multipass exec k3s-worker -- sudo rm /tmp/disco-lleno
sleep 20
kubectl describe node k3s-worker | grep -A3 "Conditions:"
# DiskPressure debe volver a False
```

---

## Escenario 3 — Troubleshooting del Control Plane (k3s)

### Verificar componentes del control plane

```bash
# En k3s, el control plane corre en el proceso k3s-server
multipass exec k3s-server -- sudo systemctl status k3s --no-pager

# Ver logs del servidor
multipass exec k3s-server -- sudo journalctl -u k3s -n 50 --no-pager | grep -E "ERROR|WARN|panic"

# En k3s el API, el scheduler y el controller-manager van dentro del proceso k3s.
# En kube-system solo quedan CoreDNS, Traefik, metrics-server y el local-path-provisioner.
kubectl get pods -n kube-system
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

### Simular problema de CoreDNS

```bash
# Este clúster tiene 1 réplica. Anótala antes de bajarla a 0.
kubectl get deploy coredns -n kube-system
kubectl scale deployment coredns --replicas=0 -n kube-system

# Probar que el DNS falla
kubectl run dns-test --image=busybox:1.36 --rm -it -- \
  sh -c "nslookup kubernetes.default || echo 'DNS CAÍDO'"

# Restaurar CoreDNS
kubectl scale deployment coredns --replicas=1 -n kube-system
sleep 15

# Verificar recuperación
kubectl run dns-test --image=busybox:1.36 --rm -it -- \
  sh -c "nslookup kubernetes.default && echo 'DNS OK'"
```

---

## Escenario 4 — Cluster completamente roto (simulación CKA)

Este escenario replica la pregunta de troubleshooting del examen CKA donde te dan un cluster con varios problemas y tienes que resolverlos todos.

### Setup del escenario

```bash
kubectl apply -f escenario-roto.yaml
```

Problemas a diagnosticar y resolver:
1. Un Deployment con imagen incorrecta
2. Un Service con selector roto
3. Un pod Pending por falta de resources
4. Un pod con liveness probe que falla

### Proceso de resolución

```bash
# 1. Visión general
kubectl get all -n cluster-roto

# 2. Pods problemáticos
kubectl get pods -n cluster-roto | grep -v Running

# 3. Para cada pod con problema:
kubectl describe pod <nombre> -n cluster-roto
kubectl logs <nombre> -n cluster-roto --previous

# 4. Verificar services
kubectl get endpoints -n cluster-roto

# 5. Corregir uno a uno
# Problema 1: imagen incorrecta
kubectl set image deployment/app-imagen-mala \
  app=nginx:alpine -n cluster-roto

# Problema 2: selector roto del service
kubectl patch service svc-roto -n cluster-roto \
  --type=merge -p '{"spec":{"selector":{"app":"app-correcta"}}}'

# Problema 3: pod pending — editar resources
kubectl delete pod pod-recursos-altos -n cluster-roto
kubectl run pod-recursos-ok --image=nginx:alpine \
  --requests=cpu=50m,memory=64Mi \
  -n cluster-roto

# Problema 4: liveness probe fallando
kubectl describe pod pod-probe-falla -n cluster-roto
# Ver en Events: "Liveness probe failed"
```

---

## Checklist de troubleshooting rápido para el examen CKA

```bash
# 1. ¿Los nodos están Ready?
kubectl get nodes

# 2. ¿Los pods del sistema están bien?
kubectl get pods -n kube-system

# 3. ¿Hay pods problemáticos?
kubectl get pods -A | grep -v "Running\|Completed"

# 4. ¿Hay eventos de error?
kubectl get events -A --field-selector type=Warning --sort-by=lastTimestamp | tail -20

# 5. ¿Los services tienen endpoints?
kubectl get endpoints -A | grep "<none>"

# 6. Estado del agente en un worker de este clúster:
# multipass exec k3s-worker -- sudo systemctl status k3s-agent
```

---

## Limpieza

Estos escenarios tocan el nodo y CoreDNS, no solo un namespace. Hay que devolverlos aunque el ejercicio se haya quedado a medias.

```bash
multipass exec k3s-worker -- sudo systemctl start k3s-agent
multipass exec k3s-worker -- sudo rm -f /tmp/disco-lleno
kubectl scale deployment coredns --replicas=1 -n kube-system
kubectl delete namespace cluster-roto --ignore-not-found
kubectl delete pod dns-test --ignore-not-found
```

---

## Para llevar a un clúster real

Estos comandos no se ejecutan en las VMs del curso.

**kubeadm.** El nodo pasa a `NotReady` si paras `kubelet`, no `k3s-agent`. El API, etcd, scheduler y controller-manager son static pods: si el API no responde, se entra al control plane por SSH y se miran `crictl ps` y los manifiestos de `/etc/kubernetes/manifests/`. CoreDNS se escala igual, con el selector `k8s-app=kube-dns`.

```bash
sudo systemctl stop kubelet
sudo journalctl -u kubelet -n 50
sudo crictl ps
kubectl get pods -n kube-system -l tier=control-plane
```

**OpenShift.** No se para el kubelet a mano para “ver qué pasa”: el Machine Config Operator puede reconciliar el nodo. El diagnóstico de plataforma es por operadores. Un nodo se saca con `oc adm cordon` y `oc adm drain`, y se inspecciona con `oc debug node`.

```bash
oc get clusteroperators
oc get nodes
oc adm cordon <worker>
oc debug node/<worker>
```

En EKS, GKE o AKS el control plane lo diagnostica el proveedor. El admin mira nodos, eventos y el node group.

---

## Preguntas de reflexión para el instructor

1. ¿Qué información da `kubectl describe node` que no da `kubectl get node`?
2. Si el API server está caído, ¿cómo diagnosticas el problema?
3. ¿Cuál es el primer componente que debes revisar cuando el cluster no responde?
4. ¿Cómo priorizarías la resolución de múltiples problemas simultáneos en producción?
