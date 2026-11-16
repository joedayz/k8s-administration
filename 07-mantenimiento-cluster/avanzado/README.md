# Lab 07 — Avanzado: Upgrade del Cluster y Gestión de Certificados

## Objetivo
Actualizar el cluster de Kubernetes sin interrumpir los workloads, e inspeccionar y gestionar los certificados TLS que mantienen seguro el cluster.

## Duración estimada
75 minutos

---

## Parte A — Upgrade del cluster k3s

### Paso 1 — Verificar la versión actual

```bash
kubectl version
kubectl get nodes -o wide
# Anotar la versión actual: v1.37.x+k3s1
```

### Paso 2 — Preparar el upgrade (plan de riesgo)

Antes de actualizar, siempre:

```bash
# 1. Hacer un backup del estado
multipass exec k3s-server -- sudo systemctl stop k3s
multipass exec k3s-server -- sudo cp \
  /var/lib/rancher/k3s/server/db/state.db \
  /tmp/k3s-pre-upgrade-backup.db
multipass exec k3s-server -- sudo systemctl start k3s
sleep 15

# 2. Verificar que el cluster está sano
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed | grep -v NAME
```

### Paso 3 — Upgrade del control plane (server)

En k3s, el upgrade se hace reinstalando con la nueva versión:

```bash
# En el nodo server
multipass exec k3s-server -- sudo bash -c \
  'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.37.2+k3s1 sh -'

# Verificar que el server está en la nueva versión
sleep 20
kubectl get nodes
multipass exec k3s-server -- sudo k3s --version
```

### Paso 4 — Upgrade de los workers (uno a uno)

```bash
# Worker 1 — cordon primero
kubectl cordon k3s-worker
kubectl drain k3s-worker --ignore-daemonsets --delete-emptydir-data --grace-period=30

# Upgrade del worker
K3S_TOKEN=$(multipass exec k3s-server -- sudo cat /var/lib/rancher/k3s/server/node-token)
SERVER_IP="192.168.252.2"

multipass exec k3s-worker -- sudo bash -c \
  "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.37.2+k3s1 \
   K3S_URL=https://${SERVER_IP}:6443 \
   K3S_TOKEN=${K3S_TOKEN} sh -"

sleep 20
kubectl uncordon k3s-worker
kubectl get nodes

# Repetir para k3s-worker2
kubectl cordon k3s-worker2
kubectl drain k3s-worker2 --ignore-daemonsets --delete-emptydir-data --grace-period=30

multipass exec k3s-worker2 -- sudo bash -c \
  "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.37.2+k3s1 \
   K3S_URL=https://${SERVER_IP}:6443 \
   K3S_TOKEN=${K3S_TOKEN} sh -"

sleep 20
kubectl uncordon k3s-worker2
kubectl get nodes
```

---

## Parte B — Gestión de certificados TLS

### Paso 5 — Inspeccionar los certificados del cluster

```bash
# Ver todos los certificados del server
multipass exec k3s-server -- sudo ls /var/lib/rancher/k3s/server/tls/

# Ver fechas de expiración de los certificados críticos
multipass exec k3s-server -- sudo openssl x509 \
  -in /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt \
  -noout -dates

multipass exec k3s-server -- sudo openssl x509 \
  -in /var/lib/rancher/k3s/server/tls/client-admin.crt \
  -noout -dates

# Quién firmó el certificado
multipass exec k3s-server -- sudo openssl x509 \
  -in /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt \
  -noout -issuer -subject
```

### Paso 6 — Workflow CKA: certificados en kubeadm

Este es el procedimiento del examen CKA. Muestra conceptualmente lo que harías en un cluster kubeadm:

```bash
# Ver expiración de todos los certificados (kubeadm)
kubeadm certs check-expiration

# Resultado típico:
# CERTIFICATE                EXPIRES                  RESIDUAL TIME
# admin.conf                 Nov 09, 2027 20:23 UTC   364d
# apiserver                  Nov 09, 2027 20:23 UTC   364d
# apiserver-etcd-client      Nov 09, 2027 20:23 UTC   364d
# etcd-ca                    Nov 07, 2036 20:23 UTC   10y

# Renovar TODOS los certificados (hacerlo 30 días antes de que caduquen)
kubeadm certs renew all

# Después de renovar, reiniciar los componentes del control plane
# (en un cluster kubeadm se reinician los static pods automáticamente)
```

### Paso 7 — Ver el kubeconfig y sus certificados

```bash
# El kubeconfig contiene certificados del cliente admin
kubectl config view --raw | grep client-certificate-data | \
  awk '{print $2}' | base64 -d | \
  openssl x509 -noout -dates -subject

# Ver todos los contextos disponibles
kubectl config get-contexts

# Ver el contexto actual
kubectl config current-context
```

### Paso 8 — Rotar el kubeconfig del admin

```bash
# Crear un nuevo kubeconfig de emergencia desde el server
multipass exec k3s-server -- sudo cat /etc/rancher/k3s/k3s.yaml > /tmp/k3s-emergency.yaml
sed -i '' 's/127.0.0.1/192.168.252.2/g' /tmp/k3s-emergency.yaml

# Validar acceso con el nuevo kubeconfig
KUBECONFIG=/tmp/k3s-emergency.yaml kubectl get nodes

# Limpiar
rm /tmp/k3s-emergency.yaml
```

---

## Limpieza

```bash
multipass exec k3s-server -- sudo rm -f /tmp/k3s-pre-upgrade-backup.db
```

---

## Referencia: orden de upgrade en kubeadm (examen CKA)

```
1. kubeadm upgrade plan                    → ver versiones disponibles
2. apt update && apt install kubeadm=X.Y.Z → actualizar kubeadm
3. kubeadm upgrade apply vX.Y.Z            → upgrade del control plane
4. apt install kubelet=X.Y.Z kubectl=X.Y.Z → actualizar kubelet y kubectl
5. systemctl restart kubelet
6. [Por cada worker]: drain → apt install kubelet → systemctl restart → uncordon
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué hay que actualizar el control plane ANTES que los workers?
2. ¿Qué ocurre si un certificado del apiserver caduca en producción a las 3 AM?
3. ¿Cuánto tiempo tienes para actualizar antes de que tu versión quede fuera de soporte?
4. ¿Qué es la política de N-2 de Kubernetes y qué implica para los upgrades?
