# Lab 07 — Avanzado: Upgrade del Cluster y Gestión de Certificados

## Objetivo
Actualizar este clúster k3s sin interrumpir los workloads, e inspeccionar y gestionar los certificados TLS del server.

## Duración estimada
75 minutos

---

## Parte A — Upgrade del cluster k3s

### Paso 1 — Verificar la versión actual

```bash
kubectl get nodes -o wide
multipass exec k3s-server -- k3s --version
# Este clúster está en v1.37.2+k3s1
```

### Paso 2 — Preparar el upgrade (plan de riesgo)

Antes de actualizar, siempre:

```bash
# 1. Backup de state.db. stop no siempre vuelca el WAL: hay que hacer checkpoint.
multipass exec k3s-server -- sudo systemctl stop k3s
multipass exec k3s-server -- sudo python3 -c 'import sqlite3; c=sqlite3.connect("/var/lib/rancher/k3s/server/db/state.db"); c.execute("PRAGMA wal_checkpoint(TRUNCATE)"); c.commit(); c.close()'
multipass exec k3s-server -- sudo cp \
  /var/lib/rancher/k3s/server/db/state.db \
  /root/k3s-pre-upgrade-backup.db
multipass exec k3s-server -- sudo systemctl start k3s
sleep 15

# 2. Verificar que el cluster está sano
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed | grep -v NAME
```

### Paso 3 — Upgrade del server

k3s se actualiza volviendo a ejecutar el script de instalación. El servicio del server se llama `k3s`. Va primero: un worker no puede quedar en una versión más nueva que el server.

`v1.37.2+k3s1` es la versión que ya tiene este clúster. Con ese valor el script reinstala y reinicia, y la release no cambia. Para subir de parche, sustituye `INSTALL_K3S_VERSION` por la release publicada en [github.com/k3s-io/k3s/releases](https://github.com/k3s-io/k3s/releases).

```bash
multipass exec k3s-server -- sudo bash -c \
  'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.37.2+k3s1 sh -'

sleep 20
kubectl get nodes
multipass exec k3s-server -- k3s --version
```

### Paso 4 — Upgrade de los workers (uno a uno)

En los workers el servicio es `k3s-agent`. El unit ya guarda `K3S_URL` y `K3S_TOKEN` en `/etc/systemd/system/k3s-agent.service.env`, así que el script solo cambia el binario. `drain` mueve todos los pods de ese nodo, también los de otros labs. kube-proxy y el CNI van dentro del proceso k3s, no son pods.

```bash
kubectl cordon k3s-worker
kubectl drain k3s-worker --ignore-daemonsets --delete-emptydir-data --grace-period=30

multipass exec k3s-worker -- sudo bash -c \
  'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.37.2+k3s1 sh -'

sleep 20
kubectl uncordon k3s-worker
kubectl get nodes

kubectl cordon k3s-worker2
kubectl drain k3s-worker2 --ignore-daemonsets --delete-emptydir-data --grace-period=30

multipass exec k3s-worker2 -- sudo bash -c \
  'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.37.2+k3s1 sh -'

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

### Paso 6 — Ver caducidad y renovar (k3s)

Los certificados los administra k3s en `k3s-server`. Los de cliente y serving duran 365 días; las CA, 10 años. Si al arrancar k3s a un certificado le quedan menos de 90 días, lo renueva solo.

```bash
multipass exec k3s-server -- sudo k3s certificate check --output table
```

La columna `STATUS` sale `OK`. `client-admin.crt` es el certificado con el que entra `kubectl`. `serving-kube-apiserver.crt` es el del API server.

`k3s certificate rotate` reescribe los certificados en disco. En este lab no hace falta ejecutarlo: el `check` ya los muestra vigentes. Si hubiera que renovarlos:

```bash
multipass exec k3s-server -- sudo k3s certificate rotate
multipass exec k3s-server -- sudo systemctl restart k3s

# k3s reescribe /etc/rancher/k3s/k3s.yaml con el client-admin nuevo
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
multipass exec k3s-server -- sudo rm -f /root/k3s-pre-upgrade-backup.db
```

---

## Para llevar a un clúster real

Estos comandos no se ejecutan en las VMs del curso. El orden se mantiene: primero el control plane, después los workers, y un worker no puede quedar más nuevo que el API.

**kubeadm.** En el primer control plane, `upgrade apply`. En los otros control planes, `upgrade node`. La cadena `<version>` sale de `apt-cache madison kubeadm`. En RHEL el paquete se instala con `dnf`.

```bash
sudo kubeadm upgrade plan
sudo apt-get install -y kubeadm=<version>
sudo kubeadm upgrade apply vX.Y.Z
sudo apt-get install -y kubelet=<version> kubectl=<version>
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Cada worker: drain, los mismos paquetes de kubelet y kubectl, restart, uncordon
```

Los certificados de cliente y serving duran 365 días. `renew all` actualiza `/etc/kubernetes/pki` y `/etc/kubernetes/admin.conf`. Las CA siguen igual. Los static pods leen el certificado al arrancar:

```bash
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all

sudo mkdir -p /tmp/k8s-manifests
sudo mv /etc/kubernetes/manifests/*.yaml /tmp/k8s-manifests/
sleep 20
sudo mv /tmp/k8s-manifests/*.yaml /etc/kubernetes/manifests/
```

**OpenShift.** El canal y la versión destino los aplica el Cluster Version Operator. El Machine Config Pool drena los nodos. Las hojas de certificado las rota la plataforma. `oc get csr` es la cola de los nodos. Forzar una hoja, y esperar a los operadores:

```bash
oc get clusterversion
oc adm upgrade
oc adm upgrade channel stable-4.21
oc adm upgrade --to=4.21.2
oc get mcp

oc get csr
oc adm ocp-certificates regenerate-leaf \
  -n openshift-kube-apiserver secrets localhost-serving-cert-certkey
oc adm wait-for-stable-cluster
```

En EKS, GKE o AKS el control plane y sus certificados los renueva el proveedor. El admin actualiza el node group y drena los workers.

---

## Preguntas de reflexión para el instructor

1. ¿Por qué hay que actualizar `k3s-server` antes que los workers?
2. ¿Qué ocurre si un certificado del apiserver caduca en producción a las 3 AM?
3. ¿Cuánto tiempo tienes para actualizar antes de que tu versión quede fuera de soporte?
4. ¿Qué es la política de N-2 de Kubernetes y qué implica para los upgrades?
