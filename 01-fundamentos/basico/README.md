# Lab 01 — Básico: Explorar el cluster

## Objetivo
Familiarizarse con kubectl y entender el estado actual del cluster desde el punto de vista del administrador.

## Duración estimada
30 minutos

---

## Paso 1 — Verificar el estado del cluster

```bash
# Ver nodos y su estado
kubectl get nodes

# Ver nodos con más detalle (IPs, OS, versión)
kubectl get nodes -o wide

# Inspeccionar un nodo específico
kubectl describe node <nombre-del-nodo>
```

**¿Qué busca un admin aquí?**
- Estado `Ready` en todos los nodos
- Versión de kubelet consistente entre nodos
- Capacidad de CPU y memoria disponible
- Condiciones: `MemoryPressure`, `DiskPressure`, `PIDPressure` — todas deben ser `False`

---

## Paso 2 — Ver los componentes del sistema

```bash
# Pods del sistema (control plane, CNI, DNS, etc.)
kubectl get pods -n kube-system

# Ver todos los pods en todos los namespaces
kubectl get pods -A

# ¿Qué namespaces existen por defecto?
kubectl get namespaces
```

**Nota para el admin:** En k3s los namespaces por defecto son:
- `kube-system` — componentes del cluster
- `kube-public` — información pública del cluster
- `kube-node-lease` — heartbeats de los nodos
- `default` — donde van los recursos sin namespace explícito

---

## Paso 3 — Desplegar una aplicación de prueba

```bash
# Aplicar el manifiesto de prueba
kubectl apply -f pod-nginx.yaml

# Verificar que el pod está corriendo
kubectl get pod nginx-test

# Ver los detalles del pod
kubectl describe pod nginx-test

# Ver los logs
kubectl logs nginx-test
```

---

## Paso 4 — Operaciones básicas de diagnóstico

```bash
# Entrar al pod (útil para diagnóstico de red)
kubectl exec -it nginx-test -- /bin/sh

# Desde dentro del pod:
# cat /etc/hosts
# wget -qO- localhost
# exit

# Ver el uso de recursos de los nodos
kubectl top nodes

# Ver el uso de recursos de los pods
kubectl top pods
```

> **Nota:** `kubectl top` requiere metrics-server. En k3s viene incluido.

---

## Paso 5 — Limpiar

```bash
kubectl delete pod nginx-test
```

---

## Verificación

Al finalizar este lab debes poder responder:
- ¿Cuántos nodos tiene el cluster y cuál es su estado?
- ¿Qué pods corren en `kube-system` y para qué sirven?
- ¿Cómo ves los logs de un pod?
- ¿Cómo ves el consumo de CPU/RAM de los nodos?

---

## Preguntas de reflexión para el instructor

1. ¿Qué pasa si un nodo entra en `DiskPressure`? ¿Qué hace el scheduler?
2. ¿Por qué el pod está en el namespace `default`? ¿Es buena práctica?
3. ¿Qué diferencia hay entre `kubectl get` y `kubectl describe`?
