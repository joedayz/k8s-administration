# Módulo 07 — Mantenimiento del Cluster

## Rol del administrador

El mantenimiento del cluster es responsabilidad exclusiva del admin. Un fallo en este proceso puede dejar el cluster sin servicio. Las tareas clave son:
- Actualizar el cluster sin interrumpir los workloads (rolling upgrade)
- Hacer y restaurar backups del estado del cluster (etcd/SQLite)
- Gestionar el ciclo de vida de los nodos: cordon, drain, uncordon
- Administrar certificados TLS del cluster (caducan cada año)

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

### Flujo de mantenimiento de un nodo

```
1. kubectl cordon <nodo>    → SchedulingDisabled: no entran pods nuevos
2. kubectl drain <nodo>     → Pods existentes migran a otros nodos
3. [mantenimiento: OS upgrade, parche, reinicio...]
4. kubectl uncordon <nodo>  → El nodo vuelve a aceptar pods
```

### Backup del estado del cluster

El estado de Kubernetes se almacena en etcd (en clusters kubeadm) o en SQLite/kine (en k3s).

| Cluster | Backend | Comando backup |
|---------|---------|---------------|
| kubeadm | etcd | `etcdctl snapshot save backup.db` |
| k3s | SQLite (kine) | `cp /var/lib/rancher/k3s/server/db/state.db backup.db` |
| k3s cluster-init | etcd embebido | `k3s etcd-snapshot save` |

**Regla de oro:** un backup de etcd es un backup de TODO el cluster (Pods, Deployments, Secrets, RBAC...). Sin él, un fallo del control plane es irrecuperable.

### Upgrade del cluster (kubeadm)

El proceso de upgrade en un cluster kubeadm tiene un orden estricto:
1. Primero el **control plane** (kubeadm upgrade apply)
2. Luego cada **worker** uno a uno (drain → upgrade → uncordon)

En k3s, el upgrade se realiza reinstalando k3s con el script oficial apuntando a la nueva versión.

### Gestión de certificados

Los certificados del cluster caducan cada **365 días** en kubeadm. Síntomas de un certificado caducado:
- `kubectl` devuelve `x509: certificate has expired`
- Los componentes del control plane no arrancan

```bash
# Ver cuándo caducan los certificados (kubeadm)
kubeadm certs check-expiration

# Renovar todos los certificados
kubeadm certs renew all
```

---

## Laboratorios

- [Lab Básico](basico/README.md) — Cordon, drain y uncordon de nodos
- [Lab Intermedio](intermedio/README.md) — Backup y restore del cluster
- [Lab Avanzado](avanzado/README.md) — Upgrade del cluster y gestión de certificados
