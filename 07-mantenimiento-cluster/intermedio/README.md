# Lab 07 — Intermedio: Backup y Restore del Cluster

## Objetivo
Hacer un backup completo del estado del cluster, simular pérdida de datos y restaurar desde el backup.

## Duración estimada
60 minutos

---

## Contexto: k3s usa SQLite (kine), no etcd

En este lab usamos k3s, que por defecto usa SQLite como backend en lugar de etcd. El proceso de backup es equivalente en concepto — estamos guardando todo el estado del cluster.

> En un cluster kubeadm de producción, el comando sería `etcdctl snapshot save`. La sección final del lab muestra ese workflow para el examen CKA.

---

## Parte A — Backup del cluster k3s

### Paso 1 — Ver el estado actual del cluster

```bash
# Qué tenemos en el cluster
kubectl get all -A | grep -v "kube-system\|traefik" | head -30

# Contar objetos por tipo
kubectl get pods -A --no-headers | wc -l
kubectl get deployments -A --no-headers | wc -l
kubectl get secrets -A --no-headers | wc -l
```

### Paso 2 — Crear recursos que vamos a "perder" y restaurar

```bash
kubectl create namespace backup-test
kubectl apply -f recursos-backup.yaml

kubectl get all -n backup-test
kubectl get configmap datos-importantes -n backup-test -o yaml
```

### Paso 3 — Backup de la base de datos SQLite

```bash
# Parar k3s brevemente para un backup consistente
multipass exec k3s-server -- sudo systemctl stop k3s

# Hacer el backup
multipass exec k3s-server -- sudo cp \
  /var/lib/rancher/k3s/server/db/state.db \
  /tmp/k3s-backup-$(date +%Y%m%d-%H%M).db

# Verificar el backup
multipass exec k3s-server -- sudo ls -lh /tmp/k3s-backup-*.db

# Reiniciar k3s
multipass exec k3s-server -- sudo systemctl start k3s
sleep 15

# Verificar que el cluster volvió
kubectl get nodes
```

---

## Parte B — Simular pérdida de datos y restaurar

### Paso 4 — Borrar los recursos (simulando un desastre)

```bash
kubectl delete namespace backup-test
kubectl get namespace backup-test
# Error: no encontrado — los datos se han "perdido"
```

### Paso 5 — Restaurar desde backup

```bash
# Parar k3s
multipass exec k3s-server -- sudo systemctl stop k3s

# Restaurar la base de datos desde el backup
multipass exec k3s-server -- sudo bash -c \
  "cp /var/lib/rancher/k3s/server/db/state.db /tmp/state.db.pre-restore && \
   cp /tmp/k3s-backup-*.db /var/lib/rancher/k3s/server/db/state.db"

# Reiniciar k3s
multipass exec k3s-server -- sudo systemctl start k3s
sleep 20

# Verificar que los datos volvieron
kubectl get namespace backup-test
kubectl get all -n backup-test
kubectl get configmap datos-importantes -n backup-test -o yaml
```

---

## Parte C — Workflow etcd para el examen CKA

Este es el procedimiento que se pide en el examen CKA con `etcdctl`:

```bash
# En un cluster kubeadm, el etcd corre como pod en kube-system
kubectl get pod -n kube-system | grep etcd

# Variables del entorno etcd
ETCD_ENDPOINTS="https://127.0.0.1:2379"
ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"

# BACKUP
ETCDCTL_API=3 etcdctl \
  --endpoints=$ETCD_ENDPOINTS \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  snapshot save /opt/etcd-backup.db

# Verificar el snapshot
ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup.db --write-out=table

# RESTORE (en caso de desastre)
ETCDCTL_API=3 etcdctl snapshot restore /opt/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored

# Actualizar el static pod de etcd para apuntar al nuevo directorio
# (editar /etc/kubernetes/manifests/etcd.yaml y cambiar el hostPath)
```

---

## Limpieza

```bash
kubectl delete namespace backup-test
multipass exec k3s-server -- sudo rm /tmp/k3s-backup-*.db /tmp/state.db.pre-restore
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué hay que parar k3s/etcd para hacer un backup consistente?
2. ¿Con qué frecuencia harías backups en producción? ¿Dónde los guardarías?
3. ¿Qué información NO está en etcd y tendría que restaurarse por otra vía?
4. ¿Qué es el RPO (Recovery Point Objective) y cómo afecta a la frecuencia de backup?
