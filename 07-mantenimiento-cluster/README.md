# Módulo 07 — Mantenimiento del Cluster

## Rol del administrador

El mantenimiento del cluster es responsabilidad exclusiva del admin. Un fallo en este proceso puede dejar el cluster sin servicio. Las tareas clave son:
- Actualizar el cluster sin interrumpir los workloads (rolling upgrade)
- Hacer y restaurar backups del estado del cluster (SQLite, `state.db`)
- Gestionar el ciclo de vida de los nodos: cordon, drain, uncordon
- Administrar certificados TLS del cluster (caducan cada año)

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

El laboratorio se ejecuta en k3s. En cada tema, debajo, está el mismo trabajo en kubeadm (Kubernetes vanilla) y en OpenShift, para llevarlo a un clúster de trabajo. Esos comandos no se corren en las VMs de este curso.

### Flujo de mantenimiento de un nodo

```
1. kubectl cordon <nodo>    → SchedulingDisabled: no entran pods nuevos
2. kubectl drain <nodo>     → Pods existentes migran a otros nodos
3. [mantenimiento: OS upgrade, parche, reinicio...]
4. kubectl uncordon <nodo>  → El nodo vuelve a aceptar pods
```

En kubeadm los comandos son los mismos: `kubectl cordon`, `kubectl drain`, `kubectl uncordon`. En OpenShift el equivalente es `oc adm cordon`, `oc adm drain` y `oc adm uncordon`. El taint `node.kubernetes.io/unschedulable` queda en el objeto Node y sobrevive a un reboot.

### Backup del estado del cluster

Este clúster tiene un solo server. k3s guarda el API en SQLite, a través de kine:

```
/var/lib/rancher/k3s/server/db/state.db
```

Ahí están los Pods, Deployments, Secrets, RBAC y el resto de objetos. Para una copia consistente hay que parar `k3s`: al salir, vuelca el journal (`state.db-wal`) dentro de `state.db`.

```bash
sudo systemctl stop k3s
sudo cp /var/lib/rancher/k3s/server/db/state.db /root/k3s-backup.db
sudo systemctl start k3s
```

**Regla de oro:** esa copia es el backup de todos los objetos del API. Sin ella, un fallo del server es irrecuperable. Quedan fuera las imágenes, los datos de los volúmenes en el nodo y los certificados de `/var/lib/rancher/k3s/server/tls/`.

Al restaurar, borra `state.db-wal` y `state.db-shm` antes de arrancar. Si los dejas, SQLite reaplica el journal posterior al backup.

**kubeadm.** El estado vive en etcd, como static pod. El backup se toma en un control plane, con el certificado de etcd:

```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup.db

sudo ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup.db --write-out=table
```

Restaurar en un control plane único apunta el static pod al directorio nuevo. En un control plane de varios miembros hay que repetir el restore en cada uno con `--name`, `--initial-cluster` y `--initial-advertise-peer-urls`:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot restore /opt/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored
# En /etc/kubernetes/manifests/etcd.yaml, el hostPath del data-dir
# pasa a /var/lib/etcd-restored. kubelet recrea el static pod.
```

**OpenShift.** etcd también es un static pod, y el backup lo hace el script del operador, desde un nodo master (`oc debug --as-root node/<master>` y `chroot /host`):

```bash
/usr/local/bin/cluster-backup.sh /home/core/assets/backup
# Deja snapshot_<fecha>.db y static_kuberesources_<fecha>.tar.gz
```

`cluster-restore.sh` devuelve el clúster a ese instante. Es el último recurso: el backup tiene que ser de la misma versión z-stream (un 4.21.2 se restaura con un snapshot tomado en 4.21.2) y durante el restore el API no responde.

```bash
sudo -E /usr/local/bin/cluster-restore.sh /home/core/assets/backup
oc adm wait-for-stable-cluster
```

### Upgrade del cluster

k3s se actualiza volviendo a ejecutar el script de instalación, con `INSTALL_K3S_VERSION`. En este clúster la versión instalada es `v1.37.2+k3s1`.

1. Backup de `state.db` con `k3s` parado
2. Primero el **server** (`k3s-server`, servicio `k3s`)
3. Luego cada **worker**, uno a uno: cordon → drain → mismo script → uncordon (servicio `k3s-agent`)

El server tiene que quedar en la versión nueva antes que los workers. Un agent no puede ir por delante del server. El unit de cada worker ya tiene `K3S_URL` y `K3S_TOKEN`; el upgrade no los vuelve a pasar.

**kubeadm.** Primero el control plane, después cada worker. En el primer control plane se usa `upgrade apply`. En los demás, `upgrade node`. La versión exacta del paquete sale de `apt-cache madison kubeadm` (en RHEL, `dnf list kubeadm`).

```bash
kubectl drain <control-plane> --ignore-daemonsets
sudo apt-get update
sudo apt-get install -y kubeadm=<version>
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply vX.Y.Z
sudo apt-get install -y kubelet=<version> kubectl=<version>
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl uncordon <control-plane>

# En cada worker
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data
sudo apt-get install -y kubelet=<version> kubectl=<version>
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl uncordon <worker>
```

**OpenShift.** El upgrade lo hace el Cluster Version Operator. El Machine Config Pool drena los nodos solo. La versión destino tiene que existir en el canal:

```bash
oc get clusterversion
oc adm upgrade
oc adm upgrade channel stable-4.21
oc adm upgrade --to=4.21.2
oc get mcp
oc get clusteroperators
```

En EKS, GKE o AKS el control plane lo sube el proveedor. El admin drena los workers o deja que el node group los reemplace. Ahí no se usa `kubeadm upgrade` ni el script de k3s.

### Gestión de certificados

Los certificados de cliente y de serving caducan a los **365 días**. Las CA duran 10 años. Síntomas de un certificado caducado:
- `kubectl` devuelve `x509: certificate has expired`
- `k3s` no arranca

Se administran en `k3s-server`. Si al arrancar a un certificado le quedan menos de 90 días, k3s lo renueva solo.

```bash
# Ver cuándo caducan
sudo k3s certificate check --output table

# Forzar la renovación de todos y cargar los nuevos
sudo k3s certificate rotate
sudo systemctl restart k3s
```

**kubeadm.** Los de cliente y serving también duran 365 días. `renew all` reescribe los certificados en `/etc/kubernetes/pki` y actualiza `/etc/kubernetes/admin.conf`. Las CA quedan igual. Los static pods cargan el certificado al arrancar, así que hay que recrearlos:

```bash
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all

sudo mkdir -p /tmp/k8s-manifests
sudo mv /etc/kubernetes/manifests/*.yaml /tmp/k8s-manifests/
sleep 20
sudo mv /tmp/k8s-manifests/*.yaml /etc/kubernetes/manifests/
```

**OpenShift.** Las hojas las rota la plataforma. `oc get csr` muestra las peticiones de los nodos pendientes de aprobar (`oc adm certificate approve <csr>`). Forzar la regeneración de una hoja es un cambio de clúster, y después hay que esperar a que los operadores vuelvan:

```bash
oc adm ocp-certificates regenerate-leaf \
  -n openshift-kube-apiserver secrets localhost-serving-cert-certkey
oc adm wait-for-stable-cluster
```

Rotar un signer (`regenerate-top-level`) es un procedimiento de recuperación, con reinicio de nodos. Queda fuera del día a día.

---

## Laboratorios

- [Lab Básico](basico/README.md) — Cordon, drain y uncordon de nodos
- [Lab Intermedio](intermedio/README.md) — Backup y restore del cluster
- [Lab Avanzado](avanzado/README.md) — Upgrade del cluster y gestión de certificados
