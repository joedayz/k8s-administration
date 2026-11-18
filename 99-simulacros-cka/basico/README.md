# Lab 10 — Básico: Retos Rápidos (Workloads y Services)

## Objetivo
Resolver ejercicios cortos con límite de tiempo, estilo examen CKA. Cada reto dura ~5 minutos.

## Duración estimada
60 minutos (10 retos × 5 min + revisión)

---

## Reto 1 — Crear un Pod con un comando específico (2 min)

> Crea un pod llamado `multi-contenedor` en el namespace `cka` con dos contenedores:
> - `nginx` con imagen `nginx:alpine`
> - `sidecar` con imagen `busybox:1.36` que ejecute `sleep 3600`

```bash
# Solución
kubectl create namespace cka
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: multi-contenedor
  namespace: cka
spec:
  containers:
  - name: nginx
    image: nginx:alpine
  - name: sidecar
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

**Verificación:**
```bash
kubectl get pod multi-contenedor -n cka -o wide
# Debe mostrar 2/2 Running
```

---

## Reto 2 — Deployment con 4 réplicas en nodos distintos (5 min)

> Crea un deployment llamado `web-app` con 4 réplicas de `nginx:alpine`
> en el namespace `cka`. Los pods deben distribuirse en nodos distintos
> (ningún nodo con más de 1 pod, usando podAntiAffinity preferred).

```bash
# Solución
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: cka
spec:
  replicas: 4
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: web-app
              topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: "20m"
            memory: "32Mi"
EOF
```

**Verificación:**
```bash
kubectl get pods -n cka -l app=web-app -o wide
# Los pods deben estar en nodos distintos (como máximo)
```

---

## Reto 3 — Service NodePort (3 min)

> Crea un Service tipo NodePort para el deployment `web-app`
> en el namespace `cka` con:
> - Nombre: `web-svc`
> - Puerto del servicio: 80
> - TargetPort: 80
> - NodePort: 30090

```bash
kubectl expose deployment web-app \
  --name=web-svc \
  --type=NodePort \
  --port=80 \
  --target-port=80 \
  --namespace=cka \
  --dry-run=client -o yaml > svc.yaml
# Editar el NodePort a 30090
kubectl apply -f svc.yaml
```

**Verificación:**
```bash
kubectl get svc web-svc -n cka
# NodePort debe ser 30090
```

---

## Reto 4 — Escalar un Deployment (1 min)

> Escala el deployment `web-app` a 7 réplicas y verifica
> cuántos pods están en Running.

```bash
kubectl scale deployment web-app --replicas=7 -n cka
kubectl get pods -n cka -l app=web-app | wc -l
```

---

## Reto 5 — Crear un ConfigMap y consumirlo (4 min)

> Crea un ConfigMap llamado `app-config` en el namespace `cka`
> con la clave `LOG_LEVEL=DEBUG`. Crea un pod `config-pod`
> que consuma esta variable de entorno.

```bash
kubectl create configmap app-config \
  --from-literal=LOG_LEVEL=DEBUG \
  -n cka

kubectl run config-pod --image=alpine:3.19 -n cka \
  --dry-run=client -o yaml > config-pod.yaml
# Editar para añadir envFrom
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-pod
  namespace: cka
spec:
  containers:
  - name: alpine
    image: alpine:3.19
    command: ["sleep", "3600"]
    envFrom:
    - configMapRef:
        name: app-config
```

**Verificación:**
```bash
kubectl exec config-pod -n cka -- env | grep LOG_LEVEL
# Debe mostrar: LOG_LEVEL=DEBUG
```

---

## Reto 6 — Crear un Job (3 min)

> Crea un Job llamado `pi-calc` en el namespace `cka`
> que ejecute `perl -Mbignum=bpi -wle 'print bpi(2000)'`
> con la imagen `perl:5.34`. El job debe completarse con 1 intento.

```bash
kubectl create job pi-calc \
  --image=perl:5.34 \
  -n cka \
  -- perl -Mbignum=bpi -wle 'print bpi(2000)' \
```

**Verificación:**
```bash
kubectl get job pi-calc -n cka
kubectl logs job/pi-calc -n cka
```

---

## Reto 7 — Listar pods por nodo con JSONPath (3 min)

> Usa JSONPath para listar todos los pods del cluster con su nombre y el nodo
> donde están corriendo. Ordena por nombre.

```bash
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' | sort
```

---

## Reto 8 — Fijar un pod a un nodo específico (2 min)

> Crea un pod llamado `nodo-fijo` en el namespace `cka`
> que solo pueda ejecutarse en `k3s-worker` usando nodeSelector.

```bash
kubectl run nodo-fijo --image=nginx:alpine -n cka \
  --dry-run=client -o yaml > nodo-fijo.yaml
# Añadir nodeSelector
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nodo-fijo
  namespace: cka
spec:
  nodeSelector:
    kubernetes.io/hostname: k3s-worker
  containers:
  - name: nginx
    image: nginx:alpine
```

**Verificación:**
```bash
kubectl get pod nodo-fijo -n cka -o wide
# NODE debe ser k3s-worker
```

---

## Reto 9 — Crear un Secret y montarlo como archivo (4 min)

> Crea un Secret llamado `credenciales` en el namespace `cka`
> con `usuario=admin` y `password=s3cr3t`. Crea un pod `secret-pod`
> que monte el secret como archivos en `/etc/secret`.

```bash
kubectl create secret generic credenciales \
  --from-literal=usuario=admin \
  --from-literal=password=s3cr3t \
  -n cka

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secret-pod
  namespace: cka
spec:
  containers:
  - name: alpine
    image: alpine:3.19
    command: ["sleep", "3600"]
    volumeMounts:
    - name: secret-vol
      mountPath: /etc/secret
      readOnly: true
  volumes:
  - name: secret-vol
    secret:
      secretName: credenciales
EOF
```

**Verificación:**
```bash
kubectl exec secret-pod -n cka -- ls /etc/secret
kubectl exec secret-pod -n cka -- cat /etc/secret/usuario
kubectl exec secret-pod -n cka -- cat /etc/secret/password
```

---

## Reto 10 — Taint un nodo y verificar (3 min)

> Aplica un taint `dedicado=true:NoSchedule` al nodo `k3s-worker2`.
> Crea un pod sin toleración y verifica que NO se agende en ese nodo.
> Limpia el taint al final.

```bash
kubectl taint nodes k3s-worker2 dedicado=true:NoSchedule

kubectl run test-taint --image=nginx:alpine -n cka --dry-run=client -o yaml | \
  kubectl apply -f -

sleep 5
kubectl get pod test-taint -n cka -o wide
# NODE no debe ser k3s-worker2

# Limpieza
kubectl taint nodes k3s-worker2 dedicado=true:NoSchedule-
kubectl delete pod test-taint -n cka
```

---

## Limpieza final

```bash
kubectl delete namespace cka
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué comando de kubectl te ahorra más tiempo en el examen?
2. ¿Cómo manejas un ejercicio que no logras resolver en 5 minutos?
3. ¿Qué recursos de kubectl explain son más útiles de memorizar?
4. ¿Por qué es importante usar `--dry-run=client -o yaml` en el examen?
