# Lab 03 — Avanzado: StorageClasses, aprovisionamiento dinámico y observabilidad de red

## Objetivo
Gestionar almacenamiento dinámico con StorageClasses, entender las políticas de retención y monitorizar el estado de la red del cluster.

## Duración estimada
75 minutos

---

## Parte A — StorageClasses y aprovisionamiento dinámico

### Paso 1 — Explorar StorageClasses existentes

```bash
# Ver StorageClasses disponibles
kubectl get storageclass

# La StorageClass por defecto en k3s es local-path
kubectl describe storageclass local-path
```

**Nota para el admin:** La `local-path` StorageClass de k3s guarda datos en el nodo (`/var/lib/rancher/k3s/storage`). Es válida para single-node pero NO para multi-node (el dato queda atado al nodo).

### Paso 2 — Comparar políticas de retención

```bash
kubectl apply -f storage-classes.yaml

# Crear PVCs con distintas políticas
kubectl apply -f pvcs-comparativa.yaml

kubectl get pvc -n produccion
kubectl get pv
```

### Paso 3 — Demostrar política Retain vs Delete

```bash
# Ver detalles de cada PVC y su PV asociado
kubectl get pvc -n produccion -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.phase,PV:.spec.volumeName,POLICY:.spec.storageClassName'

# Eliminar el PVC con política Delete
kubectl delete pvc datos-delete -n produccion

# El PV se elimina automáticamente
kubectl get pv

# Eliminar el PVC con política Retain
kubectl delete pvc datos-retain -n produccion

# El PV queda en estado Released (datos protegidos)
kubectl get pv
```

**Cuándo usar cada política:**
- `Delete`: datos temporales, caches, entornos de desarrollo
- `Retain`: datos de producción, bases de datos, archivos críticos

### Paso 4 — Recuperar un PV en estado Released

```bash
# Ver el PV liberado
kubectl get pv

# Para reutilizarlo, hay que editar la política manualmente
PV_NAME=$(kubectl get pv | grep Released | awk '{print $1}')

# Eliminar la referencia al PVC anterior (permite que se reasigne)
kubectl patch pv $PV_NAME -p '{"spec":{"claimRef": null}}'

# El PV vuelve a Available
kubectl get pv

# Limpiar
kubectl delete pv $PV_NAME
```

---

## Parte B — Diagnóstico de red avanzado

### Paso 5 — Herramientas de diagnóstico de red

```bash
# Pod de diagnóstico con herramientas de red completas
kubectl apply -f pod-netshoot.yaml

# Una vez corriendo, ejecutar diagnósticos
kubectl exec -n kube-system netshoot -- ping -c3 8.8.8.8
kubectl exec -n kube-system netshoot -- nslookup kubernetes.default.svc.cluster.local
kubectl exec -n kube-system netshoot -- curl -s http://backend-svc.desarrollo.svc.cluster.local
kubectl exec -n kube-system netshoot -- ss -tulnp

# Ver las reglas de red del nodo (desde dentro del nodo k3s)
# sudo iptables -t nat -L KUBE-SERVICES | head -30
```

### Paso 6 — Diagnosticar problemas de conectividad

```bash
# Simular un problema: aplicar una NetworkPolicy muy restrictiva
kubectl apply -f network-policy-bloqueo-total.yaml

# Verificar que el tráfico está bloqueado
kubectl run test-blocked --image=busybox:1.36 --restart=Never -n produccion -- \
  wget -qO- --timeout=5 http://backend-svc.desarrollo.svc.cluster.local

kubectl logs test-blocked -n produccion
kubectl delete pod test-blocked -n produccion

# Ver qué NetworkPolicies hay activas
kubectl get networkpolicy -A

# El admin identifica la política restrictiva y la elimina o ajusta
kubectl delete -f network-policy-bloqueo-total.yaml
```

### Paso 7 — Ver el estado del CNI (Flannel en k3s)

```bash
# Flannel corre como DaemonSet
kubectl get daemonset -n kube-system

# Ver pods de flannel
kubectl get pods -n kube-system | grep flannel

# Ver logs de flannel en un nodo
kubectl logs -n kube-system -l app=flannel --tail=50

# Ver la configuración de red del cluster
kubectl get configmap -n kube-system | grep flannel
```

---

## Limpiar todos los recursos del módulo

```bash
kubectl delete -f pod-netshoot.yaml
kubectl delete pvc --all -n produccion
kubectl delete networkpolicy --all -n desarrollo
kubectl delete networkpolicy --all -n produccion
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué `local-path` no es apta para producción multi-nodo?
2. ¿Qué StorageClass usarías en AWS? ¿En GKE? ¿En on-premises?
3. ¿Cuándo usarías `ReadWriteMany`? ¿Qué sistemas de almacenamiento lo soportan?
4. ¿Cómo detectas que un pod no puede resolver DNS?
