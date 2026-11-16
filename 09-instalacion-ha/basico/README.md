# Lab 09 — Básico: Instalación de k3s y Join de Workers

## Objetivo
Instalar un cluster de Kubernetes desde cero con k3s y añadir nodos worker. Verificar que todos los componentes funcionan correctamente.

## Duración estimada
50 minutos

---

## Paso 1 — Verificar prerrequisitos en el nodo server

```bash
# Entrar al server
multipass shell k3s-server

# Verificar que cumple los requisitos
uname -a                    # Linux x86_64
free -h                     # Mínimo 2GB RAM
df -h /                     # Mínimo 10GB disco
sudo sysctl net.ipv4.ip_forward  # Debe ser 1
```

---

## Paso 2 — Instalar k3s en el server

```bash
# En el server — instalación con un comando
sudo bash -c "curl -sfL https://get.k3s.io > /tmp/install.sh && \
  chmod +x /tmp/install.sh && \
  INSTALL_K3S_EXEC='--write-kubeconfig-mode=644' /tmp/install.sh"

# Verificar que el servicio está corriendo
sudo systemctl status k3s --no-pager

# Verificar que el cluster responde
sudo k3s kubectl get nodes
# Debe mostrar k3s-server en Ready
```

---

## Paso 3 — Obtener el token y la IP del server

```bash
# Token necesario para que los workers se unan
sudo cat /var/lib/rancher/k3s/server/node-token

# IP del server
hostname -I | awk '{print $1}'
# Anota ambos valores: TOKEN y IP_SERVER

# Salir del server
exit
```

---

## Paso 4 — Unir un worker al cluster

```bash
# Entrar al worker
multipass shell k3s-worker

# Instalar k3s como agente (worker)
# Reemplazar IP_SERVER y TOKEN con los valores del paso anterior
sudo bash -c "curl -sfL https://get.k3s.io > /tmp/install.sh && \
  chmod +x /tmp/install.sh && \
  K3S_URL=https://<IP_SERVER>:6443 K3S_TOKEN=<TOKEN> /tmp/install.sh"

# Verificar que el agente está corriendo
sudo systemctl status k3s-agent --no-pager

exit
```

---

## Paso 5 — Verificar el cluster desde tu Mac

```bash
# Actualizar kubeconfig (si no lo tienes ya configurado)
multipass exec k3s-server -- sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/k3s-config.yaml
sed -i '' 's/127.0.0.1/192.168.252.2/g' ~/.kube/k3s-config.yaml

export KUBECONFIG=~/.kube/k3s-config.yaml

# Ver todos los nodos
kubectl get nodes -o wide
# Debe mostrar k3s-server (control-plane) y k3s-worker (worker)

# Ver los pods del sistema
kubectl get pods -A
# CoreDNS, local-path-provisioner, metrics-server, traefik
```

---

## Paso 6 — Unir el segundo worker

```bash
multipass shell k3s-worker2

sudo bash -c "curl -sfL https://get.k3s.io > /tmp/install.sh && \
  chmod +x /tmp/install.sh && \
  K3S_URL=https://192.168.252.2:6443 K3S_TOKEN=<TOKEN> /tmp/install.sh"

exit
```

Desde tu Mac:

```bash
kubectl get nodes -o wide
# Tres nodos: k3s-server, k3s-worker, k3s-worker2
```

---

## Paso 7 — Verificar que todo funciona end-to-end

```bash
# Desplegar una app de prueba
kubectl create namespace install-test
kubectl create deployment nginx --image=nginx:alpine --replicas=3 -n install-test
sleep 10

# Verificar que los pods se distribuyen entre los nodos
kubectl get pods -n install-test -o wide

# Crear un servicio y probar acceso
kubectl expose deployment nginx --port=80 -n install-test
kubectl run test --image=busybox:1.36 --rm -it -n install-test -- \
  sh -c "wget -qO- http://nginx --timeout=5"

# Limpiar
kubectl delete namespace install-test
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué diferencias hay entre k3s y kubeadm en cuanto a componentes instalados?
2. ¿Para qué sirve el token de k3s/node-token? ¿Cómo lo rotarías?
3. ¿Qué pasa si el nodo server se cae? ¿Pueden los workers seguir sirciendo tráfico?
4. ¿Cómo desinstalarías k3s completamente de un nodo?
