# Lab 09 — Intermedio: Exploración de Componentes del Control Plane

## Objetivo
Inspeccionar cada componente del control plane de Kubernetes, entender cómo interactúan y verificar su salud.

## Duración estimada
60 minutos

---

## Paso 1 — Mapear la arquitectura del cluster

```bash
export KUBECONFIG=~/.kube/k3s-config.yaml

# Ver todos los nodos y sus roles
kubectl get nodes -o wide

# En k3s, los componentes del control plane corren en el proceso k3s-server
# (no como pods separados como en kubeadm)
multipass exec k3s-server -- sudo ps aux | grep -E "k3s|containerd" | grep -v grep
```

---

## Paso 2 — Explorar el kube-apiserver

El API server es el único componente al que hablan todos los demás (kubectl, kubelet, scheduler...).

```bash
# Ver la configuración del API server en k3s
multipass exec k3s-server -- sudo cat /etc/systemd/system/k3s.service | grep -v "^#"

# En un cluster kubeadm, sería un static pod:
# /etc/kubernetes/manifests/kube-apiserver.yaml

# Verificar que el API server responde
kubectl get --raw='/healthz'
# Debe devolver: ok

# Ver la versión de la API
kubectl get --raw='/version' | python3 -m json.tool
```

---

## Paso 3 — Explorar etcd / la base de datos

```bash
# En k3s, el estado se guarda en SQLite
multipass exec k3s-server -- sudo ls -lh /var/lib/rancher/k3s/server/db/

# Ver el tamaño de la base de datos
multipass exec k3s-server -- sudo du -sh /var/lib/rancher/k3s/server/db/

# En kubeadm, sería etcd:
# kubectl get pod -n kube-system | grep etcd
# ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
#   --cacert=/etc/kubernetes/pki/etcd/ca.crt \
#   --cert=/etc/kubernetes/pki/etcd/server.crt \
#   --key=/etc/kubernetes/pki/etcd/server.key \
#   endpoint status --write-out=table

# Ver todas las claves almacenadas (kubeadm)
# ETCDCTL_API=3 etcdctl ... get / --prefix --keys-only | head -20
```

---

## Paso 4 — Explorar el kube-scheduler

```bash
# Ver qué decisiones ha tomado el scheduler
kubectl get events -A --field-selector reason=Scheduled --sort-by=lastTimestamp | tail -10

# En kubeadm, ver el log del scheduler
# kubectl logs -n kube-system kube-scheduler-<master>

# En k3s, está en el log del servidor
multipass exec k3s-server -- sudo journalctl -u k3s --no-pager | grep -i "schedul" | tail -10
```

---

## Paso 5 — Explorar el kube-controller-manager

```bash
# El controller-manager ejecuta bucles de control
# Por ejemplo: si un pod muere, crea uno nuevo para mantener el número de réplicas

# Ver los controladores activos
kubectl get --raw='/metrics' | grep "kube_controller_manager" | head -10

# En kubeadm:
# kubectl logs -n kube-system kube-controller-manager-<master>
```

---

## Paso 6 — Explorar el kubelet (en cada nodo)

```bash
# En un worker
multipass exec k3s-worker -- sudo systemctl status k3s-agent --no-pager

# Logs del kubelet
multipass exec k3s-worker -- sudo journalctl -u k3s-agent -n 20 --no-pager

# En kubeadm:
# sudo systemctl status kubelet
# sudo journalctl -u kubelet -n 20
```

---

## Paso 7 — Explorar el kube-proxy

```bash
# kube-proxy gestiona las reglas de red (iptables/IPVS) para los servicios
# En k3s, corre como parte del agente

# Ver las reglas iptables en un nodo
multipass exec k3s-worker -- sudo iptables -t nat -L KUBE-SERVICES | head -20

# En kubeadm, kube-proxy es un DaemonSet:
# kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
# kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=20
```

---

## Paso 8 — Explorar el CNI (red de pods)

```bash
# En k3s, el CNI es Flannel (incluido)
# Ver las interfaces de red en un nodo
multipass exec k3s-worker -- ip addr show flannel.1 2>&1 || echo "flannel.1 no encontrada"
multipass exec k3s-worker -- ip addr show cni0 2>&1 || echo "cni0 no encontrada"

# Ver las rutas de pods entre nodos
multipass exec k3s-worker -- ip route | grep -E "10.42|flannel"

# En kubeadm, ver el CNI instalado:
# kubectl get pods -n kube-system | grep -E "flannel|calico|weave"
# kubectl get daemonset -n kube-system
```

---

## Paso 9 — Componentes de red adicionales en k3s

```bash
# CoreDNS — el DNS del cluster
kubectl get deployment coredns -n kube-system
kubectl get service kube-dns -n kube-system

# Traefik — el Ingress controller de k3s
kubectl get deployment traefik -n kube-system
kubectl get service traefik -n kube-system

# ServiceLB — el LoadBalancer de k3s (DaemonSet)
kubectl get daemonset svclb-traefik -n kube-system

# metrics-server — para kubectl top
kubectl get deployment metrics-server -n kube-system
```

---

## Limpieza

No hay recursos que limpiar — este lab es de exploración.

---

## Preguntas de reflexión para el instructor

1. ¿Qué componente procesa tu `kubectl get pods`? (pista: solo uno)
2. Si etcd/SQLite se corrompe, ¿qué se pierde? ¿Qué NO se pierde?
3. ¿Por qué el scheduler y el controller-manager solo tienen una instancia activa?
4. ¿Qué es el leader election y por qué lo usan los componentes del control plane?
