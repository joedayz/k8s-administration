# Lab 05 — Avanzado: CRDs, Operadores y Troubleshooting

## Objetivo
Entender cómo los operadores extienden Kubernetes, instalar un operador real, y dominar la metodología de troubleshooting bajo presión.

## Duración estimada
90 minutos

---

## Parte A — CRDs y Operadores

### Paso 1 — Explorar CRDs existentes en el cluster

```bash
# Ver todos los CRDs instalados
kubectl get crd

# Los CRDs son la API extendida de Kubernetes
# Cada CRD define un nuevo tipo de objeto
kubectl api-resources | grep -v "^NAME"
```

### Paso 2 — Crear un CRD simple

```bash
kubectl apply -f crd-aplicacion.yaml

# Ver el nuevo tipo de recurso
kubectl get crd aplicaciones.labs.k8s.io
kubectl api-resources | grep aplicaciones

# Crear un objeto del nuevo tipo
kubectl apply -f objeto-aplicacion.yaml

# Tratarlo como cualquier otro objeto de Kubernetes
kubectl get aplicaciones -A
kubectl describe aplicacion mi-app -n desarrollo
```

### Paso 3 — Instalar el operador de cert-manager

cert-manager es un operador que gestiona certificados TLS automáticamente — muy usado en producción.

```bash
# Instalar cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Esperar a que esté listo
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=3m
kubectl get pods -n cert-manager

# Ver los CRDs que instaló cert-manager
kubectl get crd | grep cert-manager
```

### Paso 4 — Usar cert-manager para crear un certificado

```bash
# Crear un Issuer (emisor de certificados autofirmado para lab)
kubectl apply -f cert-issuer.yaml

# Crear un Certificate
kubectl apply -f certificado.yaml

# El operador crea el Secret con el certificado automáticamente
kubectl get certificate -n desarrollo
kubectl get secret app-tls-cert -n desarrollo

# Ver cómo el operador reconcilia: si eliminas el Secret, lo recrea
kubectl delete secret app-tls-cert -n desarrollo
sleep 10
kubectl get secret app-tls-cert -n desarrollo   # vuelve a existir
```

---

## Parte B — Troubleshooting avanzado

### Escenario 1 — Pod en CrashLoopBackOff

```bash
kubectl apply -f escenario-crashloop.yaml

# Síntomas
kubectl get pods -n desarrollo | grep crash

# Diagnóstico
kubectl describe pod pod-crashloop -n desarrollo
kubectl logs pod-crashloop -n desarrollo
kubectl logs pod-crashloop -n desarrollo --previous  # logs del crash anterior

# Causa: el comando falla siempre
# Solución: corregir el comando
kubectl delete pod pod-crashloop -n desarrollo
```

### Escenario 2 — Pod en Pending (recursos insuficientes)

```bash
kubectl apply -f escenario-pending.yaml

# Síntomas
kubectl get pods -n desarrollo | grep pending

# Diagnóstico
kubectl describe pod pod-pending -n desarrollo
# Buscar: "Insufficient cpu" o "Insufficient memory" en Events

# En single-node: el pod pide más recursos de los que hay disponibles
kubectl describe node | grep -A5 "Allocated resources"

# Solución: reducir los requests del pod
kubectl delete pod pod-pending -n desarrollo
```

### Escenario 3 — Service no enruta tráfico

```bash
kubectl apply -f escenario-service-roto.yaml

# El pod está Running pero el Service no funciona
kubectl get pods -n desarrollo -l app=servicio-roto
kubectl get service servicio-roto-svc -n desarrollo

# Diagnóstico: el selector del Service no coincide con los labels del pod
kubectl describe service servicio-roto-svc -n desarrollo
# Buscar: "Endpoints: <none>"

kubectl get pods -n desarrollo -l app=servicio-roto --show-labels
# El problema: el Service tiene selector "app: servicio-roto" 
# pero el pod tiene label "app: servicio-roto-v2"

# Solución
kubectl patch service servicio-roto-svc -n desarrollo \
  --type merge \
  -p '{"spec":{"selector":{"app":"servicio-roto-v2"}}}'

# Verificar que ahora tiene endpoints
kubectl describe service servicio-roto-svc -n desarrollo | grep Endpoints

# Limpiar
kubectl delete -f escenario-service-roto.yaml
```

### Escenario 4 — Nodo con problemas de disco

```bash
# Simular disco lleno en un nodo (diagnóstico sin causar daño real)
kubectl describe node k3s-server | grep -A5 "Conditions:"

# Si DiskPressure = True:
# 1. Entrar al nodo
# multipass shell k3s-server

# 2. Ver qué ocupa espacio
# df -h
# du -sh /var/lib/rancher/k3s/*

# 3. Limpiar imágenes no usadas
# sudo crictl rmi --prune

# 4. Verificar que la condición vuelve a False
kubectl describe node k3s-server | grep DiskPressure
```

### Cheatsheet de troubleshooting para el admin

```bash
# ==========================================
# DIAGNÓSTICO RÁPIDO DEL CLUSTER
# ==========================================

# Estado general
kubectl get nodes
kubectl get pods -A | grep -v "Running\|Completed"
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# ==========================================
# DIAGNÓSTICO DE UN POD ESPECÍFICO
# ==========================================

# Ver estado y última razón de fallo
kubectl describe pod <pod> -n <namespace>

# Logs actuales
kubectl logs <pod> -n <namespace>

# Logs del crash anterior
kubectl logs <pod> -n <namespace> --previous

# Logs en tiempo real
kubectl logs -f <pod> -n <namespace>

# Shell interactivo para diagnóstico
kubectl exec -it <pod> -n <namespace> -- /bin/sh

# ==========================================
# DIAGNÓSTICO DE RED
# ==========================================

# Ver endpoints de un Service
kubectl describe service <service> -n <namespace>
kubectl get endpoints <service> -n <namespace>

# Test de conectividad desde un pod temporal
kubectl run nettest --image=busybox:1.36 --restart=Never -- \
  wget -qO- http://<service>.<namespace>.svc.cluster.local

# ==========================================
# DIAGNÓSTICO DE RECURSOS
# ==========================================

# Uso actual
kubectl top nodes
kubectl top pods -A

# Recursos solicitados vs disponibles
kubectl describe node <nodo> | grep -A10 "Allocated resources"

# ==========================================
# DIAGNÓSTICO DE ALMACENAMIENTO
# ==========================================

kubectl get pv
kubectl get pvc -A
kubectl describe pvc <pvc> -n <namespace>
```

---

## Verificación final del curso

```bash
# Health check completo del cluster
echo "=== NODOS ===" && kubectl get nodes
echo "=== PODS CON PROBLEMAS ===" && kubectl get pods -A | grep -v "Running\|Completed\|NAME"
echo "=== WARNINGS ===" && kubectl get events -A --field-selector type=Warning | tail -10
echo "=== PVCs ===" && kubectl get pvc -A | grep -v "Bound"
echo "=== HPAS ===" && kubectl get hpa -A
```

---

## Preguntas de reflexión finales del curso

1. ¿Cómo organizarías el trabajo de un equipo de admins para que nadie haga cambios manuales en producción?
2. Si un pod lleva 3 horas en Pending, ¿por dónde empiezas el diagnóstico?
3. ¿Qué tres alertas considerarías absolutamente críticas en cualquier cluster de producción?
4. ¿Cuál es la diferencia entre un operador y un Job que corre periódicamente?
5. ¿Cómo garantizarías que un backup de Velero es válido y restaurable?
