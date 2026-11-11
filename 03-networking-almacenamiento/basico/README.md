# Lab 03 — Básico: Services, DNS interno y almacenamiento

## Objetivo
Entender cómo se comunican los pods entre sí, cómo funciona el DNS interno del cluster y cómo persistir datos con volúmenes.

## Duración estimada
45 minutos

---

## Parte A — Comunicación entre servicios

### Paso 1 — Desplegar frontend y backend

```bash
kubectl apply -f app-frontend.yaml
kubectl apply -f app-backend.yaml

kubectl get pods -n desarrollo
kubectl get services -n desarrollo
```

### Paso 2 — Verificar DNS interno

El DNS interno de Kubernetes sigue el patrón:
`<servicio>.<namespace>.svc.cluster.local`

```bash
# Ejecutar un pod temporal para probar conectividad
kubectl run network-test --image=busybox:1.36 --restart=Never -n desarrollo -- \
  sh -c "
    echo '=== DNS del backend ==='
    nslookup backend-svc.desarrollo.svc.cluster.local
    echo '=== Conectividad HTTP ==='
    wget -qO- http://backend-svc.desarrollo.svc.cluster.local
  "

kubectl logs network-test -n desarrollo
kubectl delete pod network-test -n desarrollo
```

### Paso 3 — Exponer con NodePort (acceso desde fuera del cluster)

```bash
kubectl apply -f service-nodeport.yaml

# Ver el puerto asignado
kubectl get service frontend-nodeport -n desarrollo

# Obtener la IP del nodo
kubectl get nodes -o wide

# Acceder desde tu Mac (reemplaza IP y PUERTO)
# curl http://<IP-NODO>:<NODEPORT>
```

---

## Parte B — Almacenamiento persistente

### Paso 4 — Crear un PersistentVolume y PVC

```bash
kubectl apply -f storage.yaml

# Ver el PV y PVC
kubectl get pv
kubectl get pvc -n desarrollo

# El PVC debe estar en estado Bound
```

### Paso 5 — Usar el PVC en un pod

```bash
kubectl apply -f pod-con-storage.yaml

# Escribir datos en el volumen
kubectl exec -n desarrollo pod-storage -- sh -c "echo 'datos persistentes' > /datos/archivo.txt"

# Verificar que los datos están ahí
kubectl exec -n desarrollo pod-storage -- cat /datos/archivo.txt

# Eliminar el pod y recrearlo
kubectl delete pod pod-storage -n desarrollo
kubectl apply -f pod-con-storage.yaml

# Los datos siguen ahí
kubectl exec -n desarrollo pod-storage -- cat /datos/archivo.txt
```

---

## Verificación

```bash
kubectl get services -n desarrollo
kubectl get pvc -n desarrollo
kubectl get pv
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué el DNS interno usa el patrón `servicio.namespace.svc.cluster.local`?
2. ¿Qué diferencia hay entre `ClusterIP` y `NodePort` para un admin?
3. ¿Qué pasa con los datos de un PVC cuando se elimina el pod?
4. ¿Y si se elimina el PVC? ¿Y el PV?
