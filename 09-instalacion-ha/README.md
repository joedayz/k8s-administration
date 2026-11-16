# Módulo 09 — Instalación, HA y Diseño de Clusters

## Rol del administrador

Instalar y configurar clusters de Kubernetes desde cero es una habilidad fundamental del CKA. El admin necesita:
- Entender qué componentes se instalan y cómo interactúan
- Crear clusters con kubeadm y con k3s
- Unir nodos worker al cluster
- Planificar arquitecturas de Alta Disponibilidad (multi-master)
- Configurar el acceso remoto con kubeconfig

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

### Arquitectura de un cluster Kubernetes

```
┌─────────────────────────────── CONTROL PLANE ───────────────────────────────┐
│                                                                             │
│  kube-apiserver  ←─ único punto de entrada (todo pasa por aquí)             │
│       │                                                                     │
│  etcd           ←─ almacén del estado (la "base de datos" del cluster)     │
│       │                                                                     │
│  kube-scheduler  ←─ decide en qué nodo corre cada pod                        │
│       │                                                                     │
│  kube-controller-manager ←─ ejecuta bucles de control (replicas, nodes...)  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              ┌──────────┐  ┌──────────┐  ┌──────────┐
              │  WORKER  │  │  WORKER  │  │  WORKER  │
              │          │  │          │  │          │
              │ kubelet  │  │ kubelet  │  │ kubelet  │
              │ kube-proxy│ │kube-proxy│ │kube-proxy│
              │ containerd│ │containerd│ │containerd│
              │  (pods)  │  │  (pods)  │  │  (pods)  │
              └──────────┘  └──────────┘  └──────────┘
```

### kubeadm vs k3s

| Aspecto | kubeadm | k3s |
|---------|---------|-----|
| Propósito | Instalación oficial de Kubernetes | Distribución ligera |
| Backend | etcd (dedicado) | SQLite (default) / etcd embebido |
| Componentes | Se instalan por separado | Todo en un binario |
| CNI | Hay que instalarlo manualmente | Traefik + Flannel incluidos |
| Uso en CKA | Es el que se evalúa | Útil para labs rápidos |
| Producción | Sí, es el estándar | Sí, validado para edge/IoT |

### Instalación con kubeadm (workflow del examen CKA)

```bash
# 1. En TODOS los nodos: instalar containerd, kubelet, kubeadm, kubectl
apt-get update && apt-get install -y containerd kubelet kubeadm kubectl

# 2. En el control plane: inicializar el cluster
kubeadm init --pod-network-cidr=10.244.0.0/16

# 3. Configurar kubeconfig
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config

# 4. Instalar CNI (Flannel en este caso)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# 5. En cada worker: unir al cluster
kubeadm join <IP_CONTROL_PLANE>:6443 --token <TOKEN> --discovery-token-ca-cert-hash <HASH>
```

### Instalación con k3s

```bash
# En el server (single-node o primer master)
curl -sfL https://get.k3s.io | sh -

# En cada worker
curl -sfL https://get.k3s.io | K3S_URL=https://<IP>:6443 K3S_TOKEN=<TOKEN> sh -
```

### Alta Disponibilidad (HA)

Un cluster HA tiene **múltiples nodos control plane** para que si uno cae, el cluster sigue funcionando.

| Topología | Descripción | Cuándo usar |
|-----------|-------------|-------------|
| Stacked etcd | etcd corre en cada nodo master | Clusters pequeños/medianos |
| External etcd | etcd en nodos separados | Producción crítica |

```
                  ┌─── Load Balancer (HAProxy/Nginx) ───┐
                  │          VIP: 192.168.1.100          │
                  └───┬──────────┬──────────┬─────────────┘
                      ▼          ▼          ▼
                   Master 1   Master 2   Master 3
                   (etcd)     (etcd)     (etcd)
```

**Requisitos mínimos para HA:** 3 nodos master (quorum de etcd = 2f+1).

---

## Laboratorios

- [Lab Básico](basico/README.md) — Instalación de k3s single-node y join de workers
- [Lab Intermedio](intermedio/README.md) — Exploración de componentes del control plane
- [Lab Avanzado](avanzado/README.md) — Diseño de HA y workflow kubeadm
