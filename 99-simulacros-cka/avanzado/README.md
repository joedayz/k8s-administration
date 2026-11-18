# Lab 10 — Avanzado: Retos Completos estilo Examen CKA

## Objetivo
Resolver escenarios complejos que combinan múltiples dominios del CKA, con un límite de tiempo más ajustado. Cada reto dura ~15 minutos.

## Duración estimada
75 minutos (4 retos × 15 min + revisión)

---

## Reto 1 — Troubleshooting completo: cluster con 4 problemas (15 min)

> Se ha desplegado una aplicación en el namespace `cka-trouble` con varios
> problemas. Diagnostica y corrige TODOS:
>
> 1. El deployment `frontend` tiene una imagen incorrecta → debe ser `nginx:alpine`
> 2. El service `frontend-svc` no tiene endpoints → el selector es incorrecto
> 3. El pod `db-pod` está en Pending → necesita menos recursos
> 4. El pod `api-pod` está en CrashLoopBackOff → el comando de entrada es incorrecto

```bash
# Setup
kubectl create namespace cka-trouble
kubectl apply -f escenario-trouble.yaml
sleep 30

# DIAGNÓSTICO INICIAL
kubectl get pods -n cka-trouble
# Verás: frontend con ImagePullBackOff, db-pod Pending, api-pod CrashLoopBackOff
```

```bash
# Problema 1: imagen incorrecta
kubectl set image deployment/frontend nginx=nginx:alpine -n cka-trouble

# Problema 2: selector del service incorrecto
kubectl describe svc frontend-svc -n cka-trouble
kubectl get pods -n cka-trouble --show-labels
# El selector dice app=frontend-v2 pero los pods tienen app=frontend
kubectl patch svc frontend-svc -n cka-trouble \
  --type=merge -p '{"spec":{"selector":{"app":"frontend"}}}'

# Problema 3: pod Pending por recursos excesivos
kubectl describe pod db-pod -n cka-trouble | grep -A3 "Events:"
# Ve "Insufficient cpu/memory"
kubectl delete pod db-pod -n cka-trouble
# Recrear con recursos razonables
kubectl run db-pod --image=postgres:15-alpine \
  --env=POSTGRES_PASSWORD=secret \
  --requests=cpu=50m,memory=128Mi \
  -n cka-trouble

# Problema 4: CrashLoopBackOff
kubectl logs api-pod -n cka-trouble --previous
# El comando falla: sh -c "exit 1"
kubectl delete pod api-pod -n cka-trouble
kubectl run api-pod --image=nginx:alpine -n cka-trouble
```

**Verificación final:**
```bash
kubectl get pods -n cka-trouble
# TODOS deben estar Running
kubectl get endpoints frontend-svc -n cka-trouble
# Debe tener IPs
```

---

## Reto 2 — Backup, simular desastre y restaurar (15 min)

> 1. Crea un namespace `cka-backup` con un ConfigMap y un Deployment
> 2. Haz un backup de la base de datos del cluster
> 3. Borra el namespace (simulando un desastre)
> 4. Restaura desde el backup y verifica que los recursos volvieron

```bash
# Setup
kubectl create namespace cka-backup
kubectl create configmap datos-backup \
  --from-literal=valor=dato-importante \
  -n cka-backup
kubectl create deployment app-backup \
  --image=nginx:alpine --replicas=2 \
  -n cka-backup

# Verificar que existe
kubectl get all -n cka-backup

# Backup
multipass exec k3s-server -- sudo systemctl stop k3s
sleep 5
multipass exec k3s-server -- sudo cp \
  /var/lib/rancher/k3s/server/db/state.db \
  /tmp/cka-backup.db
multipass exec k3s-server -- sudo systemctl start k3s
sleep 15
kubectl get nodes

# Desastre: borrar el namespace
kubectl delete namespace cka-backup
kubectl get namespace cka-backup  # → NotFound

# Restaurar
multipass exec k3s-server -- sudo systemctl stop k3s
sleep 5
multipass exec k3s-server -- sudo cp \
  /tmp/cka-backup.db \
  /var/lib/rancher/k3s/server/db/state.db
multipass exec k3s-server -- sudo systemctl start k3s
sleep 20

# Verificar que los datos volvieron
kubectl get namespace cka-backup
kubectl get configmap datos-backup -n cka-backup
kubectl get deployment app-backup -n cka-backup

# Limpieza
kubectl delete namespace cka-backup
multipass exec k3s-server -- sudo rm /tmp/cka-backup.db
```

---

## Reto 3 — Nodos: cordon, drain y verificar resiliencia (15 min)

> 1. Despliega una aplicación con 6 réplicas distribuidas en todos los nodos
> 2. Cordon un nodo y verifica que no entran pods nuevos
> 3. Drena el nodo y verifica que los pods migran sin interrupción
> 4. Simula mantenimiento (reboot del nodo)
> 5. Uncordon y verifica que el nodo vuelve a aceptar trabajo
> 6. Comprueba que la aplicación estuvo disponible durante todo el proceso

```bash
kubectl create namespace cka-resilience

# Deployment con 6 réplicas y anti-affinity
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resilient-app
  namespace: cka-resilience
spec:
  replicas: 6
  selector:
    matchLabels:
      app: resilient
  template:
    metadata:
      labels:
        app: resilient
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: resilient
              topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: "10m"
            memory: "16Mi"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 3
EOF

sleep 15
kubectl get pods -n cka-resilience -o wide
# 6 pods distribuidos entre los 3 nodos

# Service para verificar disponibilidad
kubectl expose deployment resilient-app --port=80 -n cka-resilience

# Cordon
kubectl cordon k3s-worker
kubectl get nodes

# Drain
kubectl drain k3s-worker \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30

# Verificar que los pods migraron
sleep 10
kubectl get pods -n cka-resilience -o wide
# Ningún pod en k3s-worker

# Verificar disponibilidad
kubectl run avail-test --image=busybox:1.36 --rm -it -n cka-resilience \
  -- sh -c "wget -qO- http://resilient-app --timeout=5"

# Simular mantenimiento
multipass restart k3s-worker
sleep 20

# Uncordon
kubectl uncordon k3s-worker
kubectl get nodes

# Redistribuir
kubectl rollout restart deployment resilient-app -n cka-resilience
sleep 15
kubectl get pods -n cka-resilience -o wide

# Limpieza
kubectl delete namespace cka-resilience
```

---

## Reto 4 — Ejercicio integral: despliegue completo seguro (15 min)

> Despliega una aplicación web completa en el namespace `cka-final` con:
> 1. Un Deployment `web-final` con 3 réplicas de `nginx:alpine`
> 2. Cada pod consume un ConfigMap con configuración y un Secret con credenciales
> 3. Un Service ClusterIP `web-final-svc` en el puerto 80
> 4. Una NetworkPolicy que solo permite tráfico desde pods con label `access=allowed`
> 5. Un ServiceAccount `web-sa` con permisos de solo lectura en el namespace
> 6. Verifica que un pod SIN el label no puede acceder, pero uno CON el label sí

```bash
kubectl create namespace cka-final

# 1. ConfigMap y Secret
kubectl create configmap web-config \
  --from-literal=APP_ENV=production \
  --from-literal=MAX_CONNECTIONS=100 \
  -n cka-final

kubectl create secret generic web-creds \
  --from-literal=db_user=admin \
  --from-literal=db_pass=s3cr3t \
  -n cka-final

# 2. ServiceAccount + RBAC
kubectl create serviceaccount web-sa -n cka-final
kubectl create role web-reader \
  --verb=get,list,watch \
  --resource=pods,services \
  -n cka-final
kubectl create rolebinding web-reader-binding \
  --role=web-reader \
  --serviceaccount=cka-final:web-sa \
  -n cka-final

# 3. Deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-final
  namespace: cka-final
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-final
  template:
    metadata:
      labels:
        app: web-final
    spec:
      serviceAccountName: web-sa
      containers:
      - name: nginx
        image: nginx:alpine
        envFrom:
        - configMapRef:
            name: web-config
        - secretRef:
            name: web-creds
        resources:
          requests:
            cpu: "20m"
            memory: "32Mi"
EOF

# 4. Service
kubectl expose deployment web-final \
  --name=web-final-svc --port=80 -n cka-final

# 5. NetworkPolicy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-final-policy
  namespace: cka-final
spec:
  podSelector:
    matchLabels:
      app: web-final
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          access: allowed
    ports:
    - protocol: TCP
      port: 80
EOF

# 6. Verificación
# Pod CON label permitido
kubectl run allowed-client --image=busybox:1.36 --rm -it -n cka-final \
  --labels=access=allowed \
  -- sh -c "wget -qO- http://web-final-svc --timeout=5 && echo ACCESO OK"

# Pod SIN label — debe ser bloqueado
kubectl run blocked-client --image=busybox:1.36 --rm -it -n cka-final \
  -- sh -c "wget -qO- http://web-final-svc --timeout=3 || echo BLOQUEADO"

# Limpieza
kubectl delete namespace cka-final
```

---

## Limpieza final

```bash
kubectl delete namespace cka-trouble cka-final 2>/dev/null
```

---

## Preguntas de reflexión para el instructor

1. ¿Cuál es tu estrategia de tiempo para el examen CKA de 2 horas?
2. ¿Qué ejercicio de este módulo te resultó más difícil y por qué?
3. ¿Qué comandos deberías tener como alias antes de empezar el examen?
4. ¿Cómo te prepararías en las últimas 24 horas antes del examen?
