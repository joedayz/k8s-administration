# Lab 07 — Intermedio: Backup y Restore del Cluster

## Objetivo
Hacer un backup completo del estado del cluster, simular pérdida de datos y restaurar desde el backup.

## Duración estimada
60 minutos

---

## Dónde está el estado

Este clúster tiene un solo server. k3s guarda el API en SQLite, a través de kine, en `/var/lib/rancher/k3s/server/db/state.db`. Ahí están los Pods, Deployments, Secrets, RBAC y el resto de objetos.

Mientras `k3s` está parado, `kubectl` desde el Mac no responde. Los workers siguen encendidos y se reconectan al volver el server.

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

`systemctl stop` no siempre vuelca `state.db-wal` dentro de `state.db`. Si copias solo el archivo, el backup puede no tener los objetos que acabas de crear y el restore posterior los borra. El checkpoint mete el journal en `state.db` antes de copiar. La comprobación tiene que imprimir `ultima revision deleted: 0`. Si imprime `None` o `1`, no sigas: esa copia no sirve.

```bash
multipass exec k3s-server -- sudo systemctl stop k3s

multipass exec k3s-server -- sudo python3 - <<'PY'
import sqlite3
con = sqlite3.connect("/var/lib/rancher/k3s/server/db/state.db")
con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
con.commit()
con.close()
print("checkpoint ok")
PY

multipass exec k3s-server -- sudo cp \
  /var/lib/rancher/k3s/server/db/state.db \
  /root/k3s-backup.db

multipass exec k3s-server -- sudo python3 - <<'PY'
import sqlite3
con = sqlite3.connect("file:/root/k3s-backup.db?mode=ro", uri=True)
row = con.execute(
    "select deleted from kine where name='/registry/namespaces/backup-test' order by id desc limit 1"
).fetchone()
print("ultima revision deleted:", None if row is None else row[0])
if row is None or row[0] != 0:
    raise SystemExit("el backup no contiene backup-test")
PY

multipass exec k3s-server -- sudo systemctl start k3s
sleep 15

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

Hay que borrar el archivo y su journal, y poner el backup en un archivo nuevo. Si solo pisas `state.db` y dejas `state.db-wal`, SQLite reaplica el journal de después del backup y el namespace sigue borrado.

```bash
multipass exec k3s-server -- sudo systemctl stop k3s

multipass exec k3s-server -- sudo bash -c '
  set -e
  cp /var/lib/rancher/k3s/server/db/state.db /root/state.db.pre-restore
  rm -f /var/lib/rancher/k3s/server/db/state.db \
        /var/lib/rancher/k3s/server/db/state.db-wal \
        /var/lib/rancher/k3s/server/db/state.db-shm
  cp /root/k3s-backup.db /var/lib/rancher/k3s/server/db/state.db
'

multipass exec k3s-server -- sudo systemctl start k3s
sleep 20

kubectl get namespace backup-test
kubectl get all -n backup-test
kubectl get configmap datos-importantes -n backup-test -o yaml
```

---

## Limpieza

```bash
kubectl delete namespace backup-test
multipass exec k3s-server -- sudo rm -f /root/k3s-backup.db /root/state.db.pre-restore
```

---

## Para llevar a un clúster real

Estos comandos no se ejecutan en las VMs del curso. El backup guarda los objetos del API. Las imágenes, los volúmenes del nodo y los certificados en disco se restauran por otra vía.

**kubeadm.** etcd corre como static pod. El snapshot se toma en un control plane. En un control plane de varios miembros, el restore se repite en cada uno con `--name`, `--initial-cluster` y `--initial-advertise-peer-urls`.

```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup.db

sudo ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup.db --write-out=table

sudo ETCDCTL_API=3 etcdctl snapshot restore /opt/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored
# hostPath en /etc/kubernetes/manifests/etcd.yaml → /var/lib/etcd-restored
```

**OpenShift.** El script del operador envuelve `etcdctl snapshot save` y también guarda los static pods. Se lanza desde un master. El restore es el último recurso y el snapshot tiene que ser de la misma versión z-stream.

```bash
oc debug --as-root node/<master>
chroot /host
/usr/local/bin/cluster-backup.sh /home/core/assets/backup
# snapshot_<fecha>.db y static_kuberesources_<fecha>.tar.gz

sudo -E /usr/local/bin/cluster-restore.sh /home/core/assets/backup
oc adm wait-for-stable-cluster
```

En EKS, GKE o AKS el etcd lo opera el proveedor. El backup de objetos de aplicación se hace con Velero u otra herramienta, no con `etcdctl` desde tu laptop.

---

## Preguntas de reflexión para el instructor

1. ¿Por qué hay que parar k3s para que el backup de `state.db` sea consistente?
2. ¿Con qué frecuencia harías backups en producción? ¿Dónde los guardarías?
3. ¿Qué información queda fuera de `state.db` y habría que restaurar por otra vía?
4. ¿Qué es el RPO (Recovery Point Objective) y cómo afecta a la frecuencia de backup?
