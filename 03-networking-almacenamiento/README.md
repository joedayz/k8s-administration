# Módulo 03 — Networking y Almacenamiento

## Rol del administrador

El admin de Kubernetes es responsable de:
- Que los pods se comuniquen correctamente entre sí y con el exterior
- Que el tráfico externo llegue a las aplicaciones de forma segura
- Que las aplicaciones con estado tengan almacenamiento persistente y confiable
- Que el tráfico sensible esté aislado mediante políticas de red

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

### Modelo de red de Kubernetes

Kubernetes impone tres reglas fundamentales de red:
1. Todos los pods pueden comunicarse entre sí **sin NAT**
2. Los nodos pueden comunicarse con los pods **sin NAT**
3. El IP que ve un pod de sí mismo es el mismo que los demás ven de él

Esto lo implementa el **CNI (Container Network Interface)** — en k3s viene **Flannel** por defecto.

```
Pod A (10.42.0.5) ──── Flannel/CNI ──── Pod B (10.42.1.8)
     namespace-1                              namespace-2
```

### Services — Tipos

| Tipo | Acceso | Uso típico |
|------|--------|------------|
| `ClusterIP` | Solo dentro del cluster | Comunicación interna entre servicios |
| `NodePort` | Desde fuera en puerto del nodo | Labs, desarrollo |
| `LoadBalancer` | IP externa asignada | Producción en cloud |
| `ExternalName` | Alias DNS a servicio externo | Integración con sistemas externos |

### Ingress

El Ingress es el "proxy inverso" de Kubernetes. Permite:
- Enrutar tráfico HTTP/HTTPS por hostname o path
- Terminar TLS en un punto centralizado
- Usar un solo LoadBalancer para múltiples servicios

En k3s viene **Traefik** como Ingress Controller por defecto.

### Network Policies

Sin Network Policies, todos los pods se pueden comunicar entre sí. Con Network Policies puedes:
- Aislar namespaces entre sí
- Permitir solo el tráfico necesario (principio de mínimo privilegio)
- Bloquear tráfico saliente no autorizado

### Almacenamiento — CSI

**CSI (Container Storage Interface)** es el estándar para conectar sistemas de almacenamiento a Kubernetes.

Conceptos clave:
- **PersistentVolume (PV)**: pieza de almacenamiento en el cluster
- **PersistentVolumeClaim (PVC)**: solicitud de almacenamiento por parte de un pod
- **StorageClass**: define cómo y dónde se provisiona el almacenamiento

**Access Modes:**
- `ReadWriteOnce (RWO)`: un nodo puede leer y escribir
- `ReadOnlyMany (ROX)`: múltiples nodos pueden leer
- `ReadWriteMany (RWX)`: múltiples nodos pueden leer y escribir

---

## Laboratorios

- [Lab Básico](basico/README.md) — Services, DNS interno y almacenamiento básico
- [Lab Intermedio](intermedio/README.md) — Ingress con TLS y Network Policies
- [Lab Avanzado](avanzado/README.md) — StorageClasses, PVs y service mesh con Traefik
