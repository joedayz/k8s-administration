# Lab 01 — Intermedio: Namespaces, recursos y gestión de nodos

## Objetivo
Organizar el cluster con namespaces, aplicar cuotas de recursos y gestionar el ciclo de vida de los nodos como lo haría un administrador en producción.

## Duración estimada
45 minutos

---

## Paso 1 — Crear y organizar namespaces

Como admin, los namespaces son tu herramienta principal de organización y aislamiento.

```bash
# Crear namespaces por entorno
kubectl apply -f namespaces.yaml

# Verificar
kubectl get namespaces
```

---

## Paso 2 — Aplicar ResourceQuota a un namespace

Las `ResourceQuota` evitan que un equipo o aplicación consuma todos los recursos del cluster.

```bash
kubectl apply -f resource-quota.yaml

# Verificar la cuota aplicada
kubectl describe resourcequota -n produccion

# Intentar crear un pod sin limits (debería fallar)
kubectl run test-sin-limits --image=nginx -n produccion
```

**Observa el error:** Cuando hay ResourceQuota activa, todos los pods deben declarar `requests` y `limits`.

---

## Paso 3 — Aplicar LimitRange

`LimitRange` establece defaults de recursos para pods que no los declaran.

```bash
kubectl apply -f limit-range.yaml

# Verificar
kubectl describe limitrange -n produccion

# Ahora sí puede correr sin declarar limits explícitos
kubectl run test-con-defaults --image=nginx:1.25-alpine -n produccion

# Ver qué limits se aplicaron automáticamente
kubectl describe pod test-con-defaults -n produccion | grep -A5 Limits

# Limpiar
kubectl delete pod test-con-defaults -n produccion
```

---

## Paso 4 — Cordon y Drain de nodos

Operaciones esenciales para mantenimiento de nodos (actualizaciones de OS, hardware, etc.).

```bash
# Ver nodos disponibles
kubectl get nodes

# Marcar un nodo como no-schedulable (no acepta nuevos pods)
kubectl cordon <nombre-nodo>

# Verificar — el nodo aparece como SchedulingDisabled
kubectl get nodes

# Drenar el nodo (migra todos los pods a otros nodos)
# --ignore-daemonsets: los DaemonSets no se pueden mover, se ignoran
# --delete-emptydir-data: elimina datos de emptyDir (sin estado)
kubectl drain <nombre-nodo> --ignore-daemonsets --delete-emptydir-data

# Simular mantenimiento (en producción aquí harías el update del OS)
echo "Mantenimiento completado"

# Volver a habilitar el nodo
kubectl uncordon <nombre-nodo>

# Verificar que vuelve a Ready
kubectl get nodes
```

> **Importante para el admin:** En un cluster single-node, el drain fallará si hay pods que no pueden ser reprogramados. Usa `--force` con precaución.

---

## Verificación

```bash
# Ver cuotas de todos los namespaces
kubectl get resourcequota -A

# Ver limitranges de todos los namespaces
kubectl get limitrange -A
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué diferencia hay entre `cordon` y `drain`?
2. ¿Qué pasa con un pod con `PodDisruptionBudget` durante un drain?
3. ¿Por qué es importante tener ResourceQuota en namespaces de producción?
4. ¿Qué ocurre si un namespace no tiene LimitRange y los pods no declaran resources?
