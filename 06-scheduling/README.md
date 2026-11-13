# Módulo 06 — Scheduling Avanzado

## Rol del administrador

El scheduler decide dónde corre cada pod. Como admin necesitas:
- Controlar en qué nodos se despliegan workloads específicos (seguridad, rendimiento)
- Aislar cargas de trabajo sensibles en nodos dedicados
- Garantizar que agentes de sistema corran en TODOS los nodos
- Gestionar prioridades cuando el cluster está bajo presión de recursos

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

### ¿Cómo decide el scheduler dónde poner un pod?

El kube-scheduler sigue dos fases:

```
1. FILTRADO   → elimina nodos que NO pueden ejecutar el pod
               (recursos insuficientes, taints sin toleración, affinity...)
2. PUNTUACIÓN → rankea los nodos restantes y elige el mejor
               (balanceo de carga, afinidad preferida...)
```

### Taints y Tolerations

Los **taints** marcan un nodo para repeler pods. Las **tolerations** permiten a un pod ignorar ese rechazo.

```
Nodo con taint  ──repele──▶  Pod sin toleración  (no se agenda)
                             Pod con toleración   (sí se agenda)
```

| Efecto | Comportamiento |
|--------|---------------|
| `NoSchedule` | Pods nuevos sin toleración NO se agendan en el nodo |
| `PreferNoSchedule` | Se intenta evitar el nodo pero no es obligatorio |
| `NoExecute` | Pods sin toleración son expulsados del nodo |

**Caso de uso real:** nodo dedicado a base de datos, nodo de GPU, nodo de control-plane.

### Node Affinity y Pod Affinity

A diferencia de NodeSelector (simple igualdad), la **affinity** permite expresiones complejas:

| Tipo | Qué hace |
|------|----------|
| `requiredDuringScheduling...` | Obligatorio — pod no arranca si no hay nodo que cumpla |
| `preferredDuringScheduling...` | Preferido — el scheduler lo intenta pero no falla |
| `podAffinity` | El pod quiere estar JUNTO a otros pods con ciertos labels |
| `podAntiAffinity` | El pod quiere estar LEJOS de otros pods (alta disponibilidad) |

### DaemonSet

Un DaemonSet garantiza que **exactamente un pod** corre en cada nodo del cluster (o en los nodos seleccionados). Ideal para:
- Agentes de monitoreo (node-exporter, Datadog agent)
- Agentes de logs (Fluentd, Filebeat)
- Agentes de red (kube-proxy, CNI plugins)

### PriorityClass

Cuando el cluster está saturado, el scheduler expulsa pods de baja prioridad para hacer sitio a los de alta prioridad. Las PriorityClasses permiten definir esta jerarquía.

```
PriorityClass "critico"      value: 1000000  ← nunca se expulsa
PriorityClass "normal"       value: 100
PriorityClass "batch-jobs"   value: 10       ← primero en ser expulsado
```

### Static Pods

Los static pods son gestionados directamente por **kubelet**, sin pasar por el API server. Se definen como YAML en `/etc/kubernetes/manifests/`. Así arrancan los componentes del control plane (kube-apiserver, etcd, etc.) en clusters kubeadm. En k3s, el equivalente es `/var/lib/rancher/k3s/server/manifests/`.

---

## Laboratorios

- [Lab Básico](basico/README.md) — Taints, Tolerations y NodeSelector
- [Lab Intermedio](intermedio/README.md) — Node Affinity, Pod AntiAffinity y DaemonSets
- [Lab Avanzado](avanzado/README.md) — PriorityClass, Static Pods y Topology Spread
