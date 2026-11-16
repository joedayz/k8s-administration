# Lab 09 — Avanzado: Diseño de HA y Workflow kubeadm

## Objetivo
Comprender la arquitectura de Alta Disponibilidad de Kubernetes, practicar el workflow completo de kubeadm y configurar el acceso remoto multi-cluster con kubeconfig.

## Duración estimada
75 minutos

---

## Parte A — Diseño de Alta Disponibilidad

### Paso 1 — Entender los patrones de HA

Un cluster HA necesita que ningún componente sea un punto único de fallo:

```
Patrón 1: Stacked etcd (recomendado para la mayoría)
─────────────────────────────────────────────
     Load Balancer (HAProxy)
            │
    ┌───────┼───────┐
    ▼       ▼       ▼
  Master1  Master2  Master3
  (etcd)   (etcd)   (etcd)
    │       │       │
  Worker1  Worker2  Worker3

Patrón 2: External etcd (máxima resiliencia)
─────────────────────────────────────────────
     Load Balancer
            │
    ┌───────┼───────┐
    ▼       ▼       ▼
  Master1  Master2  Master3
    │       │       │
    └───────┼───────┘
            │
    ┌───────┼───────┐
    ▼       ▼       ▼
  etcd1    etcd2    etcd3   (nodos dedicados)
```

### Paso 2 — Planificar un cluster HA para 3 nodos

```bash
# En este ejercicio diseñamos en papel un cluster HA
# usando las VMs de Multipass como referencia

# IPs actuales del cluster
multipass list | grep -v Name

# Diseño propuesto:
# k3s-server    → Master 1 (control-plane + etcd) — 192.168.252.2
# k3s-worker    → Master 2 (control-plane + etcd) — 192.168.252.3
# k3s-worker2   → Master 3 (control-plane + etcd) — 192.168.252.4
#
# Con k3s cluster-init mode:
# curl -sfL https://get.k3s.io | K3S_TOKEN=secret sh -s - server \
#   --cluster-init --tls-san 192.168.252.100
```

### Paso 3 — Simular HA con k3s cluster-init (referencia)

```bash
# En el primer master:
# curl -sfL https://get.k3s.io | K3S_TOKEN=curso-k8s sh -s - server \
#   --cluster-init

# En los masters 2 y 3:
# curl -sfL https://get.k3s.io | K3S_TOKEN=curso-k8s sh -s - server \
#   --server https://192.168.252.2:6443

# Verificar que etcd tiene 3 nodos:
# kubectl get nodes
# k3s etcd-snapshot ls
```

---

## Parte B — Workflow kubeadm (examen CKA)

### Paso 4 — Preparar nodos para kubeadm

Este es el procedimiento exacto del examen CKA. En k3s no se ejecuta, pero hay que conocerlo:

```bash
# En TODOS los nodos (masters y workers):

# 1. Desactivar swap (kubeadm lo requiere)
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# 2. Cargar módulos del kernel
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# 3. Parámetros sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# 4. Instalar containerd
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

# 5. Instalar kubeadm, kubelet, kubectl
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### Paso 5 — Inicializar el cluster con kubeadm

```bash
# Solo en el primer master:
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Configurar kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Instalar CNI (Flannel)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### Paso 6 — Unir workers con kubeadm

```bash
# En cada worker:
# El comando exacto lo genera kubeadm init al finalizar:
sudo kubeadm join 192.168.1.10:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:...

# Si perdiste el token:
kubeadm token create --print-join-command
```

### Paso 7 — Añadir más masters al cluster HA

```bash
# Generar comando de join para masters
kubeadm token create --print-join-command

# Copiar el certificado CA al nuevo master
# (kubeadm generará un --certificate-key)
kubeadm init phase upload-certs --upload-certs

# En el nuevo master:
sudo kubeadm join 192.168.1.100:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:... \
  --control-plane \
  --certificate-key <CERT_KEY>
```

---

## Parte C — Gestión avanzada de kubeconfig

### Paso 8 — Múltiples contextos

```bash
# Ver el kubeconfig actual
kubectl config view

# Ver contextos disponibles
kubectl config get-contexts

# Si tienes varios clusters, combinar kubeconfigs
export KUBECONFIG=~/.kube/config:~/.kube/k3s-config.yaml

# Cambiar entre contextos
kubectl config use-context default

# Crear un nuevo contexto para un namespace específico
kubectl config set-context admin-produccion \
  --cluster=default \
  --user=default \
  --namespace=produccion

kubectl config use-context admin-produccion
```

### Paso 9 — Generar kubeconfig para un usuario

```bash
# Crear un kubeconfig que solo permite acceso de lectura
# (útil para equipos de monitorización o soporte)

# 1. Crear certificado para el usuario (ver módulo 04)
# 2. Crear kubeconfig manualmente:
kubectl config set-cluster curso-cluster \
  --server=https://192.168.252.2:6443 \
  --certificate-authority=/path/to/ca.crt \
  --embed-certs=true \
  --kubeconfig=/tmp/soporte-ro.kubeconfig

kubectl config set-credentials soporte \
  --client-certificate=/path/to/soporte.crt \
  --client-key=/path/to/soporte.key \
  --embed-certs=true \
  --kubeconfig=/tmp/soporte-ro.kubeconfig

kubectl config set-context soporte-context \
  --cluster=curso-cluster \
  --user=soporte \
  --namespace=desarrollo \
  --kubeconfig=/tmp/soporte-ro.kubeconfig

kubectl config use-context soporte-context \
  --kubeconfig=/tmp/soporte-ro.kubeconfig

# Verificar que funciona
KUBECONFIG=/tmp/soporte-ro.kubeconfig kubectl get pods -n desarrollo
```

---

## Limpieza

El Paso 8 cambia el contexto activo de kubectl a `admin-produccion` — si no lo revalidas, los comandos de los labs siguientes se ejecutarían contra el namespace `produccion` en lugar de `default` sin que se note en pantalla. El kubeconfig temporal del Paso 9 usa rutas de certificado inexistentes (es solo de referencia) y vive en `--kubeconfig=/tmp/...`, así que no toca tu configuración principal, pero igual lo borramos.

```bash
kubectl config use-context default
kubectl config delete-context admin-produccion
rm -f /tmp/soporte-ro.kubeconfig
```

---

## Referencia: Load Balancer para HA con HAProxy

```haproxy
# /etc/haproxy/haproxy.cfg
frontend k8s-api
    bind *:6443
    mode tcp
    default_backend k8s-masters

backend k8s-masters
    mode tcp
    option tcp-check
    server master1 192.168.252.2:6443 check
    server master2 192.168.252.3:6443 check
    server master3 192.168.252.4:6443 check
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué necesitas mínimo 3 masters para HA y no 2?
2. ¿Qué es el quórum de etcd y qué pasa si lo pierdes?
3. ¿Para qué sirve el load balancer delante de los masters?
4. ¿Cómo rotarías el token de kubeadm join sin romper los workers existentes?
